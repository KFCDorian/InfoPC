// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "InfoPC",
    platforms: [.macOS(.v13)],
    targets: [
        // Accès SMC partagé (lecture capteurs + écriture ventilateurs)
        .target(name: "SMCCore"),
        // App de barre de menus
        .executableTarget(name: "InfoPC", dependencies: ["SMCCore"]),
        // Helper privilégié pour piloter les ventilateurs (installé dans /usr/local/bin)
        .executableTarget(name: "fanctl", dependencies: ["SMCCore"]),
    ]
)
