import Foundation
import SMCCore

// Helper privilégié : installé dans /usr/local/bin/infopc-fanctl,
// appelé par l'app via `sudo -n` (règle NOPASSWD dans /etc/sudoers.d/infopc).

func die(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(1)
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    die("""
    Usage:
      infopc-fanctl set <index> <rpm>   Force un ventilateur à <rpm> tr/min
      infopc-fanctl auto <index|all>    Rend le contrôle au système
      infopc-fanctl status              Affiche l'état des ventilateurs
    """)
}

guard let smc = try? SMC() else { die("Impossible d'ouvrir AppleSMC") }

switch args[1] {
case "set":
    guard geteuid() == 0 else { die("set : droits root requis") }
    guard args.count == 4, let idx = Int(args[2]), let rpm = Double(args[3]) else {
        die("Usage : infopc-fanctl set <index> <rpm>")
    }
    guard let info = smc.fanInfo(idx) else { die("Ventilateur \(idx) introuvable") }
    let clamped = Swift.min(Swift.max(rpm, info.min), info.max)
    do {
        try smc.setFanSpeed(idx, rpm: clamped)
        print("Ventilateur \(idx) → \(Int(clamped)) tr/min")
    } catch { die("Échec : \(error)") }

case "auto":
    guard geteuid() == 0 else { die("auto : droits root requis") }
    guard args.count == 3 else { die("Usage : infopc-fanctl auto <index|all>") }
    let indices: [Int] = args[2] == "all"
        ? Array(0..<smc.fanCount())
        : Int(args[2]).map { [$0] } ?? []
    guard !indices.isEmpty else { die("Index invalide") }
    // Même exigence que `set` : on n'écrit que dans un ventilateur qui existe.
    // Ce binaire tourne en root, un index inventé n'a rien à y faire.
    for i in indices where smc.fanInfo(i) == nil {
        die("Ventilateur \(i) introuvable")
    }
    for i in indices {
        do {
            try smc.setFanAuto(i)
            // La consigne FxTg est reprise par le SMC : on la relit pour montrer
            // que le système a bien repris la main.
            let target = smc.fanInfo(i).map { " (cible système \(Int($0.target)) tr/min)" } ?? ""
            print("Ventilateur \(i) → mode auto\(target)")
        } catch { die("Échec : \(error)") }
    }

case "status":
    let count = smc.fanCount()
    print("\(count) ventilateur(s)")
    for i in 0..<count {
        if let f = smc.fanInfo(i) {
            print("  #\(i) : \(Int(f.current)) tr/min (min \(Int(f.min)), max \(Int(f.max)), cible \(Int(f.target))) — \(f.manual ? "forcé" : "auto")")
        }
    }

case "keys":
    // Debug : liste les clés SMC correspondant à un préfixe
    guard args.count == 3 else { die("Usage : infopc-fanctl keys <préfixe>") }
    for name in smc.keys(withPrefixes: [args[2]]) {
        let value = (try? smc.readNumber(name)).map { String(format: "%.1f", $0) } ?? "?"
        let type = (try? smc.read(name))?.type ?? "????"
        print("\(name) [\(type)] = \(value)")
    }

default:
    die("Commande inconnue : \(args[1])")
}
