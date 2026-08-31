import SwiftUI

struct MenuView: View {
    @ObservedObject var model: StatsModel
    /// Observé pour que tout le popover se retraduise dès la bascule.
    @ObservedObject private var loc = Localization.shared
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
                Text(t("Surveillance système", "System monitoring"))
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
            Section(t("Afficher dans la barre", "Show in menu bar")) {
                ForEach(MenuBarItem.allCases) { item in
                    Toggle(item.label, isOn: Binding(
                        get: { model.menuBarItems.contains(item) },
                        set: { on in
                            if on { model.menuBarItems.insert(item) }
                            else { model.menuBarItems.remove(item) }
                        }))
                }
            }
            Section(t("Température de la barre", "Menu bar temperature")) {
                Picker(t("Capteur", "Sensor"), selection: Binding(
                    get: { model.tempSource },
                    set: { model.tempSource = $0 })) {
                    Text("CPU").tag(TempSource.cpu)
                    Text("GPU").tag(TempSource.gpu)
                }
            }
            Section(t("Langue", "Language")) {
                Picker(t("Langue", "Language"), selection: $loc.language) {
                    ForEach(AppLanguage.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
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
        SectionCard(t("Processeur", "Processor"), icon: "cpu", trailing: {
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
                            .help(t("Cœur \(i + 1) : \(Int(cores[i])) %", "Core \(i + 1): \(Int(cores[i]))%"))
                    }
                    Spacer(minLength: 0)
                }
                Text(t("\(model.performanceCores) performance · \(model.efficiencyCores) efficience",
                     "\(model.performanceCores) performance · \(model.efficiencyCores) efficiency"))
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Mémoire / disque

    private var storageSection: some View {
        SectionCard(t("Mémoire & stockage", "Memory & storage"), icon: "internaldrive") {
            if let mem = model.memory {
                capacityRow(label: t("Mémoire", "Memory"), icon: "memorychip",
                            used: Format.gib(mem.usedBytes), total: Format.gib(mem.totalBytes),
                            fraction: mem.fraction)
            }
            if let d = model.disk {
                capacityRow(label: t("Disque", "Disk"), icon: "externaldrive",
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
                Text("\(used) / \(total) \(t("Go", "GB"))")
                    .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
            }
            ProgressBar(fraction: fraction, color: gaugeColor(forPercent: fraction * 100))
        }
    }

    // MARK: - Réseau

    private var networkSection: some View {
        SectionCard(t("Réseau", "Network"), icon: "network", trailing: {
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
                    Text(t("Test en cours…", "Testing…")).font(.system(size: 11)).foregroundStyle(.secondary)
                case .done(let down, let up):
                    Badge(text: "↓ \(String(format: "%.0f", down)) Mbps", tint: .accentColor)
                    if let up {
                        Badge(text: "↑ \(String(format: "%.0f", up)) Mbps")
                    }
                case .failed:
                    Badge(text: t("Échec du test", "Test failed"), tint: .red)
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
        SectionCard(t("Processus", "Processes"), icon: "list.bullet", trailing: {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { processesExpanded.toggle() }
            } label: {
                Label(processesExpanded ? t("Voir moins", "Show less")
                                        : t("Voir plus", "Show more"),
                      systemImage: processesExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11))
            }
            .controlSize(.small)
        }) {
            if processesExpanded {
                HStack(spacing: 8) {
                    Picker(t("Trier", "Sort"), selection: $model.procSort) {
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
                    Text(t("Nom", "Name")).frame(maxWidth: .infinity, alignment: .leading)
                    Text("CPU").frame(width: ProcCols.cpu)
                    Text("GPU").frame(width: ProcCols.gpu)
                        .help(t("L'usage GPU par processus n'est pas exposé par macOS",
                                "macOS doesn't expose per-process GPU usage"))
                    Text(t("Mém", "Mem")).frame(width: ProcCols.mem)
                    Text("").frame(width: ProcCols.kill)
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)

                if model.processGroups.isEmpty {
                    Text(t("Chargement…", "Loading…")).font(.system(size: 11)).foregroundStyle(.secondary)
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
                Text(t("\(model.processGroups.count) applications — triées par \(model.procSort.label)",
                     "\(model.processGroups.count) apps — sorted by \(model.procSort.label)"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Ventilateurs

    private var fansSection: some View {
        SectionCard(t("Ventilateurs", "Fans"), icon: "fan", trailing: {
            Badge(text: model.fans.isEmpty
                  ? t("aucun détecté", "none detected")
                  : t("\(model.fans.filter { $0.current > 10 }.count)/\(model.fans.count) actif(s)",
                      "\(model.fans.filter { $0.current > 10 }.count)/\(model.fans.count) active"))
        }) {
            ForEach(model.fans) { fan in
                FanRow(model: model, fan: fan)
            }
            if !model.fans.isEmpty && !model.helperInstalled {
                VStack(alignment: .leading, spacing: 6) {
                    notice(t("Contrôle désactivé : le pilotage des ventilateurs "
                             + "passe par un helper privilégié.",
                             "Control disabled: driving the fans goes through a "
                             + "privileged helper."))
                    Button(t("Activer le contrôle des ventilateurs…",
                             "Enable fan control…")) {
                        model.installFanHelper()
                    }
                    .controlSize(.small)
                    .help(t("Installe /usr/local/bin/infopc-fanctl et une règle "
                            + "sudo limitée à ce seul binaire. Mot de passe "
                            + "demandé une seule fois.",
                            "Installs /usr/local/bin/infopc-fanctl and a sudo rule "
                            + "limited to that single binary. Password asked once."))
                }
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

    /// Pourquoi cette section porte la mention « expérimental » : elle ne
    /// repose sur aucun contrat public, contrairement au reste de l'app.
    static var experimentalNotice: String {
        t("""
          Fonction expérimentale : elle lit le jeton OAuth de Claude Code dans \
          le Trousseau et interroge un endpoint non documenté d'Anthropic. \
          Anthropic peut le modifier sans préavis — l'affichage peut alors \
          cesser de fonctionner. Le reste de l'app (capteurs, ventilateurs) \
          n'en dépend pas.
          """,
          """
          Experimental feature: it reads the Claude Code OAuth token from the \
          Keychain and calls an undocumented Anthropic endpoint. Anthropic can \
          change it without notice, and this section would then stop working. \
          Nothing else in the app depends on it.
          """)
    }

    private var claudeSection: some View {
        SectionCard(t("Limites Claude", "Claude limits"), icon: "sparkles", trailing: {
            HStack(spacing: 5) {
                if model.claudeLive == nil && model.claude != nil {
                    Badge(text: t("estimation locale", "local estimate"))
                }
                // Cette section s'appuie sur un endpoint non documenté et sur
                // le jeton du Trousseau : elle peut cesser de fonctionner sans
                // préavis. Le dire ici plutôt que de laisser croire à un
                // affichage garanti comme les capteurs matériels.
                Badge(text: t("expérimental", "experimental"), tint: .orange)
                    .help(Self.experimentalNotice)
            }
        }) {
            if let live = model.claudeLive {
                // Usage réel du compte (endpoint OAuth /usage)
                limitBar(title: t("Session (5 h)", "Session (5 h)"),
                         limit: live.fiveHour, showDate: false)
                limitBar(title: t("Semaine (7 j)", "Week (7 d)"),
                         limit: live.sevenDay, showDate: true)
                if let name = live.modelName, let limit = live.model {
                    limitBar(title: t("\(name) (semaine)", "\(name) (week)"),
                             limit: limit, showDate: true)
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("Usage indisponible", "Usage unavailable"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(t("Connectez-vous une fois avec le CLI `claude` : "
                           + "l'app Claude pour macOS ne dépose pas de jeton "
                           + "lisible dans le Trousseau.",
                           "Sign in once with the `claude` CLI: the Claude app "
                           + "for macOS doesn't store a readable token in the "
                           + "Keychain."))
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Une barre de limite réelle : titre, jauge remplie au pourcentage, % et
    /// reset. La couleur suit la gravité annoncée par le serveur.
    private func limitBar(title: String, limit: ClaudeLimitState, showDate: Bool) -> some View {
        let level = gaugeLevel(forSeverity: limit.severity, percent: limit.percent)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 11, weight: .medium))
                Spacer()
                if let r = limit.resetsAt {
                    let reset = showDate
                        ? r.formatted(date: .abbreviated, time: .shortened)
                        : r.formatted(date: .omitted, time: .shortened)
                    Text(t("réinit. \(reset)", "resets \(reset)"))
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                Text(String(format: "%.0f %%", limit.percent))
                    .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    // Le chiffre ne se teinte qu'à partir du premier palier
                    // d'alerte : au repos, la couleur ne signalerait rien.
                    .foregroundStyle(level == .calm ? Color.primary : level.color)
            }
            ProgressBar(fraction: limit.percent / 100, color: level.color)
        }
    }

    // MARK: - Pied de page

    private var footer: some View {
        HStack {
            if !model.smcAvailable {
                Badge(text: t("SMC indisponible", "SMC unavailable"), tint: .red)
            }
            Spacer()
            Button(t("Quitter", "Quit")) { NSApplication.shared.terminate(nil) }
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
    @ObservedObject private var loc = Localization.shared
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
                    .help(t("L'usage GPU par processus n'est pas exposé par macOS",
                                "macOS doesn't expose per-process GPU usage"))
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
                            .help(t("L'usage GPU par processus n'est pas exposé par macOS",
                                "macOS doesn't expose per-process GPU usage"))
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
    @ObservedObject private var loc = Localization.shared
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
                Text(t("Ventilateur \(fan.id + 1)", "Fan \(fan.id + 1)")).font(.system(size: 12, weight: .medium))
                Badge(text: fan.manual ? t("forcé", "forced") : "auto",
                      tint: fan.manual ? .orange : nil)
                Spacer()
                // Au repos, le SMC arrête complètement le ventilateur sur
                // Apple Silicon : « 0 tr/min » se lirait comme une panne.
                Text(fan.current < 1 ? t("à l'arrêt", "stopped")
                     : t("\(Int(fan.current)) tr/min", "\(Int(fan.current)) rpm"))
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
                    Text(t("→ \(Int(displayed)) tr/min", "→ \(Int(displayed)) rpm"))
                        .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                }
                Spacer()
                Text("\(Int(fan.max))").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 1)
    }
}
