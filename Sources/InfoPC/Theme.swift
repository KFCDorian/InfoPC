import SwiftUI

/// Jetons visuels du popover : rayons, marges et couleurs neutres.
/// Tout passe par ici pour que l'ensemble reste cohérent quand une section
/// évolue — le contraste vient des fonds, pas des traits.
enum Theme {
    /// Rayon d'une carte.
    static let radius: CGFloat = 10
    /// Rayon des éléments internes (pastilles carrées, lignes de liste).
    static let innerRadius: CGFloat = 6
    /// Marge intérieure d'une carte.
    static let cardPadding: CGFloat = 11
    /// Écart entre deux cartes.
    static let gap: CGFloat = 9

    /// Contour, volontairement discret.
    static let border = Color.primary.opacity(0.09)
    /// Fond d'une carte, à peine détaché du matériau du popover.
    static let card = Color.primary.opacity(0.035)
    /// Fond d'un élément secondaire : piste de jauge, pastille neutre.
    static let muted = Color.primary.opacity(0.09)
}

/// Section du popover : un en-tête discret (icône + titre, complément à droite)
/// posé sur une carte.
///
/// `trailing` est déclaré avant `content` pour que la forme courante
/// `SectionCard("Titre", icon: "x") { … }` lie bien sa closure au contenu.
struct SectionCard<Trailing: View, Content: View>: View {
    private let title: String
    private let icon: String
    private let trailing: Trailing
    private let content: Content

    init(_ title: String, icon: String,
         @ViewBuilder trailing: () -> Trailing = { EmptyView() },
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                trailing
            }
            .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.cardPadding)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.border))
    }
}

/// Pastille compacte pour une valeur d'appoint (température, mode, puissance).
/// `tint` à `nil` donne la variante neutre.
struct Badge: View {
    let text: String
    var tint: Color?

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(tint ?? Color.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint?.opacity(0.15) ?? Theme.muted, in: Capsule())
    }
}

/// Barre de progression pleine : piste neutre + remplissage arrondi.
/// (La barre de menus garde `BatteryGauge`, dont le contour reste nécessaire
/// pour rester lisible sur fond clair comme sombre.)
struct ProgressBar: View {
    var fraction: Double
    var color: Color
    var height: CGFloat = 6

    private var clamped: Double { min(1, max(0, fraction)) }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.muted)
                Capsule().fill(color)
                    .frame(width: max(0, geo.size.width * clamped))
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.35), value: clamped)
    }
}

/// Barre verticale d'un cœur logique : se remplit par le bas, façon égaliseur.
struct CoreBar: View {
    var fraction: Double
    var width: CGFloat = 6
    var height: CGFloat = 20

    private var clamped: Double { min(1, max(0, fraction)) }

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 2).fill(Theme.muted)
            RoundedRectangle(cornerRadius: 2)
                .fill(gaugeColor(forPercent: clamped * 100))
                // Un fond de barre toujours visible : un cœur au repos reste
                // un cœur présent, pas une case vide.
                .frame(height: max(2, height * clamped))
        }
        .frame(width: width, height: height)
        .animation(.easeOut(duration: 0.35), value: clamped)
    }
}
