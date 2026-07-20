import SwiftUI

/// Version compacte des jauges, rendue en image pour être affichée en
/// permanence dans la barre de menus (sans ouvrir le popover).
/// Chaque colonne : titre (CPU/GPU/RAM) au-dessus, barre blanche en dessous,
/// et éventuellement la température à droite de la barre.
struct MenuBarGaugesView: View {
    struct Item {
        let label: String
        let fraction: Double
        let trailing: String?   // température, ex. "55°"
    }
    let items: [Item]

    // Gris moyen : lisible sur barre de menus claire comme sombre.
    private let ink = Color(white: 0.6)

    var body: some View {
        HStack(spacing: 10) {
            ForEach(items.indices, id: \.self) { i in
                VStack(spacing: 1) {
                    Text(items[i].label)
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(ink)
                    HStack(spacing: 3) {
                        BatteryGauge(fraction: items[i].fraction,
                                     color: .white,
                                     height: 9,
                                     outline: ink,
                                     animated: false)
                            .frame(width: 22)
                        if let t = items[i].trailing {
                            Text(t)
                                .font(.system(size: 8.5, weight: .medium))
                                .foregroundStyle(ink)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 2)
        .fixedSize()
    }
}
