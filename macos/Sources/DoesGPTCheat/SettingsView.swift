import SwiftUI

/// Grouped, label-left / control-right rows in the spirit of macOS System Settings, kept to one screen.
struct SettingsView: View {
    @Environment(Store.self) private var store
    @Environment(\.plainRendering) private var plain
    @State private var petName = ""

    private let frequencies: [(String, String)] = [
        ("manual", "Manually"), ("turns:4", "Every 4 turns"), ("turns:8", "Every 8 turns"), ("turns:16", "Every 16 turns"),
        ("30m", "Every 30 min"), ("1h", "Every hour"), ("2h", "Every 2 hours"),
    ]
    private let modes: [(String, String)] = [("auto", "Probe in background"), ("nudge", "Only remind me")]
    private let confidences: [(Double, String)] = [(0.7, "70%"), (0.8, "80%"), (0.9, "90%"), (0.95, "95%")]

    var body: some View {
        let cfg = store.snapshot?.config
        VStack(alignment: .leading, spacing: 8) {
            group("Schedule") {
                row("Probe each thread") { picker(cfg?.frequency ?? "turns:8", frequencies, key: "frequency") }
                row("When a probe is due") { picker(cfg?.mode ?? "auto", modes, key: "mode") }
                row("Forks per probe") {
                    segments(["1", "2", "3"], selected: String(cfg?.queries ?? 3)) { v in Task { await store.setConfig("queries", v) } }
                        .frame(width: 110)
                }
                row("Prompt language") {
                    HStack(spacing: 4) {
                        langToggle("zh", cfg)
                        langToggle("en", cfg)
                    }
                }
                row("Run the forks in parallel") { toggle("parallel", cfg?.parallel ?? true) }
            }
            group("Verdict") {
                row("Call a mismatch at") {
                    segments(confidences.map(\.1), selected: label(for: cfg?.mismatchConfidence ?? 0.8)) { v in
                        if let c = confidences.first(where: { $0.1 == v }) { Task { await store.setConfig("mismatch_confidence", String(c.0)) } }
                    }
                    .frame(width: 190)
                }
                row("Confirm a suspicious round with a second one") { toggle("confirm_uncertain", cfg?.confirmUncertain ?? true) }
                row("Halt the thread after a mismatch") { toggle("halt_on_mismatch", cfg?.haltOnMismatch ?? false) }
                row("Passive rollout scan on every turn") { toggle("passive", cfg?.passive ?? true) }
            }
            group("Alerts") {
                row("Notifications") { toggle("notify", cfg?.notify ?? true) }
                row("Also notify on MATCH") { toggle("notify_on_ok", cfg?.notifyOnOk ?? false) }
                row("Post MATCH verdicts into the thread") { toggle("announce_ok", cfg?.announceOk ?? false) }
                row("Sound on a downgrade") { toggle("sound", cfg?.sound ?? true) }
            }
            group("App") {
                row("Pet name") {
                    if plain {
                        PlainField(text: cfg?.petName ?? "Inspector Astra")
                    } else {
                        TextField("Inspector Astra", text: $petName)
                            .textFieldStyle(.roundedBorder).controlSize(.small).frame(width: 150)
                            .onSubmit { Task { await store.setConfig("pet_name", petName) } }
                    }
                }
                row("Launch at login") {
                    if plain {
                        PlainSwitch(on: store.launchAtLogin)
                    } else {
                        Toggle("", isOn: Binding(get: { store.launchAtLogin }, set: { store.setLaunchAtLogin($0) }))
                            .toggleStyle(.switch).labelsHidden().controlSize(.mini)
                    }
                }
                if let ledger = store.snapshot?.ledger {
                    Text("Ledger: \(ledger)").font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1).padding(.top, 3)
                }
            }
        }
        .padding(10)
        .onAppear { petName = store.snapshot?.config.petName ?? "" }
        .onChange(of: store.snapshot?.config.petName) { _, new in if let new, !new.isEmpty { petName = new } }
    }

    // MARK: building blocks

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
                .padding(.bottom, 4)
            VStack(spacing: 0) { content() }
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func row<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 11)).lineLimit(1)
            Spacer(minLength: 8)
            control()
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .overlay(alignment: .bottom) { Divider().opacity(0.5).padding(.leading, 8) }
    }

    @ViewBuilder
    private func picker(_ current: String, _ options: [(String, String)], key: String) -> some View {
        if plain {
            PlainValue(text: options.first(where: { $0.0 == current })?.1 ?? current)
        } else {
            Picker("", selection: Binding(get: { current }, set: { v in Task { await store.setConfig(key, v) } })) {
                ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
                if !options.contains(where: { $0.0 == current }) { Text(current).tag(current) }
            }
            .labelsHidden().frame(width: 150)
        }
    }

    @ViewBuilder
    private func segments(_ options: [String], selected: String, set: @escaping (String) -> Void) -> some View {
        if plain {
            PlainSegments(options: options, selected: selected)
        } else {
            Picker("", selection: Binding(get: { selected }, set: set)) {
                ForEach(options, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
        }
    }

    @ViewBuilder
    private func toggle(_ key: String, _ value: Bool) -> some View {
        if plain {
            PlainSwitch(on: value)
        } else {
            Toggle("", isOn: Binding(get: { value }, set: { v in Task { await store.setConfig(key, v ? "true" : "false") } }))
                .toggleStyle(.switch).labelsHidden().controlSize(.mini)
        }
    }

    private func langToggle(_ lang: String, _ cfg: DGCConfig?) -> some View {
        let langs = cfg?.languages ?? ["zh", "en"]
        return Toggle(lang, isOn: Binding(
            get: { langs.contains(lang) },
            set: { on in
                var next = langs.filter { $0 != lang }
                if on { next.append(lang) }
                if next.isEmpty { next = [lang] }
                Task { await store.setConfig("languages", next.joined(separator: ",")) }
            }))
        .toggleStyle(.button).controlSize(.small)
    }

    private func label(for confidence: Double) -> String {
        confidences.min(by: { abs($0.0 - confidence) < abs($1.0 - confidence) })?.1 ?? "80%"
    }
}
