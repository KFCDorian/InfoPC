import Foundation
import IOKit

// Structures alignées sur l'interface AppleSMC (80 octets au total)
struct SMCVers {
    var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0
    var release: UInt16 = 0
}

struct SMCPLimit {
    var version: UInt16 = 0, length: UInt16 = 0
    var cpuPLimit: UInt32 = 0, gpuPLimit: UInt32 = 0, memPLimit: UInt32 = 0
}

struct SMCKeyInfo {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
    // Padding explicite : en C la struct est paddée à 12 octets, pas en Swift.
    // Sans lui, SMCKeyData fait 76 octets au lieu des 80 attendus par AppleSMC.
    var padding: (UInt8, UInt8, UInt8) = (0, 0, 0)
}

struct SMCKeyData {
    var key: UInt32 = 0
    var vers = SMCVers()
    var pLimitData = SMCPLimit()
    var keyInfo = SMCKeyInfo()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
        (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
         0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

private let kSMCReadKey: UInt8 = 5
private let kSMCWriteKey: UInt8 = 6
private let kSMCGetKeyFromIndex: UInt8 = 8
private let kSMCGetKeyInfo: UInt8 = 9

public enum SMCError: Error, CustomStringConvertible {
    case serviceNotFound
    case openFailed(kern_return_t)
    case callFailed(kern_return_t)
    case keyError(String, UInt8)

    public var description: String {
        switch self {
        case .serviceNotFound: return "Service AppleSMC introuvable"
        case .openFailed(let k): return "IOServiceOpen a échoué (\(k))"
        case .callFailed(let k): return "Appel SMC échoué (\(k))"
        case .keyError(let key, let r): return "Clé SMC \(key) : erreur \(r)"
        }
    }
}

func fourCC(_ s: String) -> UInt32 {
    var result: UInt32 = 0
    for c in s.utf8 { result = (result << 8) | UInt32(c) }
    return result
}

func fourCCString(_ v: UInt32) -> String {
    let bytes = [UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF),
                 UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
    return String(bytes: bytes, encoding: .ascii) ?? "????"
}

public final class SMC {
    private var conn: io_connect_t = 0
    private var keyInfoCache: [UInt32: SMCKeyInfo] = [:]
    private let lock = NSLock()

    public init() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCError.serviceNotFound }
        defer { IOObjectRelease(service) }
        let kr = IOServiceOpen(service, mach_task_self_, 0, &conn)
        guard kr == KERN_SUCCESS else { throw SMCError.openFailed(kr) }
    }

    deinit {
        if conn != 0 { IOServiceClose(conn) }
    }

    private func call(_ input: inout SMCKeyData) throws -> SMCKeyData {
        var output = SMCKeyData()
        var outSize = MemoryLayout<SMCKeyData>.stride
        let kr = IOConnectCallStructMethod(conn, 2, &input,
                                           MemoryLayout<SMCKeyData>.stride,
                                           &output, &outSize)
        guard kr == KERN_SUCCESS else { throw SMCError.callFailed(kr) }
        return output
    }

    private func keyInfo(_ key: UInt32) throws -> SMCKeyInfo {
        lock.lock()
        if let cached = keyInfoCache[key] { lock.unlock(); return cached }
        lock.unlock()

        var input = SMCKeyData()
        input.key = key
        input.data8 = kSMCGetKeyInfo
        let output = try call(&input)
        guard output.result == 0 else {
            throw SMCError.keyError(fourCCString(key), output.result)
        }
        lock.lock()
        keyInfoCache[key] = output.keyInfo
        lock.unlock()
        return output.keyInfo
    }

    /// Lit une clé et renvoie (type de données, octets bruts)
    public func read(_ keyName: String) throws -> (type: String, bytes: [UInt8]) {
        let key = fourCC(keyName)
        let info = try keyInfo(key)
        var input = SMCKeyData()
        input.key = key
        input.keyInfo.dataSize = info.dataSize
        input.data8 = kSMCReadKey
        var output = try call(&input)
        guard output.result == 0 else {
            throw SMCError.keyError(keyName, output.result)
        }
        let all = withUnsafeBytes(of: &output.bytes) { Array($0) }
        return (fourCCString(info.dataType), Array(all.prefix(Int(info.dataSize))))
    }

    /// Écrit des octets bruts dans une clé (nécessite root)
    public func write(_ keyName: String, bytes payload: [UInt8]) throws {
        let key = fourCC(keyName)
        let info = try keyInfo(key)
        var input = SMCKeyData()
        input.key = key
        input.keyInfo.dataSize = info.dataSize
        input.data8 = kSMCWriteKey
        withUnsafeMutableBytes(of: &input.bytes) { buf in
            for (i, b) in payload.prefix(32).enumerated() { buf[i] = b }
        }
        let output = try call(&input)
        guard output.result == 0 else {
            throw SMCError.keyError(keyName, output.result)
        }
    }

    /// Décode une valeur numérique selon son type SMC
    public func readNumber(_ keyName: String) throws -> Double {
        let (type, bytes) = try read(keyName)
        switch type {
        case "flt ":
            guard bytes.count >= 4 else { break }
            let v = bytes.withUnsafeBytes { $0.load(as: Float32.self) }
            return Double(v)
        case "fpe2":
            guard bytes.count >= 2 else { break }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4.0
        case "sp78":
            guard bytes.count >= 2 else { break }
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256.0
        case "ui8 ":
            guard let b = bytes.first else { break }
            return Double(b)
        case "ui16":
            guard bytes.count >= 2 else { break }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32":
            guard bytes.count >= 4 else { break }
            return Double(UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16
                        | UInt32(bytes[2]) << 8 | UInt32(bytes[3]))
        default:
            break
        }
        throw SMCError.keyError(keyName, 0xFF)
    }

    public func writeFloat(_ keyName: String, _ value: Float32) throws {
        var v = value
        let bytes = withUnsafeBytes(of: &v) { Array($0) }
        try write(keyName, bytes: bytes)
    }

    public func writeUInt8(_ keyName: String, _ value: UInt8) throws {
        try write(keyName, bytes: [value])
    }

    // MARK: - Énumération des clés

    public func keyCount() throws -> Int {
        Int(try readNumber("#KEY"))
    }

    public func key(at index: Int) throws -> String {
        var input = SMCKeyData()
        input.data8 = kSMCGetKeyFromIndex
        input.data32 = UInt32(index)
        let output = try call(&input)
        guard output.result == 0 else {
            throw SMCError.keyError("#idx\(index)", output.result)
        }
        return fourCCString(output.key)
    }

    /// Toutes les clés dont le nom commence par un des préfixes donnés
    public func keys(withPrefixes prefixes: [String]) -> [String] {
        guard let count = try? keyCount() else { return [] }
        var result: [String] = []
        for i in 0..<count {
            guard let name = try? key(at: i) else { continue }
            if prefixes.contains(where: { name.hasPrefix($0) }) {
                result.append(name)
            }
        }
        return result
    }

    // MARK: - Ventilateurs

    public func fanCount() -> Int {
        (try? Int(readNumber("FNum"))) ?? 0
    }

    public struct FanInfo {
        public let index: Int
        public let current: Double
        public let min: Double
        public let max: Double
        public let target: Double
    }

    public func fanInfo(_ i: Int) -> FanInfo? {
        guard let current = try? readNumber("F\(i)Ac") else { return nil }
        let min = (try? readNumber("F\(i)Mn")) ?? 0
        let max = (try? readNumber("F\(i)Mx")) ?? 0
        let target = (try? readNumber("F\(i)Tg")) ?? 0
        return FanInfo(index: i, current: current, min: min, max: max, target: target)
    }

    /// Force un ventilateur à un régime donné (root requis).
    /// Sur Apple Silicon la clé de mode est "F0md" (minuscules).
    public func setFanSpeed(_ i: Int, rpm: Double) throws {
        try writeUInt8("F\(i)md", 1)
        try writeFloat("F\(i)Tg", Float32(rpm))
    }

    /// Rend le contrôle du ventilateur au système (root requis)
    public func setFanAuto(_ i: Int) throws {
        try writeUInt8("F\(i)md", 0)
    }
}
