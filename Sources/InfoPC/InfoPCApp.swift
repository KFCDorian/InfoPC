import SwiftUI

@main
struct InfoPCApp: App {
    @StateObject private var model = StatsModel()

    init() {
        // Mode debug système : icônes des processus + cœurs.
        if CommandLine.arguments.contains("--sys-debug") {
            let procs = ProcessSampler.top(8)
            print("=== Top processus (icône) ===")
            for p in procs {
                print(String(format: "  %-24@ cpu=%.0f%% mem=%.1f%% icône=%@",
                             p.name as NSString, p.cpu, p.mem,
                             p.icon != nil ? "OUI" : "non"))
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
                if let live = await ClaudeUsageAPI.fetch() {
                    print("API /usage : 5h=\(live.fiveHourPercent)% (reset \(live.fiveHourResetsAt?.description ?? "?")), semaine=\(live.sevenDayPercent)%")
                    if let n = live.modelName, let p = live.modelPercent {
                        print("  Limite modèle \(n) : \(p)% (reset \(live.modelResetsAt?.description ?? "?"))")
                    }
                } else {
                    print("API /usage : indisponible (token absent/expiré ou réseau)")
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
