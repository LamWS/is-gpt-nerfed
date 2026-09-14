import SwiftUI

// MARK: - Colors and small helpers

extension ProbeSummary {
    var tint: Color {
        if isDowngrade == true { return .red }
        switch verdict {
        case "MATCH": return .green
        case "MISMATCH": return .orange
        case "UNLISTED": return .yellow
        default: return .secondary
        }
    }

    var label: String {
        guard let v = verdict else { return status ?? "?" }
        if v == "MISMATCH", let d = direction { return "MISMATCH · \(d)" }
        return v
    }

    var isFailure: Bool { verdict == "INVALID" || status == "failed" }
}

private func petFace(alert: Bool, running: Bool) -> String {
    if alert { return "(ಠ_ಠ)" }
    if running { return "(•o•)" }
    return "(•ᴗ•)"
}

struct VerdictPill: View {
    let probe: ProbeSummary
    var body: some View {
        Text(probe.label)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(probe.tint.opacity(0.18), in: Capsule())
            .foregroundStyle(probe.tint)
    }
}

// MARK: - Panel

struct PanelView: View {
    @Environment(Store.self) private var store
    @Environment(\.openWindow) private var openWindow
    @Environment(\.plainRendering) private var plain
    @State private var showSettings = false

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 12) {
                header
                globalProbe
                threads
                if showSettings { SettingsView().dgcGlass() }
                footer
            }
        }
        .padding(12)
        .frame(width: 440)
        .task { store.start() }
        .onAppear { Task { await store.refresh() } }
    }

    // MARK: header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(petFace(alert: store.isAlert, running: store.isRunning))
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .frame(width: 64, height: 44)
                .dgcGlass(tint: store.isAlert ? .red.opacity(0.35) : nil, radius: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.snapshot?.config.petName ?? "Inspector Astra")
                    .font(.headline)
                HStack(spacing: 6) {
                    Circle()
                        .fill(store.isAlert ? Color.red : (store.isRunning ? Color.orange : Color.green))
                        .frame(width: 8, height: 8)
                    Text(statusLine)
                        .font(.subheadline)
                        .foregroundStyle(store.isAlert ? .red : .secondary)
                        .lineLimit(2)
                }
                if let ago = store.snapshot?.hooksLastEventAgo, !ago.isEmpty {
                    Text("hooks alive · last event \(ago)").font(.caption2).foregroundStyle(.tertiary)
                } else {
                    Text("no hook events yet · restart Codex and send a message").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            DGCButton(title: "Refresh", systemImage: "arrow.clockwise", iconOnly: true) { Task { await store.refresh() } }
                .help("Refresh now")
        }
        .padding(12)
        .dgcGlass()
    }

    private var statusLine: String {
        if let err = store.lastError { return "dgc error: \(err)" }
        guard let s = store.snapshot else { return "loading…" }
        return s.overall.message
    }

    // MARK: global (fresh-session) probe

    private var globalProbe: some View {
        let snap = store.snapshot
        let running = snap?.globalRunning ?? false
        let last = snap?.globalProbe
        let alert = snap?.globalAlert ?? false
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(alert ? Color.red : Color.accentColor)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 3) {
                Text("Fresh session").font(.callout.weight(.semibold))
                Text("brand-new ephemeral session, no thread context · \(snap?.defaultModel ?? "default model")\(snap?.defaultEffort.map { " @ \($0)" } ?? "")")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if running {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("probing… \(snap?.config.queries ?? 3) fresh sessions").font(.caption)
                    }
                } else if let p = last {
                    HStack(spacing: 6) {
                        VerdictPill(probe: p)
                        Text(freshDetail(p)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .help(p.quote ?? "")
                } else {
                    Text("never probed").font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 6)
            if running {
                EmptyView()
            } else if last?.retryable == true {
                DGCButton(title: "Retry", systemImage: "arrow.clockwise", prominent: true) { store.probeFresh() }
                    .controlSize(.small)
                    .help("The last probe failed on transport/network; run it again")
            } else {
                DGCButton(title: "Probe", systemImage: "play.fill") { store.probeFresh() }
                    .controlSize(.small)
                    .help("Start brand-new ephemeral sessions and fingerprint the model a new session gets")
            }
        }
        .padding(12)
        .dgcGlass(tint: alert ? .red.opacity(0.25) : nil)
    }

    private func freshDetail(_ p: ProbeSummary) -> String {
        if p.isFailure {
            return "\(p.errors?.first ?? "no usable sample") · \(p.finishedAgo ?? "")"
        }
        var s = ""
        if let pred = p.prediction { s += pred }
        if !p.probabilityText.isEmpty { s += " \(p.probabilityText)" }
        if let n = p.usedOutputs, let q = p.queries { s += " · \(n)/\(q)" }
        if let ago = p.finishedAgo, !ago.isEmpty { s += " · \(ago)" }
        return s
    }

    // MARK: threads

    private var threads: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Active threads").font(.subheadline.weight(.semibold))
                Spacer()
                Text("each probe forks that thread with its own context")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            if let list = store.snapshot?.threads, !list.isEmpty {
                if plain {  // offscreen self-portrait: ScrollView does not render, show the first rows flat
                    VStack(spacing: 6) {
                        ForEach(list.prefix(5)) { t in ThreadRow(thread: t) }
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(list) { t in ThreadRow(thread: t) }
                        }
                    }
                    .frame(maxHeight: 340)
                }
            } else {
                Text(store.snapshot == nil ? "Reading the ledger…" : "No Codex threads in the last 48 hours.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
        }
        .padding(12)
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
                Text("dgc \(v)").font(.caption2).foregroundStyle(.tertiary)
            }
            DGCButton(title: "Quit", systemImage: "power") { NSApplication.shared.terminate(nil) }
        }
        .controlSize(.small)
    }
}

// MARK: - Thread row

struct ThreadRow: View {
    @Environment(Store.self) private var store
    let thread: ThreadInfo

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(thread.alert ? Color.red : (thread.active ? Color.green : Color.secondary.opacity(0.35)))
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                Text(thread.title).font(.callout.weight(.semibold)).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                probeLine
                if thread.hardEvidence > 0, let ev = thread.lastEvidence {
                    Label(ev, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.red).lineLimit(2)
                } else if thread.softEvidence > 0, let ev = thread.lastEvidence {
                    Label(ev, systemImage: "questionmark.circle")
                        .font(.caption).foregroundStyle(.orange).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            actions
        }
        .padding(10)
        .dgcGlass(tint: thread.alert ? .red.opacity(0.25) : nil, radius: 12)
    }

    private var subtitle: String {
        var parts: [String] = []
        parts.append("\(thread.model ?? "?")\(thread.effort.map { " @ \($0)" } ?? "")")
        if thread.turns > 0 { parts.append("\(thread.turns) turns") }
        if let ago = thread.updatedAgo, !ago.isEmpty { parts.append(ago) }
        if thread.due { parts.append("probe due") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var probeLine: some View {
        if thread.probeRunning {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("probing… ephemeral forks in flight").font(.caption)
            }
        } else if let p = thread.lastProbe {
            HStack(spacing: 6) {
                VerdictPill(probe: p)
                Text(probeDetail(p)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .help(p.quote ?? "")
        } else {
            Text("no probe yet").font(.caption).foregroundStyle(.tertiary)
        }
    }

    private func probeDetail(_ p: ProbeSummary) -> String {
        if p.isFailure {
            return "\(p.errors?.first ?? "no usable sample") · \(p.finishedAgo ?? "")"
        }
        var s = ""
        if let pred = p.prediction { s += pred }
        if !p.probabilityText.isEmpty { s += " \(p.probabilityText)" }
        if let n = p.usedOutputs, let q = p.queries { s += " · \(n)/\(q)" }
        if let ago = p.finishedAgo, !ago.isEmpty { s += " · \(ago)" }
        return s
    }

    @ViewBuilder private var actions: some View {
        if thread.probeRunning {
            EmptyView()
        } else if thread.halted {
            DGCButton(title: "Resume", systemImage: "lock.open", prominent: true) { Task { await store.resume(thread) } }
                .tint(.red).controlSize(.small)
                .help("Clear the halt (work tools are denied in this thread)")
        } else if thread.lastProbe?.retryable == true {
            DGCButton(title: "Retry", systemImage: "arrow.clockwise", prominent: true) { store.probe(thread) }
                .controlSize(.small)
                .help("The last probe failed on transport/network; run it again")
        } else {
            DGCButton(title: "Probe", systemImage: "play.fill") { store.probe(thread) }
                .controlSize(.small)
                .help("Fork this thread ephemerally and fingerprint the answering model")
        }
    }
}
