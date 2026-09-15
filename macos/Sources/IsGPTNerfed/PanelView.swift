import SwiftUI

// MARK: - Verdict presentation: one coloured word, no pills, no icons. The only colours in the panel are the
// semantic ones (green / orange / red) on dots, verdict words and evidence lines.

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
        } else if staleAccount == true {
            parts.append(prediction ?? "?")  // unverified for this account: the numbers would only lend false weight
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

private func parseISO(_ s: String) -> Date? {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: s) ?? { f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f.date(from: s) }()
}

/// "today 17:50" or "Sep 14, 17:50", in the Mac's time zone.
private func when(_ d: Date) -> String {
    let f = DateFormatter()
    if Calendar.current.isDateInToday(d) {
        f.dateFormat = "HH:mm"
        return "today " + f.string(from: d)
    }
    f.dateFormat = "MMM d, HH:mm"
    return f.string(from: d)
}

/// The chip face that matches the app icon (bundled as face-ok / face-warn / face-alert.png); text fallback.
struct FaceView: View {
    let alert: Bool
    let warn: Bool
    let running: Bool
    var size: CGFloat = 56

    private var image: NSImage? {
        let name = alert ? "face-alert" : (warn ? "face-warn" : "face-ok")
        guard let res = Bundle.main.resourcePath else { return nil }
        return NSImage(contentsOfFile: res + "/\(name).png")
    }

    var body: some View {
        if let img = image {
            Image(nsImage: img).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            Text(petFace(alert: alert, warn: warn, running: running))
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .frame(width: size + 8, height: size - 8)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }
}

/// "Match · gpt-6-astra 100% · 10h ago" as one line, verdict word coloured; dimmed when it cannot vouch for
/// the signed-in account.
struct VerdictLine: View {
    let probe: ProbeSummary
    var body: some View {
        let stale = probe.staleAccount == true
        HStack(spacing: 4) {
            Text(probe.word).font(Type.strong).foregroundStyle(stale ? Color.secondary : probe.tint)
            Text("·").foregroundStyle(.tertiary)
            Text(probe.detail).foregroundStyle(stale ? .tertiary : .secondary).lineLimit(1)
            if stale {
                Text("·").foregroundStyle(.tertiary)
                Text(probe.accountState == "unknown" ? "account unknown" : "another account").foregroundStyle(.tertiary).fixedSize()
                    .help(probe.accountState == "unknown"
                          ? "Recorded before accounts were tracked, so it cannot vouch for the signed-in account. Re-probed when the thread is next active."
                          : "Probed while a different Codex account was signed in; it does not vouch for this account. Re-probed when the thread is next active.")
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
    @Environment(\.plainRendering) private var plain
    @State private var showSettings: Bool
    @State private var open: String?        // the row showing its report in place: a thread id, or "fresh"
    @State private var listHeight: CGFloat = 0

    init(showSettings: Bool = false, open: String? = nil) {
        _showSettings = State(initialValue: showSettings)
        _open = State(initialValue: open)
    }

    var body: some View {
        VStack(spacing: 14) {
            header
            if showSettings {  // a page of its own: it replaces the lists rather than stacking under them
                SettingsView().transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                setup
                threads
                fresh
            }
            footer
        }
        .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 10)
        .frame(width: 420)
        .task { store.start() }
        .onAppear { Task { await store.refresh() } }
    }

    private func toggle(_ id: String) {
        withAnimation(.snappy(duration: 0.25)) { open = (open == id) ? nil : id }
    }

    // MARK: header

    // The face, then two lines: the verdict of the moment, and account and plumbing in one quiet line.
    private var header: some View {
        HStack(spacing: 12) {
            FaceView(alert: store.isAlert, warn: store.isWarn, running: store.isRunning)
            VStack(alignment: .leading, spacing: 3) {
                Text(statusWord)
                    .font(Type.title)
                    .foregroundStyle(store.isAlert ? .red : (store.isWarn ? .orange : .primary))
                    .lineLimit(1)
                if let (text, attention) = hooksLine, attention {
                    Text(text).font(Type.strong).foregroundStyle(.orange).lineLimit(1)
                } else {
                    // One quiet line, never wrapped: drop the least important part until it fits.
                    ViewThatFits(in: .horizontal) {
                        ForEach(statusRestCandidates, id: \.self) { Text($0).lineLimit(1).fixedSize(horizontal: true, vertical: false) }
                        Text(statusRestCandidates.last ?? "").lineLimit(1)
                    }
                    .font(Type.text).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
    }

    private var statusWord: String {
        if let err = store.lastError { return "nerfed error: \(err)" }
        guard let s = store.snapshot else { return "Loading…" }
        let m = s.overall.message
        return m.prefix(1).uppercased() + m.dropFirst()
    }

    /// "w…@example.com · hooks alive 12s ago · switched 45m ago", then the same without the switch note, then the
    /// account alone: the first that fits on one line is shown.
    private var statusRestCandidates: [String] {
        guard let s = store.snapshot, store.lastError == nil else { return [""] }
        let acct = s.account?.label ?? ""
        let hooks = hooksLine?.0
        let switched = s.account?.switchedAgo.map { "switched \($0)" }
        let full = [acct, hooks, switched].compactMap { $0 }.filter { !$0.isEmpty }
        let noSwitch = [acct, hooks].compactMap { $0 }.filter { !$0.isEmpty }
        var out: [String] = []
        for c in [full.joined(separator: " · "), noSwitch.joined(separator: " · "), acct] where !c.isEmpty && !out.contains(c) { out.append(c) }
        return out.isEmpty ? [""] : out
    }

    /// Hook plumbing state; attention = true whenever Codex will not run the hooks yet.
    private var hooksLine: (String, Bool)? {
        guard let s = store.snapshot, store.lastError == nil else { return nil }
        guard let h = s.hooks else {
            if let ago = s.hooksLastEventAgo, !ago.isEmpty { return ("hooks alive \(ago)", false) }
            return ("no hook events yet", false)
        }
        switch h.state {
        case "untrusted":
            return ("Hooks not trusted by Codex · run nerfed hooks trust", true)
        case "missing":
            return ("Codex does not list the plugin's hooks · run install.sh", true)
        default:
            if h.desktopLoaded != true {
                return ("Codex has not loaded the plugin yet · quit and reopen Codex", true)
            }
            if h.desktopLoadedCurrent != true, let stale = h.staleSinceInstallS, stale > 240 {
                return ("Codex still runs the previous version · quit and reopen Codex", true)
            }
            return ("hooks alive \(h.lastDesktopEventAgo ?? "just now")", false)
        }
    }

    // MARK: first-run setup (only while something is missing)

    @ViewBuilder private var setup: some View {
        if let s = store.snapshot, store.lastError == nil, let inst = s.install {
            if inst.codexFound == false {
                setupRow("Codex is not installed on this Mac. Install the Codex app, then reopen this panel.", button: nil)
            } else if inst.pluginEnabled == false {
                setupRow("The plugin is not registered with Codex yet. Install adds the bundled plugin and records hook trust.",
                         button: store.installing ? nil : "Install") { Task { await store.installPlugin() } }
            } else if s.hooks?.state == "untrusted" {
                setupRow("Codex has not been told to trust the plugin's hooks, so nothing runs in your threads yet.",
                         button: "Trust hooks") { Task { await store.trustHooks() } }
            }
        }
    }

    private func setupRow(_ text: String, button: String?, action: @escaping () -> Void = {}) -> some View {
        Group(title: "Setup") {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(Color.orange).frame(width: 7, height: 7)
                Text(text).font(Type.text).foregroundStyle(.secondary).lineLimit(3)
                Spacer(minLength: 8)
                if store.installing {
                    ProgressView().controlSize(.small)
                } else if let button {
                    RowButton(title: button, action: action)
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
                        ThreadRow(thread: t, isOpen: open == t.id) { toggle(t.id) }
                    }
                }
            } else {
                // A ScrollView inside a self-sizing popover collapses to zero height, so size it from the
                // measured content height (capped) instead of letting the layout guess.
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { i, t in
                            if i > 0 { RowSeparator() }
                            ThreadRow(thread: t, isOpen: open == t.id) { toggle(t.id) }
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
                }
                .frame(height: min(open == nil ? 340 : 460, max(listHeight, 56)))
                .animation(.snappy(duration: 0.25), value: listHeight)
            }
        }
    }

    // MARK: fresh session (global probe)

    private var fresh: some View {
        let snap = store.snapshot
        let running = snap?.globalRunning ?? false
        let last = snap?.globalProbe
        return Group(title: "Fresh session", trailing: "\(snap?.defaultModel ?? "default model")\(snap?.defaultEffort.map { " @ \($0)" } ?? "")") {
            ExpandableRow(isOpen: open == "fresh", toggle: { toggle("fresh") }) {
                HStack(alignment: .center, spacing: 8) {
                    Circle().fill(last.map { ($0.isFailure || $0.staleAccount == true) ? Color.secondary.opacity(0.35) : $0.tint } ?? Color.secondary.opacity(0.35))
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
                        RowButton(title: last?.retryable == true ? "Retry" : "Probe") { store.probeFresh() }
                            .help("Start brand-new ephemeral sessions and fingerprint what a new session gets")
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
            } detail: {
                DetailView(probes: snap?.globalProbes ?? (last.map { [$0] } ?? []), evidence: [], reportText: snap?.globalReportText,
                           empty: "No fresh-session probe yet. Probe starts new ephemeral sessions with the default model and no history.")
            }
            .contextMenu {
                if !running { Button(last?.retryable == true ? "Retry the probe" : "Probe now") { store.probeFresh() } }
                if let r = snap?.globalReportText { Button("Copy report") { store.copy(r) } }
            }
        }
    }

    // MARK: footer

    private var footer: some View {
        HStack(spacing: 16) {
            TextButton(title: showSettings ? "Done" : "Settings") { withAnimation(.snappy(duration: 0.25)) { showSettings.toggle() } }
            Spacer()
            if let v = store.snapshot?.version {
                Text("v\(v)" + (store.snapshot?.demo == true ? " · sample data" : "")).font(Type.text).foregroundStyle(.tertiary)
            }
            TextButton(title: "Quit") { NSApplication.shared.terminate(nil) }
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - Rows that open in place

/// The summary stays where it is and the report slides in under it, so nothing else in the panel moves.
/// A hover tint and a link pointer say the row is clickable; the row's own button keeps its own click.
struct ExpandableRow<Summary: View, Detail: View>: View {
    @Environment(\.plainRendering) private var plain
    let isOpen: Bool
    let toggle: () -> Void
    @ViewBuilder let summary: () -> Summary
    @ViewBuilder let detail: () -> Detail
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summary()
                .contentShape(Rectangle())
                .onTapGesture(perform: toggle)
            if isOpen {
                detail().transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(hovered && !plain ? Color.primary.opacity(0.035) : Color.clear)
        .onHover { hovered = $0 }
        .pointerStyle(.link)
    }
}

/// The report, in place: fingerprint, probe facts, earlier probes, evidence with what was reverted. Text only.
struct DetailView: View {
    @Environment(Store.self) private var store
    let probes: [ProbeSummary]
    let evidence: [EvidenceInfo]
    let reportText: String?
    let empty: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let p = probes.first {
                if let r = p.results, !r.isEmpty, !p.isFailure, p.staleAccount != true {
                    fact("Fingerprint", r.map { "\($0.model ?? "?") \(ProbeSummary.pct($0.probability))" }.joined(separator: " · "))
                }
                fact("Probe", facts(p))
                ForEach(Array((p.errors ?? []).enumerated()), id: \.offset) { _, e in
                    fact("Problem", e, tint: .orange)
                }
                if p.staleAccount == true {
                    fact("Account", p.accountState == "unknown"
                         ? "recorded before accounts were tracked; it cannot vouch for the signed-in account"
                         : "probed under another Codex account; it does not vouch for this one")
                }
            } else {
                Text(empty).foregroundStyle(.tertiary).lineLimit(2)
            }
            ForEach(Array(probes.dropFirst().prefix(4))) { p in
                HStack(spacing: 4) {
                    Text("Earlier").foregroundStyle(.tertiary)
                    Text("·").foregroundStyle(.tertiary)
                    VerdictLine(probe: p)
                }
            }
            ForEach(evidence) { e in
                let on = e.active ?? true
                Text(e.text + (e.ago.map { " · \($0)" } ?? "") + (on ? "" : " · reverted"))
                    .foregroundStyle(on ? (e.severity == "hard" ? Color.red : Color.orange) : Color.secondary)
                    .lineLimit(2)
            }
            if let reportText {
                HStack {
                    Spacer()
                    TextButton(title: "Copy report") { store.copy(reportText) }
                }
                .padding(.top, 2)
            }
        }
        .font(Type.text)
        .foregroundStyle(.secondary)
        .padding(.leading, 25).padding(.trailing, 10).padding(.bottom, 8)
    }

    private func fact(_ label: String, _ value: String, tint: Color = .secondary) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text(label).foregroundStyle(.tertiary).frame(width: 64, alignment: .leading)
            Text(value).foregroundStyle(tint).lineLimit(3)
        }
    }

    /// "a1b2c3d4e5 · ephemeral forks · 3 of 3 answers · 41 s · today 17:50"
    private func facts(_ p: ProbeSummary) -> String {
        var parts = [p.id]
        if let m = p.mode { parts.append(m == "fresh" ? "fresh session" : "ephemeral forks") }
        if let n = p.usedOutputs, let q = p.queries, q > 0 { parts.append("\(n) of \(q) answers") }
        if let r = p.rounds, r > 1 { parts.append("\(r) rounds") }
        if let s = p.elapsedS { parts.append("\(Int(s.rounded())) s") }
        if let f = p.finished, let d = parseISO(f) { parts.append(when(d)) }
        return parts.joined(separator: " · ")
    }
}

/// The finding with its time when that fits on one line; without the time otherwise (a lone "9m ago" on a second
/// line is worse than no time; the report in the open row has it).
struct EvidenceLine: View {
    let text: String
    let ago: String?
    let color: Color

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Text(text + (ago.map { " · \($0)" } ?? "")).lineLimit(1).fixedSize(horizontal: true, vertical: false)
            Text(text).lineLimit(2)
        }
        .font(Type.text).foregroundStyle(color)
    }
}

// MARK: - Thread row
//
//   ● Title                                        ┌───────┐
//     model @ effort · N turns · active 2m ago     │ Probe │   ← one action, vertically centred
//     Match · gpt-6-astra 100% · 5m ago            └───────┘
//     Evidence: … (only when there is any)
//     ┄ report, when the row is open ┄

struct ThreadRow: View {
    @Environment(Store.self) private var store
    let thread: ThreadInfo
    let isOpen: Bool
    let toggle: () -> Void

    private var dot: Color {
        if thread.alert { return .red }
        if thread.suspicious == true { return .orange }
        if thread.unverified == true { return .secondary.opacity(0.35) }
        if let p = thread.lastProbe, p.verdict == "MATCH" { return .green }
        return .secondary.opacity(0.35)
    }

    var body: some View {
        ExpandableRow(isOpen: isOpen, toggle: toggle) {
            HStack(alignment: .center, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(dot).frame(width: 7, height: 7).padding(.top, 5)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(thread.title).font(Type.title).lineLimit(1)
                        Text(meta).font(Type.text).foregroundStyle(.secondary).lineLimit(1)
                        if thread.probeRunning {
                            HStack(spacing: 5) {
                                ProgressView().controlSize(.mini)
                                Text(thread.probeNote.map { "Probing · \($0)…" } ?? "Probing, ephemeral forks in flight…").font(Type.text).foregroundStyle(.secondary)
                            }
                        } else if let p = thread.lastProbe {
                            VerdictLine(probe: p)
                        } else {
                            Text(thread.due ? "No probe yet · due" : "No probe yet").font(Type.text).foregroundStyle(.tertiary)
                        }
                        if thread.hardEvidence > 0, let ev = thread.lastEvidence {
                            EvidenceLine(text: ev, ago: thread.lastEvidenceAgo, color: .red)
                                .help("Found in the thread's own records, independent of any probe, and still in effect. Open the row for the history.")
                        } else if thread.softEvidence > 0, let ev = thread.lastEvidence {
                            EvidenceLine(text: ev, ago: thread.lastEvidenceAgo, color: .orange)
                                .help("Applied through thread settings and still in effect: either you changed it, or Codex did (it lowers effort automatically at usage limits). Open the row for the history.")
                        }
                    }
                }
                Spacer(minLength: 8)
                action
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
        } detail: {
            DetailView(probes: thread.probes ?? (thread.lastProbe.map { [$0] } ?? []), evidence: thread.evidence ?? [],
                       reportText: thread.reportText, empty: thread.due ? "No probe yet · due at the next turn" : "No probe yet")
        }
        .contextMenu {
            if !thread.probeRunning, !thread.halted {
                Button(thread.lastProbe?.retryable == true ? "Retry the probe" : "Probe now") { store.probe(thread) }
            }
            if let r = thread.reportText { Button("Copy report") { store.copy(r) } }
            if let cwd = thread.cwd, !cwd.isEmpty { Button("Reveal folder in Finder") { store.reveal(cwd) } }
        }
    }

    private var meta: String {
        var parts = ["\(thread.model ?? "?")\(thread.effort.map { " @ \($0)" } ?? "")"]
        if thread.turns > 0 { parts.append(thread.turns == 1 ? "1 turn" : "\(thread.turns) turns") }
        if thread.halted { parts.append("halted") }
        if let ago = thread.updatedAgo, !ago.isEmpty { parts.append("active \(ago)") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var action: some View {
        if thread.probeRunning {
            EmptyView()
        } else if thread.halted {
            RowButton(title: "Resume", destructive: true) { Task { await store.resume(thread) } }
                .help("Clear the halt (work tools are denied in this thread)")
        } else {
            RowButton(title: thread.lastProbe?.retryable == true ? "Retry" : "Probe") { store.probe(thread) }
                .help("Fork this thread ephemerally (3 parallel forks) and fingerprint the answering model")
        }
    }
}
