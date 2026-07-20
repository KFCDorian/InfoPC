import SwiftUI

@main
struct InfoPCApp: App {
    @StateObject private var model = StatsModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            Text(model.menuBarText)
                .monospacedDigit()
        }
        .menuBarExtraStyle(.window)
    }
}
