import Foundation
import Security

/// Usage réel du compte Claude, tel que renvoyé par l'endpoint OAuth
/// `https://api.anthropic.com/api/oauth/usage` (la source qui alimente la
/// commande `/usage` de Claude Code). `utilization` est le pourcentage
/// **réel** consommé sur la limite du plan de l'utilisateur.
/// État d'une limite : où on en est, quand elle se réarme, et l'avis du
/// serveur sur la gravité.
struct ClaudeLimitState {
    let percent: Double
    /// `nil` tant que la limite n'est pas entamée : l'API ne date le
    /// réarmement que des limites actives.
    let resetsAt: Date?
    /// `severity` brut renvoyé par le serveur (« normal » est la seule valeur
    /// observée à ce jour). Conservé tel quel : c'est l'interprétation, pas la
    /// lecture, qui doit tolérer une valeur inconnue.
    let severity: String?
}

struct ClaudeLiveUsage {
    let fiveHour: ClaudeLimitState
    let sevenDay: ClaudeLimitState
    /// Limite hebdomadaire spécifique au modèle en cours (ex. « Fable »).
    let modelName: String?
    let model: ClaudeLimitState?
}

enum ClaudeUsageAPI {
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    /// Préfixe des entrées du Trousseau écrites par Claude Code. Le nom exact
    /// dépend de l'installation : historiquement « Claude Code-credentials »,
    /// aujourd'hui suffixé par un identifiant (« …-8b9b410d »). D'où une
    /// recherche par préfixe plutôt que sur un nom figé.
    private static let servicePrefix = "Claude Code-credentials"

    /// Issue détaillée d'une interrogation, pour que `--claude-debug` dise
    /// *pourquoi* l'usage réel n'est pas disponible.
    enum Outcome {
        case success(ClaudeLiveUsage)
        /// Aucune entrée du Trousseau ne porte de jeton de compte. C'est le cas
        /// quand Claude Code est lancé par l'app Claude pour macOS, qui garde
        /// ses identifiants chiffrés pour elle : seule une connexion via le CLI
        /// `claude` écrit un jeton lisible ici.
        case noCredentials
        case expired(Date)
        case http(Int)
        case unreachable
        case undecodable
    }

    /// Interroge l'endpoint avec le token OAuth du Trousseau. `nil` si le token
    /// est absent/expiré ou en cas d'erreur réseau (on retombe alors sur
    /// l'estimation locale).
    static func fetch() async -> ClaudeLiveUsage? {
        if case .success(let usage) = await fetchDetailed() { return usage }
        return nil
    }

    /// Même chose, en conservant la cause de l'échec.
    static func fetchDetailed() async -> Outcome {
        guard let creds = credentials() else { return .noCredentials }
        if let expiry = creds.expiresAt, expiry <= Date() { return .expired(expiry) }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(creds.token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/\(claudeVersion())", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return .unreachable }
        guard http.statusCode == 200 else { return .http(http.statusCode) }
        guard let usage = decode(data) else { return .undecodable }
        return .success(usage)
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
        /// Avis du serveur sur la gravité — il connaît le plan, nos seuils non.
        let severity: String?
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
        let limits = p.limits ?? []
        // Seul `limits` porte la gravité ; les blocs `five_hour`/`seven_day`
        // donnent les mêmes chiffres et servent de repli si le tableau manque.
        let session = limits.first { $0.kind == "session" }
        let weekly = limits.first { $0.kind == "weekly_all" }
        // Limite hebdomadaire propre au modèle (ex. « Fable »)
        let scoped = limits.first {
            $0.kind == "weekly_scoped" && $0.scope?.model?.display_name != nil
        }
        return ClaudeLiveUsage(
            fiveHour: ClaudeLimitState(
                percent: session?.percent ?? p.five_hour?.utilization ?? 0,
                resetsAt: parseDate(session?.resets_at ?? p.five_hour?.resets_at),
                severity: session?.severity),
            sevenDay: ClaudeLimitState(
                percent: weekly?.percent ?? p.seven_day?.utilization ?? 0,
                resetsAt: parseDate(weekly?.resets_at ?? p.seven_day?.resets_at),
                severity: weekly?.severity),
            modelName: scoped?.scope?.model?.display_name,
            model: scoped.map {
                ClaudeLimitState(percent: $0.percent ?? 0,
                                 resetsAt: parseDate($0.resets_at),
                                 severity: $0.severity)
            })
    }

    private static func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        return withFrac.date(from: s) ?? plain.date(from: s)
    }

    // MARK: - Token & version

    private struct Credentials {
        let token: String
        let expiresAt: Date?
        var isUsable: Bool { expiresAt.map { $0 > Date() } ?? true }
    }

    /// Cherche l'entrée du Trousseau qui porte réellement un jeton de compte.
    /// Plusieurs entrées coexistent sous le même préfixe : celles des serveurs
    /// MCP ne contiennent qu'un objet `mcpOAuth` et sont ignorées ici.
    private static func credentials() -> Credentials? {
        var expiredFallback: Credentials?
        for service in credentialServices() {
            guard let found = readCredentials(service: service) else { continue }
            if found.isUsable { return found }
            // On garde le jeton périmé le plus récent : mieux vaut un
            // diagnostic « expiré » qu'un « absent » trompeur.
            if (found.expiresAt ?? .distantPast) > (expiredFallback?.expiresAt ?? .distantPast) {
                expiredFallback = found
            }
        }
        return expiredFallback
    }

    /// Noms de service du Trousseau commençant par le préfixe de Claude Code.
    /// On ne demande que les attributs : énumérer ne déclenche aucune demande
    /// d'autorisation, contrairement à la lecture des données.
    private static func credentialServices() -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return [] }
        let services = Set(items.compactMap { $0[kSecAttrService as String] as? String }
            .filter { $0.hasPrefix(servicePrefix) })
        // Le nom historique d'abord, puis un ordre stable : sans cela l'entrée
        // essayée en premier changerait d'un lancement à l'autre.
        return services.sorted { ($0 == servicePrefix ? 0 : 1, $0) < ($1 == servicePrefix ? 0 : 1, $1) }
    }

    /// Lit et décode une entrée. On passe par `/usr/bin/security` plutôt que par
    /// `SecItemCopyMatching` : c'est le chemin d'accès déjà éprouvé côté
    /// Trousseau pour ces entrées.
    private static func readCredentials(service: String) -> Credentials? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-w"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }
        // `expiresAt` est un horodatage en millisecondes.
        let expiry = (oauth["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        return Credentials(token: token, expiresAt: expiry)
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
