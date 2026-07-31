import SwiftUI

struct MenuView: View {
    @ObservedObject var model: StatsModel
    @State private var processesExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            headerBar
            processorSection
            storageSection
            networkSection
            processesSection
            fansSection
            claudeSection
            footer
        }
        .padding(12)
        .frame(width: 400)
    }

    // MARK: - En-tête + réglages

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26, height: 26)
                .background(Color.accentColor.opacity(0.13),
                            in: RoundedRectangle(cornerRadius: Theme.innerRadius))
            VStack(alignment: .leading, spacing: 0) {
                Text("InfoPC").font(.system(size: 13, weight: .semibold))
                Text("Surveillance système")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            settingsMenu
        }
        .padding(.horizontal, 2)
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
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: - CPU / GPU

    private var processorSection: some View {
        SectionCard("Processeur", icon: "cpu", trailing: {
            if let w = model.power {
                Badge(text: String(format: "%.1f W", w), tint: .yellow)
            }
        }) {
            usageRow(label: "CPU", usage: model.cpuUsage, temp: model.cpuTemp)
            perCoreGrid
            usageRow(label: "GPU", usage: model.gpuUsage, temp: model.gpuTemp)
        }
    }

    /// Une mesure d'occupation : titre, température, pourcentage, barre.
    private func usageRow(label: String, usage: Double?, temp: Double?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(label).font(.system(size: 12, weight: .medium))
                if let temp {
                    Badge(text: String(format: "%.0f °C", temp), tint: tint(forTemp: temp))
                }
                Spacer()
                Text(usage.map { String(format: "%.0f %%", $0) } ?? "–")
                    .font(.system(size: 12, weight: .semibold)).monospacedDigit()
            }
            ProgressBar(fraction: (usage ?? 0) / 100,
                        color: gaugeColor(forPercent: usage ?? 0))
        }
    }

    /// Usage par cœur logique (P puis E selon sysctl), en petites barres.
    private var perCoreGrid: some View {
        let cores = model.cpuPerCore
        return VStack(alignment: .leading, spacing: 5) {
            if !cores.isEmpty {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(cores.indices, id: \.self) { i in
                        CoreBar(fraction: cores[i] / 100)
                            .help("Cœur \(i + 1) : \(Int(cores[i])) %")
                    }
                    Spacer(minLength: 0)
                }
                Text("\(model.performanceCores) performance · \(model.efficiencyCores) efficience")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Mémoire / disque

    private var storageSection: some View {
        SectionCard("Mémoire & stockage", icon: "internaldrive") {
            if let mem = model.memory {
                capacityRow(label: "Mémoire", icon: "memorychip",
                            used: Format.gib(mem.usedBytes), total: Format.gib(mem.totalBytes),
                            fraction: mem.fraction)
            }
            if let d = model.disk {
                capacityRow(label: "Disque", icon: "externaldrive",
                            used: Format.gib(d.usedBytes), total: Format.gib(d.totalBytes),
                            fraction: d.fraction)
            }
        }
    }

    /// Une capacité occupée : titre, « utilisé / total », barre.
    private func capacityRow(label: String, icon: String,
                             used: String, total: String, fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 10)).foregroundStyle(.secondary)
                Text(label).font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(used) / \(total) Go")
                    .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
            }
            ProgressBar(fraction: fraction, color: gaugeColor(forPercent: fraction * 100))
        }
    }

    // MARK: - Réseau

    private var networkSection: some View {
        SectionCard("Réseau", icon: "network", trailing: {
            if model.network == nil {
                Text("–").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }) {
            if let n = model.network {
                HStack(spacing: 6) {
                    throughput(icon: "arrow.down", value: Format.mbps(n.rxBytesPerSec))
                    throughput(icon: "arrow.up", value: Format.mbps(n.txBytesPerSec))
                    Spacer(minLength: 0)
                }
            }

            // Speed test (débit maximal de la connexion)
            HStack(spacing: 8) {
                Button {
                    model.runSpeedTest()
                } label: {
                    Label("Speed test", systemImage: "gauge.with.dots.needle.67percent")
                        .font(.system(size: 11))
                }
                .controlSize(.small)
                .disabled(model.speedState == .running)

                switch model.speedState {
                case .idle:
                    EmptyView()
                case .running:
                    ProgressView().controlSize(.small)
                    Text("Test en cours…").font(.system(size: 11)).foregroundStyle(.secondary)
                case .done(let down, let up):
                    Badge(text: "↓ \(String(format: "%.0f", down)) Mbps", tint: .accentColor)
                    if let up {
                        Badge(text: "↑ \(String(format: "%.0f", up)) Mbps")
                    }
                case .failed:
                    Badge(text: "Échec du test", tint: .red)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// Un débit instantané, sens indiqué par la flèche.
    private func throughput(icon: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value).font(.system(size: 12, weight: .medium)).monospacedDigit()
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Theme.muted, in: RoundedRectangle(cornerRadius: Theme.innerRadius))
    }

    // MARK: - Processus

    private var processesSection: some View {
        SectionCard("Processus", icon: "list.bullet", trailing: {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { processesExpanded.toggle() }
            } label: {
                Label(processesExpanded ? "Voir moins" : "Voir plus",
                      systemImage: processesExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11))
            }
            .controlSize(.small)
        }) {
            if processesExpanded {
                HStack(spacing: 8) {
                    Picker("Trier", selection: $model.procSort) {
                        ForEach(ProcSortKey.allCases) { key in
                            Text(key.label).tag(key)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 170)
                    Spacer(minLength: 0)
                }
                // En-têtes de colonnes (CPU / GPU / Mém au-dessus du tableau)
                HStack(spacing: 6) {
                    Text("").frame(width: 32)
                    Text("Nom").frame(maxWidth: .infinity, alignment: .leading)
                    Text("CPU").frame(width: ProcCols.cpu)
                    Text("GPU").frame(width: ProcCols.gpu)
                        .help("L'usage GPU par processus n'est pas exposé par macOS")
                    Text("Mém").frame(width: ProcCols.mem)
                    Text("").frame(width: ProcCols.kill)
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)

                if model.processGroups.isEmpty {
                    Text("Chargement…").font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    // Liste défilable, groupée par application
                    ScrollView {
                        VStack(spacing: 3) {
                            ForEach(model.processGroups) { group in
                                ProcGroupRow(model: model, group: group)
                            }
                        }
                        .padding(.trailing, 2)
                    }
                    .frame(height: 240)
                }
            } else {
                Text("\(model.processGroups.count) applications — triées par \(model.procSort.label)")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Ventilateurs

    private var fansSection: some View {
        SectionCard("Ventilateurs", icon: "fan", trailing: {
            Badge(text: model.fans.isEmpty ? "aucun détecté"
                  : "\(model.fans.filter { $0.current > 10 }.count)/\(model.fans.count) actif(s)")
        }) {
            ForEach(model.fans) { fan in
                FanRow(model: model, fan: fan)
            }
            if !model.fans.isEmpty && !model.helperInstalled {
                notice("Contrôle désactivé — lancez scripts/install.sh pour installer le helper.")
            }
            if let text = model.fanNotice {
                notice(text)
            }
        }
    }

    /// Avertissement discret, sur fond teinté plutôt qu'en texte orange nu.
    private func notice(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10))
            Text(text).font(.system(size: 11))
            Spacer(minLength: 0)
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(Color.orange.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: Theme.innerRadius))
    }

    // MARK: - Claude

    private var claudeSection: some View {
        SectionCard("Limites Claude", icon: "sparkles", trailing: {
            if model.claudeLive == nil && model.claude != nil {
                Badge(text: "estimation locale")
            }
        }) {
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
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("≈ \(ClaudeUsageReader.formatTokens(c.tokens)) tokens")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.0f %%", fraction * 100))
                            .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    }
                    ProgressBar(fraction: fraction,
                                color: gaugeColor(forPercent: fraction * 100))
                }
            } else {
                Text("Usage indisponible")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    /// Une barre de limite réelle : titre, jauge remplie au pourcentage, % et reset.
    private func limitBar(title: String, percent: Double, resetsAt: Date?, showDate: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 11, weight: .medium))
                Spacer()
                if let r = resetsAt {
                    let reset = showDate
                        ? r.formatted(date: .abbreviated, time: .shortened)
                        : r.formatted(date: .omitted, time: .shortened)
                    Text("réinit. \(reset)")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                Text(String(format: "%.0f %%", percent))
                    .font(.system(size: 11, weight: .semibold)).monospacedDigit()
            }
            ProgressBar(fraction: percent / 100, color: gaugeColor(forPercent: percent))
        }
    }

    // MARK: - Pied de page

    private var footer: some View {
        HStack {
            if !model.smcAvailable {
                Badge(text: "SMC indisponible", tint: .red)
            }
            Spacer()
            Button("Quitter") { NSApplication.shared.terminate(nil) }
                .controlSize(.small)
        }
        .padding(.horizontal, 2)
    }

    // MARK: - Aides

    /// Teinte d'une température : neutre tant qu'elle reste banale.
    private func tint(forTemp t: Double) -> Color? {
        switch t {
        case ..<70: return nil
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
    @State private var hovering = false

    private var expandable: Bool { group.count > 1 }

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 6) {
                // Flèche de déroulement (si plusieurs processus)
                Button {
                    withAnimation(.easeInOut(duration: 0.12)) { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 10)
                .opacity(expandable ? 1 : 0)
                .disabled(!expandable)

                if let icon = group.icon {
                    Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                } else {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(.secondary).frame(width: 16, height: 16)
                }
                HStack(spacing: 4) {
                    Text(group.name).lineLimit(1).truncationMode(.tail)
                    if expandable {
                        Text("×\(group.count)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Theme.muted, in: Capsule())
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
                    .buttonStyle(.bordered).tint(.red)
                    .controlSize(.small).frame(width: ProcCols.kill)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 6).padding(.vertical, 3)
            // Surlignage au survol : repère la ligne visée avant de cliquer KILL.
            .background(hovering ? Theme.muted : Color.clear,
                        in: RoundedRectangle(cornerRadius: Theme.innerRadius))
            .onHover { hovering = $0 }

            // Processus individuels du groupe
            if expanded {
                ForEach(group.members) { member in
                    HStack(spacing: 6) {
                        Spacer().frame(width: 32)
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
                    .padding(.horizontal, 6)
                }
            }
        }
    }
}

struct FanRow: View {
    @ObservedObject var model: StatsModel
    let fan: FanState
    /// Consigne en attente de confirmation par le SMC : pendant le glissement,
    /// puis le court instant qui suit. `nil` → le curseur suit le SMC, ce qui
    /// est le cas normal en mode auto (le système y écrit lui-même `FxTg`).
    @State private var pending: Double?
    @State private var dragging = false

    private var displayed: Double { pending ?? fan.sliderPosition }

    private var value: Binding<Double> {
        Binding(get: { displayed }, set: { pending = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("Ventilateur \(fan.id + 1)").font(.system(size: 12, weight: .medium))
                Badge(text: fan.manual ? "forcé" : "auto", tint: fan.manual ? .orange : nil)
                Spacer()
                // Au repos, le SMC arrête complètement le ventilateur sur
                // Apple Silicon : « 0 tr/min » se lirait comme une panne.
                Text(fan.current < 1 ? "à l'arrêt" : "\(Int(fan.current)) tr/min")
                    .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                if fan.manual {
                    Button("Auto") {
                        // On relâche l'affichage : le curseur doit repartir sur
                        // la consigne que le système va reprendre.
                        pending = nil
                        model.setFanAuto(fan.id)
                    }
                    .font(.system(size: 11)).buttonStyle(.bordered).controlSize(.small)
                }
            }
            Slider(value: value,
                   in: fan.min...max(fan.max, fan.min + 1),
                   onEditingChanged: { editing in
                       dragging = editing
                       guard !editing else { return }
                       model.setFanSpeed(fan.id, rpm: displayed)
                       // Le SMC applique la consigne en un instant ; on rend
                       // ensuite la main à la valeur relue, pour ne jamais
                       // afficher une position qui n'est plus la vraie.
                       Task { @MainActor in
                           try? await Task.sleep(for: .seconds(2))
                           if !dragging { pending = nil }
                       }
                   })
            .controlSize(.small)
            .disabled(!model.helperInstalled)
            HStack {
                Text("\(Int(fan.min))").font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
                if dragging {
                    Text("→ \(Int(displayed)) tr/min")
                        .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                }
                Spacer()
                Text("\(Int(fan.max))").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 1)
    }
}
