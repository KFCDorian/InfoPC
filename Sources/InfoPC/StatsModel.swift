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
    var label: String {
        switch self {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .ram: return "RAM"
        case .network: return "Réseau"
        case .temperature: return "Température"
        }
    }
}

struct FanState: Identifiable {
    let id: Int
    var current: Double
    var min: Double
    var max: Double
    var target: Double
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
    @Published var claude: ClaudeBlockUsage?
    /// Dénominateur de la jauge Claude locale = plus gros bloc de 5 h historique
    /// (repli si l'API d'usage réelle n'est pas joignable).
    @Published var claudeLimit: Int = 0
    /// Usage réel du compte (endpoint OAuth `/usage`) : source prioritaire.
    @Published var claudeLive: ClaudeLiveUsage?
    @Published var smcAvailable = true
    /// Jauges compactes rendues en image pour la barre de menus.
    @Published var menuBarImage: NSImage?
    /// Processus les plus gourmands (rafraîchis moins souvent).
    @Published var processes: [ProcInfo] = []
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

    let helperInstalled = FanController.isInstalled
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

        fastTimer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
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
                if self.tick % 60 == 0 { self.refreshClaudeMax() }
            }
        }
        RunLoop.main.add(fastTimer!, forMode: .common)
        RunLoop.main.add(slowTimer!, forMode: .common)
    }

    private var tick = 0
    private var claudeMax = 0

    private func refreshProcesses() {
        processes = ProcessSampler.top(8)
    }

    func killProcess(_ pid: Int32) {
        _ = ProcessSampler.kill(pid)
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

    private func refreshFast() {
        let sample = cpuSampler.sample()
        cpuUsage = sample?.overall
        cpuPerCore = sample?.perCore ?? cpuPerCore
        gpuUsage = SystemStats.gpuUsage()
        memory = SystemStats.memoryUsage()
        cpuTemp = sensors?.cpuTemp
        gpuTemp = sensors?.gpuTemp
        power = try? smc?.readNumber("PSTR")
        disk = SystemStats.diskUsage()
        network = netSampler.sample() ?? network

        if let smc {
            let count = smc.fanCount()
            var states: [FanState] = []
            for i in 0..<count {
                if let f = smc.fanInfo(i) {
                    states.append(FanState(id: i, current: f.current,
                                           min: f.min, max: f.max, target: f.target))
                }
            }
            fans = states
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

        let view = MenuBarGaugesView(temperature: tempStr, network: net, gauges: gauges)
        let renderer = ImageRenderer(content: view)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        if let image = renderer.nsImage {
            image.isTemplate = false   // conserve le blanc
            menuBarImage = image
        }
    }

    func setFanSpeed(_ index: Int, rpm: Double) {
        if FanController.setSpeed(index, rpm: rpm) {
            fanManual[index] = true
        }
    }

    func setFanAuto(_ index: Int) {
        if FanController.setAuto(index) {
            fanManual[index] = false
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
