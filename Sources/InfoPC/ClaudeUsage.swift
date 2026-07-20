import Foundation

/// Estime l'usage Claude Code du bloc de 5 h en cours en analysant les
/// transcripts JSONL de ~/.claude/projects (comptage de tous les tokens :
/// input + output + création de cache + lecture de cache, comme ccusage).
///
/// La limite affichée s'auto-calibre : on retient le plus gros bloc jamais
/// observé (persisté dans UserDefaults), modifiable dans le popover.
struct ClaudeBlockUsage {
    let tokens: Int
    let blockStart: Date
    let blockEnd: Date
    let isActive: Bool
}

enum ClaudeUsageReader {
    static let defaultsMaxKey = "claudeMaxTokensObserved"
    static let defaultLimit = 50_000_000

    static var tokenLimit: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: defaultsMaxKey)
            return v > 0 ? v : defaultLimit
        }
        set { UserDefaults.standard.set(newValue, forKey: defaultsMaxKey) }
    }

    private struct Entry {
        let date: Date
        let tokens: Int
        let messageId: String
    }

    static func currentBlock(now: Date = Date()) -> ClaudeBlockUsage? {
        let projectsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
        guard let enumerator = FileManager.default.enumerator(
            at: projectsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { return nil }

        // Seuls les fichiers modifiés dans les ~13 dernières heures peuvent
        // contenir des entrées du bloc en cours ou du précédent.
        let horizon = now.addingTimeInterval(-13 * 3600)
        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            if mtime > horizon { files.append(url) }
        }
        guard !files.isEmpty else { return nil }

        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso = ISO8601DateFormatter()

        var entries: [Entry] = []
        var seen = Set<String>()
        for file in files {
            guard let data = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for line in data.split(separator: "\n") {
                guard line.contains("\"usage\"") else { continue }
                guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      let tsString = obj["timestamp"] as? String,
                      let message = obj["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any] else { continue }
                guard let date = isoFrac.date(from: tsString) ?? iso.date(from: tsString),
                      date > horizon else { continue }

                let id = (message["id"] as? String ?? "") + (obj["requestId"] as? String ?? "")
                if !id.isEmpty {
                    if seen.contains(id) { continue }
                    seen.insert(id)
                }
                let tokens = (usage["input_tokens"] as? Int ?? 0)
                    + (usage["output_tokens"] as? Int ?? 0)
                    + (usage["cache_creation_input_tokens"] as? Int ?? 0)
                    + (usage["cache_read_input_tokens"] as? Int ?? 0)
                entries.append(Entry(date: date, tokens: tokens, messageId: id))
            }
        }
        guard !entries.isEmpty else { return nil }
        entries.sort { $0.date < $1.date }

        // Blocs de 5 h alignés sur l'heure pleine du premier message du bloc
        var blockStart = floorToHour(entries[0].date)
        var blockTokens = 0
        for entry in entries {
            if entry.date >= blockStart.addingTimeInterval(5 * 3600) {
                blockStart = floorToHour(entry.date)
                blockTokens = 0
            }
            blockTokens += entry.tokens
        }

        let blockEnd = blockStart.addingTimeInterval(5 * 3600)
        let isActive = now < blockEnd
        if isActive, blockTokens > tokenLimit {
            tokenLimit = blockTokens  // auto-calibration de la limite
        }
        return ClaudeBlockUsage(tokens: isActive ? blockTokens : 0,
                                blockStart: blockStart,
                                blockEnd: blockEnd,
                                isActive: isActive)
    }

    private static func floorToHour(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
    }

    static func formatTokens(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...: return String(format: "%.0fk", Double(n) / 1_000)
        default: return "\(n)"
        }
    }
}
