import SwiftUI
import AppKit

/// Version compacte rendue en image pour la barre de menus, sur une seule ligne
/// pour pouvoir utiliser la vraie police de la barre de menus macOS
/// (`NSFont.menuBarFont`) — la même que l'heure et les menus Fichier/Édition.
/// À gauche : température (capteur choisi) puis réseau ; ensuite les colonnes
/// CPU / GPU / RAM (libellé + barre blanche). Tout en blanc.
struct MenuBarGaugesView: View {
    struct Gauge {
        let label: String
        let fraction: Double
    }
    let temperature: String?
    var network: String? = nil
    let gauges: [Gauge]

    /// Police native de la barre de menus macOS.
    private var menuFont: Font {
        Font(NSFont.menuBarFont(ofSize: 0))
    }
    private var gaugeHeight: CGFloat {
        // Barre calée sur la hauteur des majuscules de la police de la barre.
        NSFont.menuBarFont(ofSize: 0).capHeight + 2
    }

    var body: some View {
        HStack(spacing: 8) {
            if let temperature {
                Text(temperature).font(menuFont).foregroundStyle(.white)
            }
            if let network {
                Text(network).font(menuFont).foregroundStyle(.white)
            }
            ForEach(gauges.indices, id: \.self) { i in
                HStack(spacing: 4) {
                    Text(gauges[i].label).font(menuFont).foregroundStyle(.white)
                    BatteryGauge(fraction: gauges[i].fraction,
                                 color: .white,
                                 height: gaugeHeight,
                                 outline: .white,
                                 animated: false)
                        .frame(width: 24)
                }
            }
        }
        .padding(.horizontal, 2)
        .fixedSize()
    }
}
