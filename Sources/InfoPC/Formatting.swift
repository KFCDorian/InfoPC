import Foundation

/// Formatage compact pour la barre de menus.
enum MenuBarFormat {
    /// Débit en Mbps (1 décimale), à partir d'octets/s.
    static func speed(_ bytesPerSec: Double) -> String {
        let mbps = bytesPerSec * 8 / 1_000_000
        return String(format: "%.1f", mbps)
    }
}

/// Formatage lisible pour le popover.
enum Format {
    /// Débit en Mbps avec unité, ex. « 12.3 Mbps ».
    static func mbps(_ bytesPerSec: Double) -> String {
        String(format: "%.1f Mbps", bytesPerSec * 8 / 1_000_000)
    }

    /// Taille en Go (base 1024), ex. « 12.3 ».
    static func gib(_ bytes: Int64) -> String {
        String(format: "%.1f", Double(bytes) / 1_073_741_824)
    }

    static func gib(_ bytes: UInt64) -> String { gib(Int64(bytes)) }
}
