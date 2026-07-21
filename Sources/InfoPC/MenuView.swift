import SwiftUI

struct MenuView: View {
    @ObservedObject var model: StatsModel
    @State private var processesExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerBar
            Divider()
            processorSection
            Divider()
            memorySection
            diskSection
            networkSection
            Divider()
            processesSection
            Divider()
            fansSection
            Divider()
            claudeSection
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 380)
    }

    // MARK: - En-tête + réglages

    private var headerBar: some View {
        HStack {
            Image(systemName: "gauge.with.dots.needle.67percent")
            Text("InfoPC").bold()
            Spacer()
            settingsMenu
        }
    }

    /// Menu engrenage regroupant les réglages d'interface (barre de menus).
    private var settingsMenu: some View {
        Menu {
            Section("Afficher dans la barre") {
                ForEach(MenuBarItem.allCases) { item in
                    Toggle(item.label, isOn: Binding(
                        get: { model.menuBarItems.contains(item) },
                        set: { on in
                            if on { model.menuBarItems.insert(item) }
                            else { model.menuBarItems.remove(item) }
                        }))
                }
            }
            Section("Température de la barre") {
                Picker("Capteur", selection: Binding(
                    get: { model.tempSource },
                    set: { model.tempSource = $0 })) {
                    Text("CPU").tag(TempSource.cpu)
                    Text("GPU").tag(TempSource.gpu)
                }
            }
        } label: {
            Image(systemName: "gearshape")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: - CPU / GPU

    private var processorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            statRow(icon: "cpu", label: "CPU",
                    usage: model.cpuUsage, temp: model.cpuTemp)
            perCoreGrid
            statRow(icon: "rectangle.3.group", label: "GPU",
                    usage: model.gpuUsage, temp: model.gpuTemp)
            if let w = model.power {
                HStack {
                    Image(systemName: "bolt.fill").frame(width: 18).foregroundStyle(.yellow)
                    Text("Puissance").bold()
                    Spacer()
                    Text(String(format: "%.1f W", w)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Grille d'usage par cœur logique (P puis E selon sysctl).
    private var perCoreGrid: some View {
        let cores = model.cpuPerCore
        let p = model.performanceCores
        return VStack(alignment: .leading, spacing: 3) {
            if !cores.isEmpty {
                HStack(spacing: 3) {
                    Text("Cœurs").font(.caption2).foregroundStyle(.secondary)
                        .frame(width: 58, alignment: .leading)
                    ForEach(cores.indices, id: \.self) { i in
                        BatteryGauge(fraction: cores[i] / 100,
                                     color: gaugeColor(forPercent: cores[i]), height: 12)
                            .frame(width: 16)
                            .help("Cœur \(i + 1) : \(Int(cores[i])) %")
                    }
                }
                Text("\(p) performance · \(model.efficiencyCores) efficience")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private func statRow(icon: String, label: String, usage: Double?, temp: Double?) -> some View {
        HStack {
            Image(systemName: icon).frame(width: 18)
            Text(label).bold().frame(width: 40, alignment: .leading)
            BatteryGauge(fraction: (usage ?? 0) / 100, color: gaugeColor(forPercent: usage ?? 0))
            Text(usage.map { String(format: "%.0f %%", $0) } ?? "–")
                .monospacedDigit().frame(width: 46, alignment: .trailing)
            Text(temp.map { String(format: "%.0f °C", $0) } ?? "–")
                .monospacedDigit()
                .foregroundStyle(color(forTemp: temp))
                .frame(width: 46, alignment: .trailing)
        }
    }

    // MARK: - RAM

    private var memorySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "memorychip").frame(width: 18)
                Text("Mémoire").bold()
                Spacer()
                if let mem = model.memory {
                    Text("\(gb(mem.usedBytes)) / \(gb(mem.totalBytes)) Go")
                        .monospacedDigit().foregroundStyle(.secondary)
                }
            }
            if let mem = model.memory {
                BatteryGauge(fraction: mem.fraction, color: gaugeColor(forPercent: mem.fraction * 100))
            }
        }
    }

    // MARK: - Disque

    private var diskSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "internaldrive").frame(width: 18)
                Text("Disque").bold()
                Spacer()
                if let d = model.disk {
                    Text("\(Format.gib(d.usedBytes)) / \(Format.gib(d.totalBytes)) Go")
                        .monospacedDigit().foregroundStyle(.secondary)
                }
            }
            if let d = model.disk {
                BatteryGauge(fraction: d.fraction, color: gaugeColor(forPercent: d.fraction * 100))
            }
        }
    }

    // MARK: - Réseau

    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "network").frame(width: 18)
                Text("Réseau").bold()
                Spacer()
                if let n = model.network {
                    Label(Format.mbps(n.rxBytesPerSec), systemImage: "arrow.down")
                        .monospacedDigit().foregroundStyle(.secondary)
                    Label(Format.mbps(n.txBytesPerSec), systemImage: "arrow.up")
                        .monospacedDigit().foregroundStyle(.secondary)
                } else {
                    Text("–").foregroundStyle(.secondary)
                }
            }
            .font(.callout)

            // Speed test (débit maximal de la connexion)
            HStack(spacing: 8) {
                Button {
                    model.runSpeedTest()
                } label: {
                    Label("Speed test", systemImage: "gauge.with.dots.needle.67percent")
                }
                .controlSize(.small)
                .disabled(model.speedState == .running)

                switch model.speedState {
                case .idle:
                    EmptyView()
                case .running:
                    ProgressView().controlSize(.small)
                    Text("Test en cours…").font(.caption).foregroundStyle(.secondary)
                case .done(let down, let up):
                    Text("↓ \(String(format: "%.0f", down)) Mbps")
                        .font(.caption).monospacedDigit()
                    if let up {
                        Text("↑ \(String(format: "%.0f", up)) Mbps")
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                case .failed:
                    Text("Échec du test").font(.caption).foregroundStyle(.red)
                }
                Spacer()
            }
        }
    }

    // MARK: - Processus

    private var processesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "list.bullet").frame(width: 18)
                Text("Processus").bold()
                Spacer()
                // Bouton replier / déplier
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { processesExpanded.toggle() }
                } label: {
                    Label(processesExpanded ? "Voir moins" : "Voir plus",
                          systemImage: processesExpanded ? "chevron.up" : "chevron.down")
                }
                .controlSize(.small)
            }

            if processesExpanded {
                HStack {
                    Text("Trier :").font(.caption).foregroundStyle(.secondary)
                    Picker("Trier", selection: $model.procSort) {
                        ForEach(ProcSortKey.allCases) { key in
                            Text(key.label).tag(key)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 160)
                    Spacer()
                }
                // En-têtes de colonnes (le petit tableau : CPU / GPU / Mém au-dessus)
                HStack(spacing: 6) {
                    Text("").frame(width: 20)
                    Text("Nom").font(.caption2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("CPU").font(.caption2).foregroundStyle(.secondary).frame(width: ProcCols.cpu)
                    Text("GPU").font(.caption2).foregroundStyle(.secondary).frame(width: ProcCols.gpu)
                        .help("L'usage GPU par processus n'est pas exposé par macOS")
                    Text("Mém").font(.caption2).foregroundStyle(.secondary).frame(width: ProcCols.mem)
                    Text("").frame(width: ProcCols.kill)
                }
                if model.processGroups.isEmpty {
                    Text("Chargement…").font(.caption).foregroundStyle(.secondary)
                } else {
                    // Liste défilable, groupée par application
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(model.processGroups) { group in
                                ProcGroupRow(model: model, group: group)
                            }
                        }
                    }
                    .frame(height: 240)
                }
            } else {
                Text("\(model.processGroups.count) applications — triées par \(model.procSort.label)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Ventilateurs

    private var fansSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "fan").frame(width: 18)
                Text("Ventilateurs").bold()
                Spacer()
                Text(model.fans.isEmpty ? "aucun détecté"
                     : "\(model.fans.filter { $0.current > 10 }.count)/\(model.fans.count) actif(s)")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.fans) { fan in
                FanRow(model: model, fan: fan)
            }
            if !model.fans.isEmpty && !model.helperInstalled {
                Text("Contrôle désactivé — lancez scripts/install.sh pour installer le helper.")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Claude

    private var claudeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "sparkles").frame(width: 18)
                Text("Limites Claude").bold()
                Spacer()
            }
            if let live = model.claudeLive {
                // Usage réel du compte (endpoint OAuth /usage)
                limitBar(title: "Session (5 h)",
                         percent: live.fiveHourPercent,
                         resetsAt: live.fiveHourResetsAt,
                         showDate: false)
                limitBar(title: "Semaine (7 j)",
                         percent: live.sevenDayPercent,
                         resetsAt: live.sevenDayResetsAt,
                         showDate: true)
                if let name = live.modelName, let pct = live.modelPercent {
                    limitBar(title: "\(name) (semaine)",
                             percent: pct,
                             resetsAt: live.modelResetsAt,
                             showDate: true)
                }
            } else if let c = model.claude, c.isActive {
                // Repli : estimation locale rapportée au plus gros bloc historique
                let fraction = min(1.0, Double(c.tokens) / Double(model.claudeLimit))
                BatteryGauge(fraction: fraction, color: gaugeColor(forPercent: fraction * 100))
                HStack {
                    Text("≈ \(ClaudeUsageReader.formatTokens(c.tokens)) tokens (estimation locale)")
                    Spacer()
                    Text(String(format: "%.0f %%", fraction * 100)).monospacedDigit()
                }
                .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Usage indisponible")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// Une barre de limite réelle : titre, jauge remplie au pourcentage, % et reset.
    private func limitBar(title: String, percent: Double, resetsAt: Date?, showDate: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                if let r = resetsAt {
                    let reset = showDate
                        ? r.formatted(date: .abbreviated, time: .shortened)
                        : r.formatted(date: .omitted, time: .shortened)
                    Text("réinit. \(reset)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Text(String(format: "%.0f %%", percent))
                    .font(.caption).monospacedDigit().bold()
            }
            BatteryGauge(fraction: percent / 100, color: gaugeColor(forPercent: percent))
        }
    }

    // MARK: - Pied de page

    private var footer: some View {
        HStack {
            if !model.smcAvailable {
                Text("SMC indisponible").font(.caption).foregroundStyle(.red)
            }
            Spacer()
            Button("Quitter") { NSApplication.shared.terminate(nil) }
        }
    }

    // MARK: - Aides

    private func gb(_ bytes: UInt64) -> String {
        String(format: "%.1f", Double(bytes) / 1_073_741_824)
    }

    private func color(forTemp t: Double?) -> Color {
        guard let t else { return .secondary }
        switch t {
        case ..<70: return .primary
        case ..<90: return .orange
        default: return .red
        }
    }
}

/// Largeurs des colonnes du tableau des processus (partagées en-tête / lignes).
enum ProcCols {
    static let cpu: CGFloat = 42
    static let gpu: CGFloat = 42
    static let mem: CGFloat = 46
    static let kill: CGFloat = 44
}

/// Ligne d'un groupe d'application : icône, nom (+ nombre de processus),
/// CPU/mém agrégés, KILL (ferme tout le groupe) et flèche pour dérouler les
/// processus individuels.
struct ProcGroupRow: View {
    @ObservedObject var model: StatsModel
    let group: ProcGroup
    @State private var expanded = false

    private var expandable: Bool { group.count > 1 }

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 6) {
                // Flèche de déroulement (si plusieurs processus)
                Button {
                    withAnimation(.easeInOut(duration: 0.12)) { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 12)
                .opacity(expandable ? 1 : 0)
                .disabled(!expandable)

                if let icon = group.icon {
                    Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                } else {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(.secondary).frame(width: 18, height: 18)
                }
                HStack(spacing: 4) {
                    Text(group.name).lineLimit(1).truncationMode(.tail)
                    if expandable {
                        Text("×\(group.count)").font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(String(format: "%.0f%%", group.cpu))
                    .monospacedDigit().frame(width: ProcCols.cpu)
                Text("—").foregroundStyle(.tertiary).frame(width: ProcCols.gpu)
                    .help("L'usage GPU par processus n'est pas exposé par macOS")
                Text(String(format: "%.1f%%", group.mem))
                    .monospacedDigit().frame(width: ProcCols.mem)

                Button("KILL") { model.killGroup(group) }
                    .buttonStyle(.borderedProminent).tint(.red)
                    .controlSize(.small).frame(width: ProcCols.kill)
            }
            .font(.system(size: 12))

            // Processus individuels du groupe
            if expanded {
                ForEach(group.members) { member in
                    HStack(spacing: 6) {
                        Spacer().frame(width: 30)
                        Text(member.name).lineLimit(1).truncationMode(.tail)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(String(format: "%.0f%%", member.cpu))
                            .monospacedDigit().frame(width: ProcCols.cpu)
                        Text("—").foregroundStyle(.tertiary).frame(width: ProcCols.gpu)
                    .help("L'usage GPU par processus n'est pas exposé par macOS")
                        Text(String(format: "%.1f%%", member.mem))
                            .monospacedDigit().frame(width: ProcCols.mem)
                        Button("KILL") { model.killProcess(member.id) }
                            .buttonStyle(.bordered).tint(.red)
                            .controlSize(.small).frame(width: ProcCols.kill)
                    }
                    .font(.system(size: 11))
                }
            }
        }
    }
}

struct FanRow: View {
    @ObservedObject var model: StatsModel
    let fan: FanState
    @State private var sliderValue: Double = 0
    @State private var dragging = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Ventilateur \(fan.id + 1)")
                Spacer()
                Text("\(Int(fan.current)) tr/min")
                    .monospacedDigit().foregroundStyle(.secondary)
                if model.fanManual[fan.id] == true {
                    Button("Auto") { model.setFanAuto(fan.id) }
                        .font(.caption).buttonStyle(.bordered).controlSize(.small)
                }
            }
            Slider(value: $sliderValue,
                   in: fan.min...max(fan.max, fan.min + 1),
                   onEditingChanged: { editing in
                       dragging = editing
                       if !editing {
                           model.setFanSpeed(fan.id, rpm: sliderValue)
                       }
                   })
            .disabled(!model.helperInstalled)
            HStack {
                Text("\(Int(fan.min))").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                if dragging {
                    Text("→ \(Int(sliderValue)) tr/min")
                        .font(.caption2).monospacedDigit()
                }
                Spacer()
                Text("\(Int(fan.max))").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .onAppear { sliderValue = fan.target > 0 ? fan.target : fan.current }
    }
}
