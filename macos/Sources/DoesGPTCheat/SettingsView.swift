import SwiftUI

struct SettingsView: View {
    @Environment(Store.self) private var store

    private let frequencies: [(String, String)] = [
        ("manual", "Manual only"), ("turns:4", "Every 4 turns"), ("turns:8", "Every 8 turns"),
        ("turns:16", "Every 16 turns"), ("30m", "Every 30 min"), ("1h", "Every hour"), ("2h", "Every 2 hours"),
    ]

    var body: some View {
        let cfg = store.snapshot?.config
        VStack(alignment: .leading, spacing: 10) {
            Text("Settings").font(.subheadline.weight(.semibold))
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Probe frequency")
                    Picker("", selection: Binding(
                        get: { cfg?.frequency ?? "turns:8" },
                        set: { v in Task { await store.setConfig("frequency", v) } })) {
                        ForEach(frequencies, id: \.0) { Text($0.1).tag($0.0) }
                        if let f = cfg?.frequency, !frequencies.contains(where: { $0.0 == f }) { Text(f).tag(f) }
                    }
                    .labelsHidden().frame(width: 170)
                }
                GridRow {
                    Text("When due")
                    Picker("", selection: Binding(
                        get: { cfg?.mode ?? "auto" },
                        set: { v in Task { await store.setConfig("mode", v) } })) {
                        Text("Probe in background").tag("auto")
                        Text("Only remind me").tag("nudge")
                    }
                    .labelsHidden().frame(width: 170)
                }
                GridRow {
                    Text("Forks per probe")
                    Picker("", selection: Binding(
                        get: { cfg?.queries ?? 3 },
                        set: { v in Task { await store.setConfig("queries", String(v)) } })) {
                        Text("1").tag(1); Text("2").tag(2); Text("3 (100% calibrated)").tag(3)
                    }
                    .labelsHidden().frame(width: 170)
                }
                GridRow {
                    Text("Prompt languages")
                    HStack {
                        langToggle("zh", cfg)
                        langToggle("en", cfg)
                    }
                }
            }
            Divider().padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 6) {
                toggle("Run the three forks in parallel", "parallel", cfg?.parallel ?? true)
                toggle("Passive rollout scan every turn", "passive", cfg?.passive ?? true)
                toggle("Notifications", "notify", cfg?.notify ?? true)
                toggle("Also notify on MATCH", "notify_on_ok", cfg?.notifyOnOk ?? false)
                toggle("Post MATCH verdicts into the thread", "announce_ok", cfg?.announceOk ?? false)
                toggle("Sound on a downgrade", "sound", cfg?.sound ?? true)
                toggle("Halt the thread after a mismatch (deny work tools until Resume)", "halt_on_mismatch", cfg?.haltOnMismatch ?? false)
                Toggle("Launch at login", isOn: Binding(get: { store.launchAtLogin }, set: { store.setLaunchAtLogin($0) }))
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            HStack {
                Text("Pet name")
                TextField("Inspector Astra", text: Binding(
                    get: { cfg?.petName ?? "" },
                    set: { _ in }), prompt: Text("Inspector Astra"))
                .textFieldStyle(.roundedBorder)
                .onSubmit { }
                .disabled(true)
                .help("Change with: dgc config set pet_name \"…\"")
            }
            .font(.caption)
            if let ledger = store.snapshot?.ledger {
                Text("ledger: \(ledger)").font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
        .padding(12)
        .font(.callout)
    }

    private func toggle(_ title: String, _ key: String, _ value: Bool) -> some View {
        Toggle(title, isOn: Binding(get: { value }, set: { v in Task { await store.setConfig(key, v ? "true" : "false") } }))
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
        .toggleStyle(.button)
        .controlSize(.small)
    }
}
