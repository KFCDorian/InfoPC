import SwiftUI

@main
struct InfoPCApp: App {
    @StateObject private var model = StatsModel()

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
