import Foundation

/// Usage réel du compte Claude, tel que renvoyé par l'endpoint OAuth
/// `https://api.anthropic.com/api/oauth/usage` (la source qui alimente la
/// commande `/usage` de Claude Code). `utilization` est le pourcentage
/// **réel** consommé sur la limite du plan de l'utilisateur.
struct ClaudeLiveUsage {
    let fiveHourPercent: Double
    let fiveHourResetsAt: Date?
    let sevenDayPercent: Double
    let sevenDayResetsAt: Date?
    /// Limite hebdomadaire spécifique au modèle en cours (ex. « Fable »).
    let modelName: String?
    let modelPercent: Double?
    let modelResetsAt: Date?
}

enum ClaudeUsageAPI {
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    /// Interroge l'endpoint avec le token OAuth du Trousseau. `nil` si le token
    /// est absent/expiré ou en cas d'erreur réseau (on retombe alors sur
    /// l'estimation locale).
    static func fetch() async -> ClaudeLiveUsage? {
        guard let token = keychainToken() else { return nil }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/\(claudeVersion())", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }
        return decode(data)
    }

    // MARK: - Décodage

    private struct Window: Decodable {
        let utilization: Double?
        let resets_at: String?
    }
    private struct LimitEntry: Decodable {
        let kind: String?
        let percent: Double?
        let resets_at: String?
        let scope: Scope?
        struct Scope: Decodable {
            let model: Model?
            struct Model: Decodable { let display_name: String? }
        }
    }
    private struct Payload: Decodable {
        let five_hour: Window?
        let seven_day: Window?
        let limits: [LimitEntry]?
    }

    private static func decode(_ data: Data) -> ClaudeLiveUsage? {
        guard let p = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        // Limite hebdomadaire propre au modèle (ex. « Fable »)
        let scoped = p.limits?.first {
            $0.kind == "weekly_scoped" && $0.scope?.model?.display_name != nil
        }
        return ClaudeLiveUsage(
            fiveHourPercent: p.five_hour?.utilization ?? 0,
            fiveHourResetsAt: parseDate(p.five_hour?.resets_at),
            sevenDayPercent: p.seven_day?.utilization ?? 0,
            sevenDayResetsAt: parseDate(p.seven_day?.resets_at),
            modelName: scoped?.scope?.model?.display_name,
            modelPercent: scoped?.percent,
            modelResetsAt: parseDate(scoped?.resets_at))
    }

    private static func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        return withFrac.date(from: s) ?? plain.date(from: s)
    }

    // MARK: - Token & version

    /// Lit le token OAuth depuis le Trousseau (même entrée que Claude Code).
    private static func keychainToken() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else { return nil }
        return token
    }

    /// Version de Claude Code (via le lien `~/.local/bin/claude`), pour le
    /// User-Agent. Seul le préfixe `claude-code/` est réellement requis.
    private static func claudeVersion() -> String {
        let link = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/claude").path
        if let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: link) {
            let v = (dest as NSString).lastPathComponent
            if !v.isEmpty { return v }
        }
        return "2.1.0"
    }
}
