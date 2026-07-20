import SwiftUI

/// Couleur d'une jauge selon son niveau de remplissage (0–100).
func gaugeColor(forPercent p: Double) -> Color {
    switch p {
    case ..<60: return .green
    case ..<85: return .orange
    default: return .red
    }
}

/// Jauge en forme de batterie : coque arrondie + remplissage proportionnel
/// (de gauche à droite) + petite borne à droite. Plus « rempli » = plus haut niveau.
struct BatteryGauge: View {
    /// Niveau de remplissage entre 0 et 1
    var fraction: Double
    /// Couleur du remplissage (typiquement vert / orange / rouge selon le niveau)
    var color: Color
    var height: CGFloat = 16
    /// Couleur du contour et de la borne. Gris moyen par défaut pour rester
    /// lisible aussi bien sur barre de menus claire que sombre.
    var outline: Color = Color.primary.opacity(0.35)
    /// Anime le remplissage (désactivé lors du rendu en image pour la barre).
    var animated: Bool = true

    private var clamped: Double { min(1, max(0, fraction)) }

    var body: some View {
        GeometryReader { geo in
            let nub: CGFloat = 2.5
            let shellWidth = geo.size.width - nub - 1
            let corner = height * 0.28
            let inset: CGFloat = 2

            HStack(spacing: 1) {
                ZStack(alignment: .leading) {
                    // Coque
                    RoundedRectangle(cornerRadius: corner)
                        .strokeBorder(outline, lineWidth: 1.2)
                    // Remplissage
                    RoundedRectangle(cornerRadius: max(1, corner - inset))
                        .fill(color)
                        .frame(width: max(0, (shellWidth - inset * 2) * clamped))
                        .padding(inset)
                }
                .frame(width: shellWidth)

                // Borne
                RoundedRectangle(cornerRadius: 1)
                    .fill(outline)
                    .frame(width: nub, height: height * 0.4)
            }
        }
        .frame(height: height)
        .animation(animated ? .easeOut(duration: 0.4) : nil, value: clamped)
    }
}
