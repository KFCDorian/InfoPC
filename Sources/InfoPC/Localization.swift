import Foundation
import SwiftUI

/// Langue de l'interface.
enum AppLanguage: String, CaseIterable, Identifiable {
    case fr, en
    var id: String { rawValue }
    /// Chaque langue s'annonce dans sa propre langue : c'est ce que cherche
    /// quelqu'un qui ne comprend pas celle affichée à l'écran.
    var label: String { self == .fr ? "Français" : "English" }
}

/// Réglage de langue, persisté et observable pour que le popover se redessine
/// dès la bascule (le menu engrenage reste ouvert pendant le changement).
@MainActor
final class Localization: ObservableObject {
    static let shared = Localization()

    private static let key = "language"

    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Self.key) }
    }

    private init() {
        if let saved = UserDefaults.standard.string(forKey: Self.key),
           let choice = AppLanguage(rawValue: saved) {
            language = choice
        } else {
            // Premier lancement : on suit le système, l'anglais servant de repli
            // pour tout le reste du monde.
            let preferred = Locale.preferredLanguages.first ?? "en"
            language = preferred.hasPrefix("fr") ? .fr : .en
        }
    }
}

/// Une chaîne d'interface, dans les deux langues.
///
/// Les textes restent là où ils s'affichent plutôt que dans un catalogue de
/// clés : à cette échelle, une clé à retrouver ailleurs coûte plus qu'elle ne
/// rapporte, et on voit tout de suite si une traduction manque.
@MainActor
func t(_ fr: String, _ en: String) -> String {
    Localization.shared.language == .fr ? fr : en
}
