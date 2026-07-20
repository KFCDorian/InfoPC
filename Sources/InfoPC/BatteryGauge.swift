import SwiftUI

/// Jauge en forme de batterie : coque arrondie + remplissage proportionnel
/// (de gauche à droite) + petite borne à droite. Plus « rempli » = plus haut niveau.
struct BatteryGauge: View {
    /// Niveau de remplissage entre 0 et 1
    var fraction: Double
    /// Couleur du remplissage (typiquement vert / orange / rouge selon le niveau)
    var color: Color
    var height: CGFloat = 16

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
                        .strokeBorder(Color.primary.opacity(0.35), lineWidth: 1.2)
                    // Remplissage
                    RoundedRectangle(cornerRadius: max(1, corner - inset))
                        .fill(color)
                        .frame(width: max(0, (shellWidth - inset * 2) * clamped))
                        .padding(inset)
                }
                .frame(width: shellWidth)

                // Borne
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.primary.opacity(0.35))
                    .frame(width: nub, height: height * 0.4)
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.4), value: clamped)
    }
}
