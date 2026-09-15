import SwiftUI

// MARK: - Verdict presentation: one colored word, no pills, no icons

extension ProbeSummary {
    var tint: Color {
        if isDowngrade == true { return .red }
        switch verdict {
        case "MATCH": return .green
        case "MISMATCH", "SUSPICIOUS": return .orange
        default: return .secondary
        }
    }

    /// Sentence-case verdict word; the direction carries the meaning ("Downgrade" rather than "Mismatch · downgrade").
    var word: String {
        guard let v = verdict else { return status == "failed" ? "Failed" : "…" }
        switch (v, direction) {
        case ("DOWNGRADED!", _): return "Downgraded"
        case ("MISMATCH", "downgrade"?): return "Downgrade"
        case ("MISMATCH", "upgrade"?): return "Upgrade"
        case ("MISMATCH", _): return "Rerouted"
        case ("SUSPICIOUS", _): return "Suspicious"
        case ("MATCH", _): return "Match"
        case ("UNLISTED", _): return "Unlisted"
        case ("INVALID", _): return "Invalid"
        default: return v.capitalized
        }
    }

    var isFailure: Bool { verdict == "INVALID" || status == "failed" }

    /// "gpt-5.6-luna 91%, declared 3% · 2 rounds · retried once"
    var detail: String {
        var parts: [String] = []
        if isFailure {
            parts.append(errors?.first ?? "no usable sample")
        } else {
            var s = prediction ?? "?"
            if !probabilityText.isEmpty { s += " \(probabilityText)" }
            if let e = expected, e != prediction, let pe = pExpected { s += ", declared \(Self.pct(pe))" }
            parts.append(s)
            if let n = usedOutputs, let q = queries, n < q { parts.append("\(n) of \(q) answers") }
            if let r = rounds, r > 1 { parts.append("\(r) rounds") }
        }
        if let r = retries, r > 0 { parts.append(r == 1 ? "retried once" : "retried \(r)×") }
        return parts.joined(separator: " · ")
    }
}

private func petFace(alert: Bool, warn: Bool, running: Bool) -> String {
    if alert { return "(ಠ_ಠ)" }
    if warn { return "(•_•)" }
    if running { return "(•o•)" }
    return "(•ᴗ•)"
}

/// "Match · gpt-6-astra 100% · 10h ago" as one line, verdict word colored.
struct VerdictLine: View {
    let probe: ProbeSummary
    var body: some View {
        let stale = probe.staleAccount == true  // obtained under another Codex account: dimmed, does not vouch
        HStack(spacing: 4) {
            Text(probe.word).font(Type.strong).foregroundStyle(stale ? Color.secondary : probe.tint)
            Text("·").foregroundStyle(.tertiary)
            Text(probe.detail).foregroundStyle(stale ? .tertiary : .secondary).lineLimit(1)
            if stale {
                Text("·").foregroundStyle(.tertiary)
                Text("another account").foregroundStyle(.tertiary).fixedSize()
                    .help("Probed while a different Codex account was signed in; it does not vouch for this account. Re-probed when the thread is next active.")
            }
            if let ago = probe.finishedAgo, !ago.isEmpty {
                Text("·").foregroundStyle(.tertiary)
                Text(ago).monospacedDigit().foregroundStyle(.tertiary)
            }
        }
        .font(Type.text)
        .help(probe.quote ?? "")
    }
}

// MARK: - Panel

struct PanelView: View {
    @Environment(Store.self) private var store
    @Environment(\.openWindow) private var openWindow
    @Environment(\.plainRendering) private var plain
    @State private var showSettings: Bool

    init(showSettings: Bool = false) {
        _showSettings = State(initialValue: showSettings)
    }

    var body: some View {
        VStack(spacing: 14) {
            header
            fresh
            threads
            if showSettings { SettingsView() }
            footer
        }
        .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)
        .frame(width: 420)
        .task { store.start() }
        .onAppear { Task { await store.refresh() } }
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 12) {
            Text(petFace(alert: store.isAlert, warn: store.isWarn, running: store.isRunning))
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .frame(width: 52, height: 36)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(store.snapshot?.config.petName ?? "Inspector Astra").font(Type.title)
                    if store.snapshot?.demo == true { Text("sample data").font(Type.text).foregroundStyle(.tertiary) }
                }
                Text(statusWord)
                    .font(store.isAlert || store.isWarn ? Type.strong : Type.text)
                    .foregroundStyle(store.isAlert ? .red : (store.isWarn ? .orange : .secondary))
                    .lineLimit(1)
                Text(statusRest).font(Type.text).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer()
        }
    }

    private var statusWord: String {
        if let err = store.lastError { return "nerfed error: \(err)" }
        guard let s = store.snapshot else { return "Loading…" }
        let m = s.overall.message
        return m.prefix(1).uppercased() + m.dropFirst()
    }

    private var statusRest: String {
        guard let s = store.snapshot, store.lastError == nil else { return "" }
        var parts: [String] = []
        if let acct = s.account?.label, !acct.isEmpty { parts.append(acct) }
        if let ago = s.hooksLastEventAgo, !ago.isEmpty { parts.append("hooks alive \(ago)") } else { parts.append("no hook events yet") }
        return parts.joined(separator: " · ")
    }

    // MARK: fresh session (global probe)

    private var fresh: some View {
        let snap = store.snapshot
        let running = snap?.globalRunning ?? false
        let last = snap?.globalProbe
        return Group(title: "Fresh session", trailing: "\(snap?.defaultModel ?? "default model")\(snap?.defaultEffort.map { " @ \($0)" } ?? "")") {
            HStack(spacing: 8) {
                Circle().fill(last.map { $0.isFailure ? Color.secondary.opacity(0.35) : $0.tint } ?? Color.secondary.opacity(0.35))
                    .frame(width: 7, height: 7)
                if running {
                    ProgressView().controlSize(.mini)
                    Text("Probing \(snap?.config.queries ?? 3) new ephemeral sessions…").font(Type.text).foregroundStyle(.secondary)
                } else if let p = last {
                    VerdictLine(probe: p)
                } else {
                    Text("Never probed · a new session, no thread context").font(Type.text).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if !running {
                    TextButton(title: last?.retryable == true ? "Retry" : "Probe") { store.probeFresh() }
                        .help("Start brand-new ephemeral sessions and fingerprint what a new session gets")
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
        }
    }

    // MARK: threads

    private var threads: some View {
        let list = store.snapshot?.threads ?? []
        return Group(title: "Active threads", trailing: list.isEmpty ? nil : "\(list.count) in 48 h") {
            if list.isEmpty {
                Text(store.snapshot == nil ? "Reading the ledger…" : "No Codex threads in the last 48 hours.")
                    .font(Type.text).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 40)
            } else if plain {  // offscreen self-portrait: ScrollView does not render
                VStack(spacing: 0) {
                    ForEach(Array(list.prefix(6).enumerated()), id: \.element.id) { i, t in
                        if i > 0 { RowSeparator() }
                        ThreadRow(thread: t)
                    }
                }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { i, t in
                            if i > 0 { RowSeparator() }
                            ThreadRow(thread: t)
                        }
                    }
                }
                .frame(maxHeight: 330)
            }
        }
    }

    // MARK: footer

    private var footer: some View {
        HStack(spacing: 16) {
            TextButton(title: showSettings ? "Hide settings" : "Settings") { withAnimation(.snappy) { showSettings.toggle() } }
            TextButton(title: "Report") {
                Task { await store.loadReport() }
                openWindow(id: "report")
            }
            Spacer()
            if let v = store.snapshot?.version { Text("v\(v)").font(Type.text).foregroundStyle(.tertiary) }
            TextButton(title: "Quit", color: .secondary) { NSApplication.shared.terminate(nil) }
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - Thread row: title + time · model line · verdict line · evidence (only when present)

struct ThreadRow: View {
    @Environment(Store.self) private var store
    let thread: ThreadInfo

    private var dot: Color {
        if thread.alert { return .red }
        if thread.suspicious == true { return .orange }
        if thread.unverified == true { return .secondary.opacity(0.35) }
        if let p = thread.lastProbe, p.verdict == "MATCH" { return .green }
        return .secondary.opacity(0.35)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(dot).frame(width: 7, height: 7).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(thread.title).font(Type.title).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(thread.updatedAgo ?? "").font(Type.text).monospacedDigit().foregroundStyle(.tertiary)
                    action
                }
                Text(meta).font(Type.text).foregroundStyle(.secondary).lineLimit(1)
                if thread.probeRunning {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.mini)
                        Text("Probing, ephemeral forks in flight…").font(Type.text).foregroundStyle(.secondary)
                    }
                } else if let p = thread.lastProbe {
                    VerdictLine(probe: p)
                }
                if thread.hardEvidence > 0, let ev = thread.lastEvidence {
                    Text("Evidence: \(ev)").font(Type.text).foregroundStyle(.red).lineLimit(2)
                } else if thread.softEvidence > 0, let ev = thread.lastEvidence {
                    Text("Check: \(ev)").font(Type.text).foregroundStyle(.orange).lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
    }

    private var meta: String {
        var parts = ["\(thread.model ?? "?")\(thread.effort.map { " @ \($0)" } ?? "")"]
        if thread.turns > 0 { parts.append("\(thread.turns) turns") }
        if thread.lastProbe == nil && !thread.probeRunning { parts.append("no probe yet") }
        if thread.halted { parts.append("halted") }
        if thread.due { parts.append("probe due") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var action: some View {
        if thread.probeRunning {
            EmptyView()
        } else if thread.halted {
            TextButton(title: "Resume", color: .red) { Task { await store.resume(thread) } }
                .help("Clear the halt (work tools are denied in this thread)")
        } else {
            TextButton(title: thread.lastProbe?.retryable == true ? "Retry" : "Probe") { store.probe(thread) }
                .help("Fork this thread ephemerally (3 parallel forks) and fingerprint the answering model")
        }
    }
}
