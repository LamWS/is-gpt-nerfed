import SwiftUI

/// Label-left / control-right rows, four quiet groups, sentence case throughout.
struct SettingsView: View {
    @Environment(Store.self) private var store
    @Environment(\.plainRendering) private var plain
    @State private var petName = ""

    private let frequencies: [(String, String)] = [
        ("manual", "Manually"), ("turns:4", "Every 4 turns"), ("turns:8", "Every 8 turns"), ("turns:16", "Every 16 turns"),
        ("30m", "Every 30 minutes"), ("1h", "Every hour"), ("2h", "Every 2 hours"),
    ]
    private let modes: [(String, String)] = [("auto", "Probe in the background"), ("nudge", "Only remind me")]
    private let languages: [(String, String)] = [("zh,en", "Chinese and English"), ("zh", "Chinese"), ("en", "English")]
    private let confidences: [(Double, String)] = [(0.7, "70%"), (0.8, "80%"), (0.9, "90%"), (0.95, "95%")]

    var body: some View {
        let cfg = store.snapshot?.config
        VStack(alignment: .leading, spacing: 14) {
            Group(title: "Schedule") {
                row("Probe each thread") { picker(cfg?.frequency ?? "turns:8", frequencies, key: "frequency") }
                RowSeparator()
                row("When a probe is due") { picker(cfg?.mode ?? "auto", modes, key: "mode") }
                RowSeparator()
                row("Forks per probe") {
                    segments(["1", "2", "3"], selected: String(cfg?.queries ?? 3)) { v in Task { await store.setConfig("queries", v) } }
                        .frame(width: 110)
                }
                RowSeparator()
                row("Prompt language") { picker((cfg?.languages ?? ["zh", "en"]).joined(separator: ","), languages, key: "languages") }
                RowSeparator()
                row("Run the forks in parallel") { toggle("parallel", cfg?.parallel ?? true) }
            }
            Group(title: "Verdict") {
                row("Call a mismatch at") {
                    segments(confidences.map(\.1), selected: label(for: cfg?.mismatchConfidence ?? 0.8)) { v in
                        if let c = confidences.first(where: { $0.1 == v }) { Task { await store.setConfig("mismatch_confidence", String(c.0)) } }
                    }
                    .frame(width: 190)
                }
                RowSeparator()
                row("Confirm a suspicious round with a second one") { toggle("confirm_uncertain", cfg?.confirmUncertain ?? true) }
                RowSeparator()
                row("Halt the thread after a mismatch") { toggle("halt_on_mismatch", cfg?.haltOnMismatch ?? false) }
                RowSeparator()
                row("Scan rollouts on every turn") { toggle("passive", cfg?.passive ?? true) }
            }
            Group(title: "Alerts") {
                row("Notifications") { toggle("notify", cfg?.notify ?? true) }
                RowSeparator()
                row("Also notify on a match") { toggle("notify_on_ok", cfg?.notifyOnOk ?? false) }
                RowSeparator()
                row("Post matches into the thread") { toggle("announce_ok", cfg?.announceOk ?? false) }
                RowSeparator()
                row("Sound on a downgrade") { toggle("sound", cfg?.sound ?? true) }
            }
            Group(title: "App") {
                row("Pet name") {
                    if plain {
                        PlainField(text: cfg?.petName ?? "Inspector Astra")
                    } else {
                        TextField("Inspector Astra", text: $petName)
                            .textFieldStyle(.roundedBorder).controlSize(.small).frame(width: 150)
                            .onSubmit { Task { await store.setConfig("pet_name", petName) } }
                    }
                }
                RowSeparator()
                row("Launch at login") {
                    if plain {
                        PlainSwitch(on: store.launchAtLogin)
                    } else {
                        Toggle("", isOn: Binding(get: { store.launchAtLogin }, set: { store.setLaunchAtLogin($0) }))
                            .toggleStyle(.switch).labelsHidden().controlSize(.mini)
                    }
                }
            }
        }
        .onAppear { petName = store.snapshot?.config.petName ?? "" }
        .onChange(of: store.snapshot?.config.petName) { _, new in if let new, !new.isEmpty { petName = new } }
    }

    // MARK: building blocks

    private func row<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 8) {
            Text(title).font(Type.text).lineLimit(1)
            Spacer(minLength: 8)
            control()
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
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
            .labelsHidden().controlSize(.small).frame(width: 170)
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
            .pickerStyle(.segmented).labelsHidden().controlSize(.small)
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

    private func label(for confidence: Double) -> String {
        confidences.min(by: { abs($0.0 - confidence) < abs($1.0 - confidence) })?.1 ?? "80%"
    }
}
