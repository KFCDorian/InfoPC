import Foundation
import AppKit
import Darwin

/// Un processus individuel avec sa consommation CPU / mémoire.
struct ProcInfo: Identifiable {
    let id: Int32          // pid
    let name: String
    let cpu: Double        // % CPU (peut dépasser 100 sur plusieurs cœurs)
    let mem: Double        // % de la RAM physique
}

/// Un groupe d'processus appartenant à la même application (ex. Chrome et
/// tous ses processus d'aide), avec consommation agrégée et icône.
struct ProcGroup: Identifiable {
    let id: String         // clé de regroupement (bundle .app ou nom)
    let name: String
    let icon: NSImage?
    let cpu: Double        // somme CPU des membres
    let mem: Double        // somme mémoire des membres
    let members: [ProcInfo]
    var count: Int { members.count }
    var pids: [Int32] { members.map(\.id) }
}

/// Critère de tri de la liste des processus.
enum ProcSortKey: String, CaseIterable, Identifiable {
    case cpu, memory
    var id: String { rawValue }
    @MainActor var label: String { self == .cpu ? "CPU" : t("Mémoire", "Memory") }
}

enum ProcessSampler {
    /// Les N groupes d'applications les plus gourmands, triés selon `sortBy`.
    /// Les processus d'une même app (Chrome + ses helpers) sont fusionnés.
    static func topGroups(_ limit: Int = 12, sortBy: ProcSortKey = .cpu) -> [ProcGroup] {
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

        // Regroupement par application (bundle .app) ou, à défaut, par nom.
        struct Accum { var name: String; var path: String; var cpu = 0.0; var mem = 0.0; var members: [ProcInfo] = [] }
        var groups: [String: Accum] = [:]

        for row in rows {
            let fullPath = pidPath(row.pid) ?? row.path
            let bundle = appBundlePath(fromPath: fullPath)
            let running = NSRunningApplication(processIdentifier: row.pid)
            // Clé de regroupement : bundle .app si possible, sinon nom d'exécutable.
            let procName = running?.localizedName ?? (fullPath as NSString).lastPathComponent
            let key = bundle ?? procName
            let groupName = bundle.map { ($0 as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "") }
                ?? procName

            let member = ProcInfo(id: row.pid, name: procName, cpu: row.cpu, mem: row.mem)
            if groups[key] == nil {
                groups[key] = Accum(name: groupName, path: bundle ?? fullPath)
            }
            groups[key]?.cpu += row.cpu
            groups[key]?.mem += row.mem
            groups[key]?.members.append(member)
        }

        let sorted = groups.map { (key, acc) -> ProcGroup in
            let icon = resolveIcon(path: acc.path)
            let members = acc.members.sorted {
                sortBy == .cpu ? $0.cpu > $1.cpu : $0.mem > $1.mem
            }
            return ProcGroup(id: key, name: acc.name, icon: icon,
                             cpu: acc.cpu, mem: acc.mem, members: members)
        }
        .sorted { sortBy == .cpu ? $0.cpu > $1.cpu : $0.mem > $1.mem }

        return Array(sorted.prefix(limit))
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

    /// Icône couleur d'une app à partir de son chemin (bundle `.app` ou exécutable).
    /// Renvoie `nil` pour les daemons/CLI sans bundle → la vue met un symbole neutre
    /// (plutôt qu'une icône « exécutable » noire).
    private static func resolveIcon(path: String) -> NSImage? {
        let appPath = path.hasSuffix(".app") ? path : appBundlePath(fromPath: path)
        guard let appPath else { return nil }
        if let cached = iconCache[appPath] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: appPath)
        iconCache[appPath] = icon
        return icon
    }

    /// Chemin absolu complet d'un processus via libproc (fiable, non tronqué).
    private static func pidPath(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)   // PROC_PIDPATHINFO_MAXSIZE
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(cString: buffer) : nil
    }

    /// Remonte au bundle `.app` le plus externe : `/…/Foo.app/Contents/MacOS/Foo`
    /// → `/…/Foo.app`. Gère aussi les helpers imbriqués (première occurrence).
    private static func appBundlePath(fromPath path: String) -> String? {
        if let range = path.range(of: ".app/") {
            return String(path[..<range.lowerBound]) + ".app"
        }
        if path.hasSuffix(".app") { return path }
        return nil
    }
}
