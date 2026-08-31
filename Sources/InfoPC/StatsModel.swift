import Foundation
import SwiftUI
import AppKit
import SMCCore

/// Capteur de température affiché dans la barre de menus.
enum TempSource: String {
    case cpu, gpu
}

/// Éléments affichables dans la barre de menus (personnalisation).
enum MenuBarItem: String, CaseIterable, Identifiable {
    case cpu, gpu, ram, network, temperature
    var id: String { rawValue }
    @MainActor var label: String {
        switch self {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .ram: return "RAM"
        case .network: return t("Réseau", "Network")
        case .temperature: return t("Température", "Temperature")
        }
    }
}

struct FanState: Identifiable {
    let id: Int
    var current: Double
    var min: Double
    var max: Double
    /// Consigne lue dans le SMC. En mode auto, elle est écrite par le système :
    /// c'est elle que doit suivre le curseur pour rester juste.
    var target: Double
    /// Régime forcé (clé `Fxmd`), relu à chaque rafraîchissement.
    var manual: Bool

    /// Position à afficher sur le curseur, bornée à la plage du ventilateur.
    var sliderPosition: Double {
        Swift.min(Swift.max(target > 0 ? target : current, min), Swift.max(max, min + 1))
    }
}

/// Appelle le helper privilégié installé par scripts/install.sh.
/// La règle NOPASSWD de /etc/sudoers.d/infopc permet `sudo -n` sans mot de passe.
enum FanController {
    static let helperPath = "/usr/local/bin/infopc-fanctl"

    static var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: helperPath)
    }

    @discardableResult
    private static func run(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-n", helperPath] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    static func setSpeed(_ index: Int, rpm: Double) -> Bool {
        run(["set", "\(index)", "\(Int(rpm))"])
    }

    static func setAuto(_ index: Int) -> Bool {
        run(["auto", "\(index)"])
    }

    /// Script embarqué dans le bundle qui pose le helper et sa règle sudoers.
    /// Absent quand l'app tourne depuis `swift run` (build sans bundle).
    static var installerPath: String? {
        let path = Bundle.main.bundlePath + "/Contents/Resources/install-helper.sh"
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    /// Installe le helper en demandant les droits admin via le dialogue système
    /// (osascript). C'est le seul moment où l'app a besoin d'un mot de passe :
    /// ensuite la règle NOPASSWD, ciblée sur ce seul binaire, suffit.
    /// Renvoie `nil` si tout s'est bien passé, sinon la raison de l'échec.
    static func installHelper() -> HelperFailure? {
        guard let script = installerPath else { return .installerMissing }
        // Le chemin peut contenir des espaces ou une apostrophe : on le quote
        // pour le shell, puis pour la chaîne AppleScript.
        let shellQuoted = "'" + script.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let appleQuoted = shellQuoted.replacingOccurrences(of: "\\", with: "\\\\")
                                     .replacingOccurrences(of: "\"", with: "\\\"")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e",
            "do shell script \"\(appleQuoted)\" with administrator privileges"]
        process.standardOutput = FileHandle.nullDevice
        let errPipe = Pipe()
        process.standardError = errPipe
        do {
            try process.run()
            let err = errPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if process.terminationStatus == 0 { return nil }
            let text = String(data: err, encoding: .utf8) ?? ""
            // -128 : l'utilisateur a fermé le dialogue de mot de passe.
            if text.contains("-128") { return nil }
            return .failed
        } catch {
            return .failed
        }
    }
}

/// Pourquoi la pose du helper n'a pas abouti. Un cas plutôt qu'un texte :
/// l'installation tourne hors du thread principal, où la langue n'est pas
/// lisible ; c'est l'appelant qui met les mots dessus.
enum HelperFailure {
    case installerMissing
    case failed

    @MainActor var message: String {
        switch self {
        case .installerMissing:
            return t("Installateur introuvable — lancez scripts/install.sh.",
                     "Installer not found — run scripts/install.sh.")
        case .failed:
            return t("Installation du helper impossible.",
                     "Could not install the helper.")
        }
    }
}

@MainActor
final class StatsModel: ObservableObject {
    @Published var cpuUsage: Double?
    @Published var cpuPerCore: [Double] = []
    @Published var cpuTemp: Double?
    @Published var gpuUsage: Double?
    @Published var gpuTemp: Double?
    @Published var power: Double?          // puissance système (W, clé SMC PSTR)
    @Published var memory: SystemStats.MemoryUsage?
    @Published var disk: SystemStats.DiskUsage?
    @Published var network: NetworkSampler.Throughput?
    @Published var fans: [FanState] = []
    @Published var fanManual: [Int: Bool] = [:]   // index → mode forcé actif
    /// Message affiché sous les ventilateurs quand une commande n'a pas abouti.
    @Published var fanNotice: String?
    @Published var claude: ClaudeBlockUsage?
    /// Dénominateur de la jauge Claude locale = plus gros bloc de 5 h historique
    /// (repli si l'API d'usage réelle n'est pas joignable).
    @Published var claudeLimit: Int = 0
    /// Usage réel du compte (endpoint OAuth `/usage`) : source prioritaire.
    @Published var claudeLive: ClaudeLiveUsage?
    @Published var smcAvailable = true
    /// Jauges compactes rendues en image pour la barre de menus.
    @Published var menuBarImage: NSImage?
    /// Groupes de processus (par application) les plus gourmands.
    @Published var processGroups: [ProcGroup] = []
    /// Capteur dont la température est affichée dans la barre de menus.
    @Published var tempSource: TempSource {
        didSet {
            UserDefaults.standard.set(tempSource.rawValue, forKey: "menuBarTempSource")
            renderMenuBar()
        }
    }
    /// Éléments cochés pour la barre de menus (personnalisation).
    @Published var menuBarItems: Set<MenuBarItem> {
        didSet {
            UserDefaults.standard.set(menuBarItems.map(\.rawValue), forKey: "menuBarItems")
            renderMenuBar()
        }
    }

    /// Publié plutôt que constant : le helper peut être posé pendant que
    /// l'app tourne (bouton « Activer le contrôle »).
    @Published var helperInstalled = FanController.isInstalled
    var performanceCores: Int { cpuSampler.performanceCores }
    var efficiencyCores: Int { cpuSampler.efficiencyCores }

    private var smc: SMC?
    private var sensors: TemperatureSensors?
    private let cpuSampler = CPUSampler()
    private let netSampler = NetworkSampler()
    private var fastTimer: Timer?
    private var slowTimer: Timer?

    init() {
        let saved = UserDefaults.standard.string(forKey: "menuBarTempSource")
        tempSource = TempSource(rawValue: saved ?? "") ?? .cpu
        if let raw = UserDefaults.standard.array(forKey: "menuBarItems") as? [String] {
            menuBarItems = Set(raw.compactMap(MenuBarItem.init(rawValue:)))
        } else {
            menuBarItems = [.cpu, .gpu, .ram, .temperature]   // défaut
        }
        do {
            let smc = try SMC()
            self.smc = smc
            self.sensors = TemperatureSensors(smc: smc)
        } catch {
            smcAvailable = false
        }
        refreshFast()
        refreshProcesses()
        refreshClaude()
        refreshClaudeMax()
        refreshClaudeLive()

        // Rafraîchissement capteurs toutes les 3 s (au lieu de 2 s).
        fastTimer = Timer(timeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshFast() }
        }
        // Processus toutes les 10 s ; Claude toutes les 60 s ; max historique / 10 min.
        slowTimer = Timer(timeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.refreshProcesses()
                self.tick += 1
                if self.tick % 6 == 0 { self.refreshClaude() }
                if self.tick % 18 == 0 { self.refreshClaudeLive() }   // 180 s (intervalle sûr)
                if self.tick % 180 == 0 { self.refreshClaudeMax() }   // 30 min (scan complet)
            }
        }
        RunLoop.main.add(fastTimer!, forMode: .common)
        RunLoop.main.add(slowTimer!, forMode: .common)
    }

    private var tick = 0
    private var claudeMax = 0

    /// Critère de tri de la liste des processus.
    @Published var procSort: ProcSortKey = .cpu {
        didSet { refreshProcesses() }
    }

    /// État du speed test de la connexion.
    enum SpeedState: Equatable {
        case idle, running
        case done(down: Double, up: Double?)
        case failed
    }
    @Published var speedState: SpeedState = .idle

    func runSpeedTest() {
        guard speedState != .running else { return }
        speedState = .running
        Task {
            let result = await SpeedTest.run()
            await MainActor.run {
                if let r = result { self.speedState = .done(down: r.downloadMbps, up: r.uploadMbps) }
                else { self.speedState = .failed }
            }
        }
    }

    private func refreshProcesses() {
        processGroups = ProcessSampler.topGroups(20, sortBy: procSort)
    }

    func killProcess(_ pid: Int32) {
        _ = ProcessSampler.kill(pid)
        refreshProcesses()
    }

    /// Termine tous les processus d'un groupe (ex. toutes les fenêtres Chrome).
    func killGroup(_ group: ProcGroup) {
        for pid in group.pids { _ = ProcessSampler.kill(pid) }
        refreshProcesses()
    }

    /// Recalcule le bloc de 5 h courant (lecture fichiers, hors thread principal).
    private func refreshClaude() {
        Task.detached(priority: .utility) {
            let block = ClaudeUsageReader.currentBlock()
            await MainActor.run {
                self.claude = block
                self.recomputeClaudeLimit()
            }
        }
    }

    /// Recalcule le plus gros bloc historique = dénominateur de la jauge.
    private func refreshClaudeMax() {
        Task.detached(priority: .utility) {
            let maxTokens = ClaudeUsageReader.historicalMaxBlockTokens()
            await MainActor.run {
                self.claudeMax = maxTokens
                self.recomputeClaudeLimit()
            }
        }
    }

    private func recomputeClaudeLimit() {
        // La limite ne peut pas être plus petite que le bloc courant (jauge ≤ 100 %).
        claudeLimit = max(claudeMax, claude?.tokens ?? 0, 1)
    }

    /// Récupère l'usage réel du compte via l'endpoint OAuth `/usage`.
    private func refreshClaudeLive() {
        Task {
            let live = await ClaudeUsageAPI.fetch()
            await MainActor.run { if let live { self.claudeLive = live } }
        }
    }

    private var fastTick = 0

    private func refreshFast() {
        fastTick += 1
        let sample = cpuSampler.sample()
        cpuUsage = sample?.overall
        cpuPerCore = sample?.perCore ?? cpuPerCore
        // GPU (scan IORegistry coûteux) : 1 fois sur 2, soit ~6 s.
        if fastTick % 2 == 0 { gpuUsage = SystemStats.gpuUsage() }
        memory = SystemStats.memoryUsage()
        cpuTemp = sensors?.cpuTemp
        gpuTemp = sensors?.gpuTemp
        power = try? smc?.readNumber("PSTR")
        // Disque (change lentement) : ~1 fois sur 4, soit ~12 s.
        if fastTick % 4 == 1 { disk = SystemStats.diskUsage() }
        network = netSampler.sample() ?? network

        if let smc {
            let count = smc.fanCount()
            var states: [FanState] = []
            var manual: [Int: Bool] = [:]
            for i in 0..<count {
                if let f = smc.fanInfo(i) {
                    states.append(FanState(id: i, current: f.current,
                                           min: f.min, max: f.max,
                                           target: f.target, manual: f.manual))
                    manual[i] = f.manual
                }
            }
            fans = states
            // Le mode vient du SMC, pas d'un état supposé côté app : un
            // ventilateur laissé en forcé par une session précédente (ou par un
            // autre outil) est ainsi correctement détecté au lancement.
            if fanManual != manual { fanManual = manual }
        }

        renderMenuBar()
    }

    /// Rend la barre de menus selon les éléments cochés (personnalisation).
    private func renderMenuBar() {
        let temp = (tempSource == .cpu) ? cpuTemp : gpuTemp
        let tempStr = (menuBarItems.contains(.temperature) ? temp : nil)
            .map { "\(Int($0.rounded()))°" }

        var gauges: [MenuBarGaugesView.Gauge] = []
        if menuBarItems.contains(.cpu) {
            gauges.append(.init(label: "CPU", fraction: (cpuUsage ?? 0) / 100))
        }
        if menuBarItems.contains(.gpu) {
            gauges.append(.init(label: "GPU", fraction: (gpuUsage ?? 0) / 100))
        }
        if menuBarItems.contains(.ram), let mem = memory {
            gauges.append(.init(label: "RAM", fraction: mem.fraction))
        }

        let net = (menuBarItems.contains(.network) ? network : nil)
            .map { "↓\(MenuBarFormat.speed($0.rxBytesPerSec)) ↑\(MenuBarFormat.speed($0.txBytesPerSec))" }

        // Repli si rien n'est coché, pour ne pas afficher une barre vide.
        if gauges.isEmpty && tempStr == nil && net == nil {
            gauges.append(.init(label: "CPU", fraction: (cpuUsage ?? 0) / 100))
        }

        // On ne redessine l'image que si l'affichage a réellement changé
        // (les jauges sont arrondies à l'entier). Évite un rendu SwiftUI inutile.
        let signature = (tempStr ?? "-") + "|" + (net ?? "-") + "|"
            + gauges.map { "\($0.label)\(Int(($0.fraction * 100).rounded()))" }.joined(separator: ",")
        guard signature != lastMenuSignature else { return }
        lastMenuSignature = signature

        let view = MenuBarGaugesView(temperature: tempStr, network: net, gauges: gauges)
        let renderer = ImageRenderer(content: view)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        if let image = renderer.nsImage {
            image.isTemplate = false   // conserve le blanc
            menuBarImage = image
        }
    }
    private var lastMenuSignature = ""

    func setFanSpeed(_ index: Int, rpm: Double) {
        guard FanController.setSpeed(index, rpm: rpm) else {
            fanNotice = t("Régime non appliqué — le helper a refusé la commande.",
                          "Speed not applied — the helper refused the command.")
            return
        }
        fanNotice = nil
        resyncFans()
    }

    func setFanAuto(_ index: Int) {
        guard FanController.setAuto(index) else {
            fanNotice = t("Retour en auto refusé — vérifiez l'installation du helper.",
                          "Switch back to auto refused — check the helper installation.")
            return
        }
        fanNotice = nil
        resyncFans()
    }

    /// Pose le helper privilégié depuis le popover (dialogue de mot de passe
    /// système). Sans lui, l'app reste utilisable en lecture seule.
    /// Hors du thread principal : la saisie du mot de passe peut durer, l'UI ne
    /// doit pas se figer pendant ce temps.
    func installFanHelper() {
        fanNotice = t("Installation du helper en cours…", "Installing the helper…")
        Task { @MainActor [weak self] in
            let failure = await Task.detached { FanController.installHelper() }.value
            guard let self else { return }
            self.fanNotice = failure?.message
            self.helperInstalled = FanController.isInstalled
            if self.helperInstalled { self.resyncFans() }
        }
    }

    /// Relit l'état réel des ventilateurs juste après une commande, sans
    /// attendre le tick de 3 s. Le SMC met un instant à recalculer sa consigne
    /// après un retour en auto : on relit donc une seconde fois peu après.
    private func resyncFans() {
        refreshFast()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            self?.refreshFast()
        }
    }

    /// Texte affiché dans la barre de menus
    var menuBarText: String {
        let cpu = cpuUsage.map { String(format: "%.0f%%", $0) } ?? "–"
        let cpuT = cpuTemp.map { String(format: "%.0f°", $0) } ?? ""
        let gpu = gpuUsage.map { String(format: "%.0f%%", $0) } ?? "–"
        let gpuT = gpuTemp.map { String(format: "%.0f°", $0) } ?? ""
        return "C \(cpu) \(cpuT)  G \(gpu) \(gpuT)"
    }
}
