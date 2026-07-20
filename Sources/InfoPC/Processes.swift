import Foundation
import AppKit
import Darwin

/// Un processus avec sa consommation CPU / mémoire et son icône.
struct ProcInfo: Identifiable {
    let id: Int32          // pid
    let name: String
    let cpu: Double        // % CPU (peut dépasser 100 sur plusieurs cœurs)
    let mem: Double        // % de la RAM physique
    let icon: NSImage?
}

enum ProcessSampler {
    /// Les N processus les plus gourmands (score = CPU + mémoire).
    /// GPU par processus non exposé publiquement par macOS → non renseigné ici.
    static func top(_ limit: Int = 8) -> [ProcInfo] {
        guard let raw = runPS() else { return [] }

        struct Row { let pid: Int32; let cpu: Double; let mem: Double; let path: String }
        var rows: [Row] = []
        let me = Int32(getpid())

        for line in raw.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 4,
                  let pid = Int32(parts[0]),
                  let cpu = Double(parts[1]),
                  let mem = Double(parts[2]) else { continue }
            if pid == me { continue }             // on n'affiche pas InfoPC lui-même
            let path = parts[3...].joined(separator: " ")
            rows.append(Row(pid: pid, cpu: cpu, mem: mem, path: path))
        }

        let topRows = rows
            .sorted { ($0.cpu + $0.mem) > ($1.cpu + $1.mem) }
            .prefix(limit)

        return topRows.map { row in
            let running = NSRunningApplication(processIdentifier: row.pid)
            let name = running?.localizedName ?? (row.path as NSString).lastPathComponent
            let icon = running?.icon ?? fallbackIcon(forPath: row.path)
            return ProcInfo(id: row.pid, name: name, cpu: row.cpu, mem: row.mem, icon: icon)
        }
    }

    /// Termine un processus (SIGTERM). Sans privilège root, ne peut agir que sur
    /// les processus appartenant à l'utilisateur.
    @discardableResult
    static func kill(_ pid: Int32) -> Bool {
        Darwin.kill(pid, SIGTERM) == 0
    }

    private static func runPS() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-Ao", "pid=,pcpu=,pmem=,comm="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private static var iconCache: [String: NSImage] = [:]

    private static func fallbackIcon(forPath path: String) -> NSImage? {
        if let cached = iconCache[path] { return cached }
        let icon: NSImage
        if FileManager.default.fileExists(atPath: path) {
            icon = NSWorkspace.shared.icon(forFile: path)
        } else {
            icon = NSImage(systemSymbolName: "gearshape.fill",
                           accessibilityDescription: nil) ?? NSImage()
        }
        iconCache[path] = icon
        return icon
    }
}
