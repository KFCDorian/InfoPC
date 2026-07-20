import SwiftUI

/// Version compacte rendue en image pour la barre de menus.
/// À gauche : une seule température (capteur choisi). Puis trois colonnes
/// CPU / GPU / RAM, chacune avec son titre au-dessus de la barre. Tout en blanc.
struct MenuBarGaugesView: View {
    struct Gauge {
        let label: String
        let fraction: Double
    }
    let temperature: String?
    let gauges: [Gauge]

    private let labelHeight: CGFloat = 8

    var body: some View {
        HStack(spacing: 9) {
            if let temperature {
                VStack(spacing: 1) {
                    // Cale invisible pour aligner la température sur les barres
                    Text(" ").font(.system(size: labelHeight, weight: .bold))
                    Text(temperature)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            ForEach(gauges.indices, id: \.self) { i in
                VStack(spacing: 1) {
                    Text(gauges[i].label)
                        .font(.system(size: labelHeight, weight: .bold))
                        .foregroundStyle(.white)
                    BatteryGauge(fraction: gauges[i].fraction,
                                 color: .white,
                                 height: 9,
                                 outline: .white,
                                 animated: false)
                        .frame(width: 22)
                }
            }
        }
        .padding(.horizontal, 2)
        .fixedSize()
    }
}
