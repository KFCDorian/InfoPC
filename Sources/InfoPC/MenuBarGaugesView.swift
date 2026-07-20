import SwiftUI

/// Version compacte des jauges, rendue en image pour être affichée en
/// permanence dans la barre de menus (sans ouvrir le popover).
struct MenuBarGaugesView: View {
    struct Item {
        let label: String
        let fraction: Double
    }
    let items: [Item]

    // Gris moyen : lisible sur barre de menus claire comme sombre.
    private let ink = Color(white: 0.55)

    var body: some View {
        HStack(spacing: 7) {
            ForEach(items.indices, id: \.self) { i in
                HStack(spacing: 2) {
                    Text(items[i].label)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(ink)
                    BatteryGauge(fraction: items[i].fraction,
                                 color: gaugeColor(forPercent: items[i].fraction * 100),
                                 height: 11,
                                 outline: ink,
                                 animated: false)
                        .frame(width: 22)
                }
            }
        }
        .padding(.horizontal, 2)
        .frame(height: 15)
        .fixedSize()
    }
}
