import SwiftUI

struct MenuView: View {
    @ObservedObject var model: StatsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            processorSection
            Divider()
            memorySection
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

    // MARK: - CPU / GPU

    private var processorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            statRow(icon: "cpu", label: "CPU",
                    usage: model.cpuUsage, temp: model.cpuTemp)
            statRow(icon: "rectangle.3.group", label: "GPU",
                    usage: model.gpuUsage, temp: model.gpuTemp)
        }
    }

    private func statRow(icon: String, label: String, usage: Double?, temp: Double?) -> some View {
        HStack {
            Image(systemName: icon).frame(width: 18)
            Text(label).bold().frame(width: 40, alignment: .leading)
            BatteryGauge(fraction: (usage ?? 0) / 100, color: .white)
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
                BatteryGauge(fraction: mem.fraction, color: .white)
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
                Text("les plus gourmands").font(.caption).foregroundStyle(.secondary)
            }
            // En-têtes de colonnes (le petit tableau : CPU / GPU / Mém au-dessus)
            HStack(spacing: 6) {
                Text("").frame(width: 20)
                Text("Nom").font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("CPU").font(.caption2).foregroundStyle(.secondary).frame(width: ProcCols.cpu)
                Text("GPU").font(.caption2).foregroundStyle(.secondary).frame(width: ProcCols.gpu)
                Text("Mém").font(.caption2).foregroundStyle(.secondary).frame(width: ProcCols.mem)
                Text("").frame(width: ProcCols.kill)
            }
            if model.processes.isEmpty {
                Text("Chargement…").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(model.processes) { proc in
                    ProcessRow(model: model, proc: proc)
                }
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
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "sparkles").frame(width: 18)
                Text("Limites Claude").bold()
                Spacer()
                if let c = model.claude, c.isActive {
                    Text("réinit. \(c.blockEnd.formatted(date: .omitted, time: .shortened))")
                        .foregroundStyle(.secondary).font(.caption)
                }
            }
            if let c = model.claude, c.isActive {
                let fraction = min(1.0, Double(c.tokens) / Double(model.claudeLimit))
                BatteryGauge(fraction: fraction, color: .white)
                HStack {
                    Text("\(ClaudeUsageReader.formatTokens(c.tokens)) / \(ClaudeUsageReader.formatTokens(model.claudeLimit)) tokens")
                    Spacer()
                    Text(String(format: "%.0f %%", fraction * 100)).monospacedDigit()
                }
                .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Aucun bloc de 5 h actif")
                    .font(.caption).foregroundStyle(.secondary)
            }
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

struct ProcessRow: View {
    @ObservedObject var model: StatsModel
    let proc: ProcInfo

    var body: some View {
        HStack(spacing: 6) {
            // Logo du processus
            if let icon = proc.icon {
                Image(nsImage: icon).resizable().frame(width: 18, height: 18)
            } else {
                Image(systemName: "gearshape.fill").frame(width: 18, height: 18)
            }
            Text(proc.name)
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(String(format: "%.0f%%", proc.cpu))
                .monospacedDigit().frame(width: ProcCols.cpu)
            Text("—")   // GPU par processus non exposé par macOS
                .foregroundStyle(.tertiary).frame(width: ProcCols.gpu)
            Text(String(format: "%.1f%%", proc.mem))
                .monospacedDigit().frame(width: ProcCols.mem)

            Button("KILL") { model.killProcess(proc.id) }
                .buttonStyle(.borderedProminent).tint(.red)
                .controlSize(.small).frame(width: ProcCols.kill)
        }
        .font(.system(size: 12))
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
