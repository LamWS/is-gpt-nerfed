import SwiftUI

// MARK: - Type scale (compact, native): title 13 semibold · meta 11 secondary · pill 10 bold · time 11 tertiary

private enum Type {
    static let title = Font.system(size: 13, weight: .semibold)
    static let meta = Font.system(size: 11)
    static let pill = Font.system(size: 10, weight: .bold)
    static let section = Font.system(size: 10, weight: .semibold)
    static let name = Font.system(size: 14, weight: .semibold)
}

extension ProbeSummary {
    var tint: Color {
        if isDowngrade == true { return .red }
        switch verdict {
        case "MATCH": return .green
        case "MISMATCH": return .orange
        case "SUSPICIOUS": return .orange
        case "UNLISTED": return .yellow
        default: return .secondary
        }
    }

    /// Short pill text; the direction carries the meaning, so "MISMATCH · downgrade" becomes "DOWNGRADE".
    var label: String {
        guard let v = verdict else { return (status ?? "?").uppercased() }
        switch (v, direction) {
        case ("DOWNGRADED!", _): return "DOWNGRADED"
        case ("MISMATCH", "downgrade"?): return "DOWNGRADE"
        case ("MISMATCH", "upgrade"?): return "UPGRADE"
        case ("MISMATCH", _): return "REROUTED"
        default: return v
        }
    }

    var isFailure: Bool { verdict == "INVALID" || status == "failed" }

    /// One dense line: "gpt-5.6-luna 91% · declared 3% · 2 rounds · retried ×1"
    var detail: String {
        var parts: [String] = []
        if isFailure {
            parts.append(errors?.first ?? "no usable sample")
        } else {
            var s = prediction ?? "?"
            if !probabilityText.isEmpty { s += " \(probabilityText)" }
            parts.append(s)
            if let e = expected, e != prediction, let pe = pExpected { parts.append("declared \(Self.pct(pe))") }
            if let n = usedOutputs, let q = queries, n < q { parts.append("\(n)/\(q) answers") }
            if let r = rounds, r > 1 { parts.append("\(r) rounds") }
        }
        if let r = retries, r > 0 { parts.append("retried ×\(r)") }
        return parts.joined(separator: " · ")
    }
}

private func petFace(alert: Bool, warn: Bool, running: Bool) -> String {
    if alert { return "(ಠ_ಠ)" }
    if warn { return "(•_•)" }
    if running { return "(•o•)" }
    return "(•ᴗ•)"
}

struct VerdictPill: View {
    let probe: ProbeSummary
    var body: some View {
        Text(probe.label)
            .font(Type.pill)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(probe.tint.opacity(0.16), in: Capsule())
            .foregroundStyle(probe.tint)
            .lineLimit(1)
            .fixedSize()
    }
}

struct SectionTitle: View {
    let text: String
    var trailing: String? = nil
    var body: some View {
        HStack {
            Text(text.uppercased()).font(Type.section).tracking(0.6).foregroundStyle(.secondary)
            Spacer()
            if let t = trailing { Text(t).font(Type.meta).foregroundStyle(.tertiary).lineLimit(1) }
        }
    }
}

struct TimeStamp: View {
    let text: String?
    var body: some View {
        Text(text ?? "").font(Type.meta).monospacedDigit().foregroundStyle(.tertiary).lineLimit(1)
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
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 10) {
                header
                fresh
                threads
                if showSettings { SettingsView().dgcGlass() }
                footer
            }
        }
        .padding(10)
        .frame(width: 440)
        .task { store.start() }
        .onAppear { Task { await store.refresh() } }
    }

    // MARK: header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(petFace(alert: store.isAlert, warn: store.isWarn, running: store.isRunning))
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .frame(width: 56, height: 40)
                .dgcGlass(tint: store.isAlert ? .red.opacity(0.35) : (store.isWarn ? .orange.opacity(0.3) : nil), radius: 12)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(store.snapshot?.config.petName ?? "Inspector Astra").font(Type.name)
                    if store.snapshot?.demo == true { Text("demo").font(Type.pill).foregroundStyle(.tertiary) }
                }
                HStack(spacing: 5) {
                    Circle()
                        .fill(store.isAlert ? Color.red : (store.isWarn ? Color.orange : (store.isRunning ? Color.blue : Color.green)))
                        .frame(width: 7, height: 7)
                    Text(statusLine)
                        .font(Type.meta.weight(store.isAlert || store.isWarn ? .semibold : .regular))
                        .foregroundStyle(store.isAlert ? .red : (store.isWarn ? .orange : .secondary))
                        .lineLimit(1)
                }
                recentDots
            }
            Spacer(minLength: 4)
            DGCButton(title: "Refresh", systemImage: "arrow.clockwise", iconOnly: true) { Task { await store.refresh() } }
                .controlSize(.small)
                .help("Refresh now")
        }
        .padding(10)
        .dgcGlass()
    }

    private var statusLine: String {
        if let err = store.lastError { return "dgc error: \(err)" }
        guard let s = store.snapshot else { return "loading…" }
        return s.overall.message
    }

    private var hooksLine: String {
        if let ago = store.snapshot?.hooksLastEventAgo, !ago.isEmpty { return "hooks alive \(ago)" }
        return "no hook events yet"
    }

    @ViewBuilder private var recentDots: some View {
        let recent = store.snapshot?.recentProbes ?? []
        HStack(spacing: 3) {
            ForEach(recent.prefix(12)) { p in
                Circle().fill(p.isFailure ? Color.secondary.opacity(0.4) : p.tint).frame(width: 6, height: 6)
                    .help("\(p.label) · \(p.detail) · \(p.finishedAgo ?? "")")
            }
            Text(recent.isEmpty ? hooksLine : "\(min(recent.count, 12)) probes · \(hooksLine)")
                .font(Type.meta).foregroundStyle(.tertiary).lineLimit(1).padding(.leading, recent.isEmpty ? 0 : 3)
        }
    }

    // MARK: fresh session (global probe)

    private var fresh: some View {
        let snap = store.snapshot
        let running = snap?.globalRunning ?? false
        let last = snap?.globalProbe
        let alert = snap?.globalAlert ?? false
        return VStack(alignment: .leading, spacing: 6) {
            SectionTitle(text: "Fresh session", trailing: "\(snap?.defaultModel ?? "default model")\(snap?.defaultEffort.map { " @ \($0)" } ?? "") · no thread context")
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "sparkles").font(.system(size: 12)).foregroundStyle(alert ? Color.red : Color.accentColor)
                if running {
                    ProgressView().controlSize(.mini)
                    Text("probing \(snap?.config.queries ?? 3) new ephemeral sessions…").font(Type.meta)
                } else if let p = last {
                    VerdictPill(probe: p)
                    Text(p.detail).font(Type.meta).foregroundStyle(.secondary).lineLimit(1).help(p.quote ?? "")
                    Spacer(minLength: 4)
                    TimeStamp(text: p.finishedAgo)
                } else {
                    Text("never probed").font(Type.meta).foregroundStyle(.tertiary)
                }
                if !running {
                    Spacer(minLength: 0)
                    actionButton(retry: last?.retryable == true, help: "Start brand-new ephemeral sessions and fingerprint what a new session gets") { store.probeFresh() }
                }
            }
        }
        .padding(10)
        .dgcGlass(tint: alert ? .red.opacity(0.25) : nil)
    }

    // MARK: threads

    private var threads: some View {
        let list = store.snapshot?.threads ?? []
        return VStack(alignment: .leading, spacing: 6) {
            SectionTitle(text: "Active threads", trailing: list.isEmpty ? nil : "\(list.count) in the last 48 h · each probe forks that thread")
            if !list.isEmpty {
                if plain {  // offscreen self-portrait: ScrollView does not render, show the first rows flat
                    VStack(spacing: 4) { ForEach(list.prefix(6)) { t in ThreadRow(thread: t) } }
                } else {
                    ScrollView {
                        VStack(spacing: 4) { ForEach(list) { t in ThreadRow(thread: t) } }
                    }
                    .frame(maxHeight: 330)
                }
            } else {
                Text(store.snapshot == nil ? "Reading the ledger…" : "No Codex threads in the last 48 hours.")
                    .font(Type.meta).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .padding(10)
        .dgcGlass()
    }

    // MARK: footer

    private var footer: some View {
        HStack {
            DGCButton(title: showSettings ? "Hide settings" : "Settings", systemImage: "slider.horizontal.3") {
                withAnimation(.snappy) { showSettings.toggle() }
            }
            DGCButton(title: "Report", systemImage: "doc.text.magnifyingglass") {
                Task { await store.loadReport() }
                openWindow(id: "report")
            }
            Spacer()
            if let v = store.snapshot?.version {
                Text("dgc \(v)").font(Type.meta).foregroundStyle(.tertiary)
            }
            DGCButton(title: "Quit", systemImage: "power") { NSApplication.shared.terminate(nil) }
        }
        .controlSize(.small)
    }
}

// MARK: - Shared action button

@ViewBuilder
func actionButton(retry: Bool, help: String, action: @escaping () -> Void) -> some View {
    if retry {
        DGCButton(title: "Retry", systemImage: "arrow.clockwise", prominent: true, iconOnly: true, action: action)
            .controlSize(.small)
            .help("The last probe failed on transport/network even after one automatic retry; run it again")
    } else {
        DGCButton(title: "Probe", systemImage: "play.fill", iconOnly: true, action: action)
            .controlSize(.small)
            .help(help)
    }
}

// MARK: - Thread row

struct ThreadRow: View {
    @Environment(Store.self) private var store
    let thread: ThreadInfo

    private var dot: Color {
        if thread.alert { return .red }
        if thread.suspicious == true { return .orange }
        return thread.active ? .green : .secondary.opacity(0.35)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(dot).frame(width: 7, height: 7).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(thread.title).font(Type.title).lineLimit(1)
                    Spacer(minLength: 4)
                    TimeStamp(text: thread.updatedAgo)
                }
                Text(meta).font(Type.meta).foregroundStyle(.secondary).lineLimit(1)
                probeLine
                if thread.hardEvidence > 0, let ev = thread.lastEvidence {
                    Label(ev, systemImage: "exclamationmark.triangle.fill").font(Type.meta).foregroundStyle(.red).lineLimit(2)
                } else if thread.softEvidence > 0, let ev = thread.lastEvidence {
                    Label(ev, systemImage: "questionmark.circle").font(Type.meta).foregroundStyle(.orange).lineLimit(1)
                }
            }
            actions
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .dgcGlass(tint: thread.alert ? .red.opacity(0.22) : (thread.suspicious == true ? .orange.opacity(0.18) : nil), radius: 10)
    }

    private var meta: String {
        var parts = ["\(thread.model ?? "?")\(thread.effort.map { " @ \($0)" } ?? "")"]
        if thread.turns > 0 { parts.append("\(thread.turns) turns") }
        if thread.halted { parts.append("halted") }
        if thread.due { parts.append("probe due") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var probeLine: some View {
        if thread.probeRunning {
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text("probing… ephemeral forks in flight").font(Type.meta).foregroundStyle(.secondary)
            }
        } else if let p = thread.lastProbe {
            HStack(spacing: 5) {
                VerdictPill(probe: p)
                Text(p.detail).font(Type.meta).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 2)
                TimeStamp(text: p.finishedAgo)
            }
            .help(p.quote ?? "")
        } else {
            Text("no probe yet").font(Type.meta).foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder private var actions: some View {
        if thread.probeRunning {
            EmptyView()
        } else if thread.halted {
            DGCButton(title: "Resume", systemImage: "lock.open", prominent: true, iconOnly: true) { Task { await store.resume(thread) } }
                .tint(.red).controlSize(.small)
                .help("Clear the halt (work tools are denied in this thread)")
        } else {
            actionButton(retry: thread.lastProbe?.retryable == true,
                         help: "Fork this thread ephemerally (3 parallel forks) and fingerprint the answering model") { store.probe(thread) }
        }
    }
}
