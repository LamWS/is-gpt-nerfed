import Foundation
import Observation
import OSLog
import ServiceManagement

/// Unified-logging channel for the menu bar app (Console.app: subsystem "is-gpt-nerfed"). The ledger's own
/// activity log (`nerfed log`) is the primary record; this only covers what happens inside the app.
let appLog = Logger(subsystem: "is-gpt-nerfed", category: "app")

@MainActor
@Observable
final class Store {
    static let shared = Store()

    var snapshot: Snapshot?
    var lastError: String?
    var refreshing = false
    var lastRefresh: Date?
    var reportText: String?
    var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    private var pollTask: Task<Void, Never>?
    private var lastStatusKey = ""

    var isAlert: Bool { (snapshot?.overall.downgraded ?? 0) > 0 }
    var isWarn: Bool { !isAlert && (snapshot?.overall.suspicious ?? 0) > 0 }
    var isRunning: Bool { (snapshot?.overall.running ?? 0) > 0 }
    /// `NERFED_DEMO=1` renders synthetic English sample data (used for README screenshots).
    let demo = ProcessInfo.processInfo.environment["NERFED_DEMO"] == "1"

    func start(interval: Duration = .seconds(8)) {
        guard pollTask == nil else { return }
        appLog.info("store started, polling every \(interval.components.seconds, privacy: .public)s\(self.demo ? " (demo)" : "", privacy: .public)")
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: interval)
            }
        }
    }

    func refresh() async {
        if refreshing { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let json = try await DGC.run(["snapshot", "--json"] + (demo ? ["--demo"] : []), timeout: 20)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let snap = try decoder.decode(Snapshot.self, from: Data(json.utf8))
            snapshot = snap
            lastError = nil
            lastRefresh = Date()
            let key = "\(snap.overall.status)|\(snap.overall.message)|\(snap.hooks?.state ?? "-")|\(snap.hooks?.desktopLoaded ?? false)"
            if key != lastStatusKey {
                lastStatusKey = key
                appLog.notice("status \(snap.overall.status, privacy: .public): \(snap.overall.message, privacy: .public) · hooks \(snap.hooks?.state ?? "?", privacy: .public) · desktop loaded \(snap.hooks?.desktopLoaded ?? false, privacy: .public)")
            }
        } catch {
            if lastError != error.localizedDescription {
                appLog.error("snapshot failed: \(error.localizedDescription, privacy: .public)")
            }
            lastError = error.localizedDescription
        }
    }

    /// Start (or retry) a background probe of one thread. The worker records the result; the next refresh shows it.
    func probe(_ thread: ThreadInfo) {
        appLog.notice("probe requested from panel for thread \(thread.id, privacy: .public)")
        do {
            try DGC.spawnDetached(["worker", "--thread", thread.id])
            if var snap = snapshot, let i = snap.threads.firstIndex(where: { $0.id == thread.id }) {
                snap.threads[i].probeRunning = true
                snap.overall.running += 1
                snapshot = snap
            }
        } catch {
            appLog.error("probe spawn failed: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
        }
        Task { try? await Task.sleep(for: .seconds(2)); await refresh() }
    }

    /// Global probe: brand-new ephemeral sessions with the default model, no thread context.
    func probeFresh() {
        appLog.notice("fresh-session probe requested from panel")
        do {
            try DGC.spawnDetached(["worker", "--fresh"])
            if var snap = snapshot {
                snap.globalRunning = true
                snap.overall.running += 1
                snapshot = snap
            }
        } catch {
            appLog.error("fresh probe spawn failed: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
        }
        Task { try? await Task.sleep(for: .seconds(2)); await refresh() }
    }

    func resume(_ thread: ThreadInfo) async {
        appLog.notice("resume requested for thread \(thread.id, privacy: .public)")
        do { _ = try await DGC.run(["resume", "--thread", thread.id]) } catch { lastError = error.localizedDescription }
        await refresh()
    }

    func setConfig(_ key: String, _ value: String) async {
        appLog.notice("config \(key, privacy: .public) = \(value, privacy: .public)")
        do { _ = try await DGC.run(["config", "set", key, value]) } catch { lastError = error.localizedDescription }
        await refresh()
    }

    func loadReport() async {
        do { reportText = try await DGC.run(["report"], timeout: 30) } catch { reportText = error.localizedDescription }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = enabled
            appLog.notice("launch at login \(enabled ? "enabled" : "disabled", privacy: .public)")
        } catch {
            lastError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
