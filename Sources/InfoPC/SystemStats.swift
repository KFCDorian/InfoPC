import Foundation
import IOKit
import SMCCore

/// Résultat d'un échantillon CPU : usage global + usage par cœur logique.
struct CPUSample {
    let overall: Double
    let perCore: [Double]
}

/// Sonde CPU : usage global et par cœur via host_processor_info (delta entre
/// deux appels). Le nombre de cœurs Performance / Efficience vient de sysctl.
final class CPUSampler {
    private var previousTicks: [(user: UInt32, system: UInt32, nice: UInt32, idle: UInt32)] = []

    /// Nombre de cœurs Performance (perflevel0) et Efficience (perflevel1).
    let performanceCores: Int
    let efficiencyCores: Int

    init() {
        performanceCores = CPUSampler.sysctlInt("hw.perflevel0.logicalcpu") ?? 0
        efficiencyCores = CPUSampler.sysctlInt("hw.perflevel1.logicalcpu") ?? 0
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int = 0
        var size = MemoryLayout<Int>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? value : nil
    }

    func sample() -> CPUSample? {
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
        var perCore: [Double] = []
        for (prev, cur) in zip(previousTicks, ticks) {
            let dUser = Double(cur.0 &- prev.user)
            let dSys = Double(cur.1 &- prev.system)
            let dNice = Double(cur.2 &- prev.nice)
            let dIdle = Double(cur.3 &- prev.idle)
            let coreBusy = dUser + dSys + dNice
            let coreTotal = coreBusy + dIdle
            perCore.append(coreTotal > 0 ? coreBusy / coreTotal * 100.0 : 0)
            busy += coreBusy
            total += coreTotal
        }
        guard total > 0 else { return nil }
        return CPUSample(overall: busy / total * 100.0, perCore: perCore)
    }
}

/// Sonde réseau : débit montant/descendant en octets/s, calculé sur le delta
/// des compteurs d'octets des interfaces physiques (hors loopback).
final class NetworkSampler {
    private var previous: (rx: UInt64, tx: UInt64, time: Date)?

    struct Throughput {
        let rxBytesPerSec: Double   // téléchargement
        let txBytesPerSec: Double   // envoi
    }

    func sample() -> Throughput? {
        var counters = readCounters()
        let now = Date()
        defer { previous = (counters.rx, counters.tx, now) }
        guard let prev = previous else { return nil }
        let dt = now.timeIntervalSince(prev.time)
        guard dt > 0 else { return nil }
        // Protection contre un reset de compteur
        let rxDelta = counters.rx >= prev.rx ? counters.rx - prev.rx : 0
        let txDelta = counters.tx >= prev.tx ? counters.tx - prev.tx : 0
        return Throughput(rxBytesPerSec: Double(rxDelta) / dt,
                          txBytesPerSec: Double(txDelta) / dt)
    }

    private func readCounters() -> (rx: UInt64, tx: UInt64) {
        var rx: UInt64 = 0, tx: UInt64 = 0
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return (0, 0) }
        defer { freeifaddrs(addrs) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }
            let name = String(cString: cur.pointee.ifa_name)
            if name == "lo0" { continue }                    // loopback
            guard let addr = cur.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_LINK),
                  let data = cur.pointee.ifa_data else { continue }
            let stats = data.assumingMemoryBound(to: if_data.self)
            rx += UInt64(stats.pointee.ifi_ibytes)
            tx += UInt64(stats.pointee.ifi_obytes)
        }
        return (rx, tx)
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

    struct DiskUsage {
        let freeBytes: Int64
        let totalBytes: Int64
        var usedBytes: Int64 { totalBytes - freeBytes }
        var fraction: Double { totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0 }
    }

    /// Espace du volume de démarrage (« / »).
    static func diskUsage() -> DiskUsage? {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey]),
              let total = values.volumeTotalCapacity,
              let free = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return DiskUsage(freeBytes: Int64(free), totalBytes: Int64(total))
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
