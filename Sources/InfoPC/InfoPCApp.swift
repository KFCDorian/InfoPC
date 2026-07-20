import SwiftUI

@main
struct InfoPCApp: App {
    @StateObject private var model = StatsModel()

    init() {
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
