import SwiftUI

@main
struct InfoPCApp: App {
    @StateObject private var model = StatsModel()

    init() {
        // Mode debug système : icônes des processus + cœurs.
        if CommandLine.arguments.contains("--sys-debug") {
            let groups = ProcessSampler.topGroups(12)
            print("=== Top groupes (icône) ===")
            for g in groups {
                print(String(format: "  %-24@ ×%d cpu=%.0f%% mem=%.1f%% icône=%@",
                             g.name as NSString, g.count, g.cpu, g.mem,
                             g.icon != nil ? "OUI" : "non"))
            }
            let s = CPUSampler()
            _ = s.sample()
            Thread.sleep(forTimeInterval: 0.5)
            if let sample = s.sample() {
                print("=== Cœurs (\(s.performanceCores) P + \(s.efficiencyCores) E) ===")
                print("  usage global : \(Int(sample.overall)) %")
                print("  par cœur : \(sample.perCore.map { Int($0) })")
            }
            exit(0)
        }

        // Mode debug : « InfoPC --claude-debug » imprime l'usage Claude et quitte.
        if CommandLine.arguments.contains("--claude-debug") {
            if let b = ClaudeUsageReader.currentBlock() {
                let end = b.blockEnd.formatted(date: .omitted, time: .standard)
                print("Bloc courant : début=\(b.blockStart), fin=\(end), actif=\(b.isActive)")
                print("Tokens bloc courant : \(b.tokens)")
            } else {
                print("Aucun bloc courant")
            }
            print("Max historique : \(ClaudeUsageReader.historicalMaxBlockTokens())")

            // Usage réel via l'endpoint OAuth (test du chemin Trousseau + réseau)
            let sem = DispatchSemaphore(value: 0)
            Task.detached {
                switch await ClaudeUsageAPI.fetchDetailed() {
                case .success(let live):
                    func line(_ title: String, _ l: ClaudeLimitState) {
                        print("  \(title) : \(l.percent)% [\(l.severity ?? "gravité absente")]"
                              + " reset \(l.resetsAt?.description ?? "—")")
                    }
                    print("API /usage :")
                    line("5 h    ", live.fiveHour)
                    line("7 jours", live.sevenDay)
                    if let n = live.modelName, let l = live.model { line("modèle \(n)", l) }
                case .noCredentials:
                    print("API /usage : aucun jeton de compte dans le Trousseau.")
                    print("  Les entrées « Claude Code-credentials* » présentes ne portent que")
                    print("  des jetons MCP. Connectez-vous via le CLI (`claude` puis /login)")
                    print("  pour qu'un jeton lisible y soit écrit.")
                case .expired(let date):
                    print("API /usage : jeton expiré le \(date) — reconnectez-vous.")
                case .http(let code):
                    print("API /usage : refusée par le serveur (HTTP \(code)).")
                case .unreachable:
                    print("API /usage : injoignable (réseau).")
                case .undecodable:
                    print("API /usage : réponse illisible (format changé ?).")
                }
                sem.signal()
            }
            sem.wait()
            exit(0)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            if let image = model.menuBarImage {
                Image(nsImage: image)
            } else {
                Text(model.menuBarText).monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)
    }
}
