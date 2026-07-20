import Foundation

/// Usage Claude Code du bloc de 5 h en cours, estimé à partir des transcripts
/// JSONL locaux de `~/.claude/projects` (donc automatiquement le compte de
/// l'utilisateur connecté). Le comptage additionne tous les tokens
/// (input + output + création de cache + lecture de cache), comme ccusage.
///
/// Le serveur Anthropic n'expose aucune limite exacte en local ; comme référence
/// on prend — à la manière de `ccusage --token-limit max` — le plus gros bloc de
/// 5 h jamais observé dans l'historique. La jauge montre donc l'usage du bloc
/// courant rapporté à ce maximum personnel.
struct ClaudeBlockUsage {
    let tokens: Int
    let blockStart: Date
    let blockEnd: Date
    let isActive: Bool
}

enum ClaudeUsageReader {
    private struct Entry {
        let date: Date
        let tokens: Int
    }

    private static var projectsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
    }

    // MARK: - API publique

    /// Bloc de 5 h en cours (fichiers modifiés dans les ~13 dernières heures).
    static func currentBlock(now: Date = Date()) -> ClaudeBlockUsage? {
        let entries = loadEntries(modifiedSince: now.addingTimeInterval(-13 * 3600))
        guard let last = buildBlocks(entries).last else { return nil }
        let end = last.start.addingTimeInterval(5 * 3600)
        let active = now < end
        return ClaudeBlockUsage(tokens: active ? last.tokens : 0,
                                blockStart: last.start,
                                blockEnd: end,
                                isActive: active)
    }

    /// Plus gros bloc de 5 h de tout l'historique (dénominateur de la jauge).
    static func historicalMaxBlockTokens() -> Int {
        let entries = loadEntries(modifiedSince: nil)
        return buildBlocks(entries).map(\.tokens).max() ?? 0
    }

    // MARK: - Lecture & découpage

    /// Charge et dédoublonne les entrées avec `usage`. `modifiedSince == nil`
    /// scanne tout l'historique ; sinon on ignore les fichiers trop anciens.
    private static func loadEntries(modifiedSince horizon: Date?) -> [Entry] {
        guard let enumerator = FileManager.default.enumerator(
            at: projectsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { return [] }

        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso = ISO8601DateFormatter()

        var entries: [Entry] = []
        var seen = Set<String>()

        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            if let horizon {
                let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                if mtime < horizon { continue }
            }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in content.split(separator: "\n") {
                guard line.contains("\"usage\"") else { continue }
                guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      let tsString = obj["timestamp"] as? String,
                      let message = obj["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any],
                      let date = isoFrac.date(from: tsString) ?? iso.date(from: tsString) else { continue }
                if let horizon, date < horizon { continue }

                let id = (message["id"] as? String ?? "") + (obj["requestId"] as? String ?? "")
                if !id.isEmpty {
                    if seen.contains(id) { continue }
                    seen.insert(id)
                }
                let tokens = (usage["input_tokens"] as? Int ?? 0)
                    + (usage["output_tokens"] as? Int ?? 0)
                    + (usage["cache_creation_input_tokens"] as? Int ?? 0)
                    + (usage["cache_read_input_tokens"] as? Int ?? 0)
                entries.append(Entry(date: date, tokens: tokens))
            }
        }
        return entries.sorted { $0.date < $1.date }
    }

    /// Découpe en blocs de 5 h façon ccusage : un nouveau bloc démarre au premier
    /// message (calé à l'heure pleine), puis dès qu'on dépasse 5 h depuis le début
    /// du bloc ou qu'un silence de 5 h sépare deux messages.
    private static func buildBlocks(_ entries: [Entry]) -> [(start: Date, tokens: Int)] {
        var blocks: [(Date, Int)] = []
        var start: Date?
        var tokens = 0
        var last: Date?
        let fiveHours: TimeInterval = 5 * 3600

        for e in entries {
            if let s = start, let l = last,
               e.date >= s.addingTimeInterval(fiveHours) || e.date.timeIntervalSince(l) >= fiveHours {
                blocks.append((s, tokens))
                start = floorToHour(e.date); tokens = 0
            } else if start == nil {
                start = floorToHour(e.date); tokens = 0
            }
            tokens += e.tokens
            last = e.date
        }
        if let s = start { blocks.append((s, tokens)) }
        return blocks
    }

    private static func floorToHour(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
    }

    // MARK: - Formatage

    static func formatTokens(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...: return String(format: "%.0fk", Double(n) / 1_000)
        default: return "\(n)"
        }
    }
}
