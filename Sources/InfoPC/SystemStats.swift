import Foundation
import IOKit
import SMCCore

/// Sonde CPU : usage global en % via host_processor_info (delta entre deux appels)
final class CPUSampler {
    private var previousTicks: [(user: UInt32, system: UInt32, nice: UInt32, idle: UInt32)] = []

    func sample() -> Double? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let kr = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                     &cpuCount, &info, &infoCount)
        guard kr == KERN_SUCCESS, let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }

        var ticks: [(UInt32, UInt32, UInt32, UInt32)] = []
        for cpu in 0..<Int(cpuCount) {
            let base = cpu * Int(CPU_STATE_MAX)
            ticks.append((UInt32(info[base + Int(CPU_STATE_USER)]),
                          UInt32(info[base + Int(CPU_STATE_SYSTEM)]),
                          UInt32(info[base + Int(CPU_STATE_NICE)]),
                          UInt32(info[base + Int(CPU_STATE_IDLE)])))
        }

        defer { previousTicks = ticks }
        guard previousTicks.count == ticks.count else { return nil }

        var busy: Double = 0, total: Double = 0
        for (prev, cur) in zip(previousTicks, ticks) {
            let dUser = Double(cur.0 &- prev.user)
            let dSys = Double(cur.1 &- prev.system)
            let dNice = Double(cur.2 &- prev.nice)
            let dIdle = Double(cur.3 &- prev.idle)
            busy += dUser + dSys + dNice
            total += dUser + dSys + dNice + dIdle
        }
        guard total > 0 else { return nil }
        return busy / total * 100.0
    }
}

enum SystemStats {
    /// Utilisation GPU en % via IORegistry (PerformanceStatistics de l'accélérateur)
    static func gpuUsage() -> Double? {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOAccelerator"),
                                           &iter) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iter) }

        while true {
            let entry = IOIteratorNext(iter)
            guard entry != 0 else { break }
            defer { IOObjectRelease(entry) }

            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any],
                  let perf = dict["PerformanceStatistics"] as? [String: Any] else { continue }

            if let util = perf["Device Utilization %"] as? NSNumber {
                return util.doubleValue
            }
        }
        return nil
    }

    struct MemoryUsage {
        let usedBytes: UInt64
        let totalBytes: UInt64
        var fraction: Double { totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0 }
    }

    /// Mémoire utilisée = active + wired + compressée (proche d'Activity Monitor)
    static func memoryUsage() -> MemoryUsage? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let pageSize = UInt64(vm_kernel_page_size)
        let used = (UInt64(stats.active_count) + UInt64(stats.wire_count)
                    + UInt64(stats.compressor_page_count)) * pageSize
        return MemoryUsage(usedBytes: used,
                           totalBytes: ProcessInfo.processInfo.physicalMemory)
    }
}

/// Capteurs de température via SMC : sur Apple Silicon les sondes CPU commencent
/// par "Tp" et les sondes GPU par "Tg" (type flt). On garde la valeur max
/// (capteur le plus chaud), la plus parlante pour l'utilisateur.
final class TemperatureSensors {
    private let smc: SMC
    private var cpuKeys: [String] = []
    private var gpuKeys: [String] = []

    init(smc: SMC) {
        self.smc = smc
        let candidates = smc.keys(withPrefixes: ["Tp", "Tg"])
        for key in candidates {
            guard let value = try? smc.readNumber(key), value > 10, value < 120 else { continue }
            if key.hasPrefix("Tp") { cpuKeys.append(key) }
            else { gpuKeys.append(key) }
        }
    }

    private func maxTemp(_ keys: [String]) -> Double? {
        let values = keys.compactMap { try? smc.readNumber($0) }
            .filter { $0 > 10 && $0 < 120 }
        return values.max()
    }

    var cpuTemp: Double? { maxTemp(cpuKeys) }
    var gpuTemp: Double? { maxTemp(gpuKeys) }
}
