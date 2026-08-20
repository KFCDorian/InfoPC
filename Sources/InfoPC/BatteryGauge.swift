import SwiftUI

/// Paliers d'alerte, du plus calme au plus grave. Ordonnés pour qu'on puisse
/// retenir le plus alarmant de deux avis.
enum GaugeLevel: Int, Comparable {
    case calm, elevated, high, critical

    static func < (a: GaugeLevel, b: GaugeLevel) -> Bool { a.rawValue < b.rawValue }

    var color: Color {
        switch self {
        case .calm: return .accentColor
        case .elevated: return .yellow
        case .high: return .orange
        case .critical: return .red
        }
    }

    /// Palier déduit du seul remplissage (0–100).
    init(percent p: Double) {
        switch p {
        case 80...: self = .critical
        case 60..<80: self = .high
        case 30..<60: self = .elevated
        default: self = .calm
        }
    }

    /// Palier tiré du `severity` renvoyé par l'API d'usage Claude. `nil` si la
    /// valeur est absente ou inconnue : le vocabulaire du serveur n'est pas
    /// documenté (seul « normal » a été observé), donc tout ce qui n'est pas
    /// reconnu doit rester sans effet plutôt que d'être deviné.
    init?(severity: String?) {
        switch severity?.lowercased() {
        case "normal", "none", "ok": self = .calm
        case "warning", "warn": self = .high
        case "critical", "severe", "exceeded": self = .critical
        default: return nil
        }
    }
}

/// Couleur d'une jauge selon son niveau de remplissage (0–100) :
/// < 30 % bleu (accent), 30–60 % jaune, 60–80 % orange, ≥ 80 % rouge.
func gaugeColor(forPercent p: Double) -> Color {
    GaugeLevel(percent: p).color
}

/// Palier d'une limite Claude. On retient le **plus alarmant** entre l'avis du
/// serveur et nos seuils : le serveur connaît le plan réel, mais son
/// vocabulaire nous échappe en partie — une valeur mal reconnue ne doit jamais
/// faire passer une jauge pleine pour tranquille.
func gaugeLevel(forSeverity severity: String?, percent: Double) -> GaugeLevel {
    let local = GaugeLevel(percent: percent)
    guard let server = GaugeLevel(severity: severity) else { return local }
    return max(server, local)
}

/// Jauge en forme de barre : coque arrondie + remplissage proportionnel
/// (de gauche à droite). Plus « rempli » = plus haut niveau.
struct BatteryGauge: View {
    /// Niveau de remplissage entre 0 et 1
    var fraction: Double
    /// Couleur du remplissage
    var color: Color
    var height: CGFloat = 16
    /// Couleur du contour. Gris moyen par défaut pour rester lisible aussi
    /// bien sur barre de menus claire que sombre.
    var outline: Color = Color.primary.opacity(0.35)
    /// Anime le remplissage (désactivé lors du rendu en image pour la barre).
    var animated: Bool = true

    private var clamped: Double { min(1, max(0, fraction)) }

    var body: some View {
        GeometryReader { geo in
            let corner = height * 0.28
            let inset: CGFloat = 2
            ZStack(alignment: .leading) {
                // Coque
                RoundedRectangle(cornerRadius: corner)
                    .strokeBorder(outline, lineWidth: 1.2)
                // Remplissage
                RoundedRectangle(cornerRadius: max(1, corner - inset))
                    .fill(color)
                    .frame(width: max(0, (geo.size.width - inset * 2) * clamped))
                    .padding(inset)
            }
        }
        .frame(height: height)
        .animation(animated ? .easeOut(duration: 0.4) : nil, value: clamped)
    }
}
