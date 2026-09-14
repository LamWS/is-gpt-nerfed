import Foundation
import Observation
import ServiceManagement

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

    var isAlert: Bool { (snapshot?.overall.downgraded ?? 0) > 0 }
    var isWarn: Bool { !isAlert && (snapshot?.overall.suspicious ?? 0) > 0 }
    var isRunning: Bool { (snapshot?.overall.running ?? 0) > 0 }
    /// `DGC_DEMO=1` renders synthetic English sample data (used for README screenshots).
    let demo = ProcessInfo.processInfo.environment["DGC_DEMO"] == "1"

    func start(interval: Duration = .seconds(8)) {
        guard pollTask == nil else { return }
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
            snapshot = try decoder.decode(Snapshot.self, from: Data(json.utf8))
            lastError = nil
            lastRefresh = Date()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Start (or retry) a background probe of one thread. The worker records the result; the next refresh shows it.
    func probe(_ thread: ThreadInfo) {
        do {
            try DGC.spawnDetached(["worker", "--thread", thread.id])
            if var snap = snapshot, let i = snap.threads.firstIndex(where: { $0.id == thread.id }) {
                snap.threads[i].probeRunning = true
                snap.overall.running += 1
                snapshot = snap
            }
        } catch {
            lastError = error.localizedDescription
        }
        Task { try? await Task.sleep(for: .seconds(2)); await refresh() }
    }

    /// Global probe: brand-new ephemeral sessions with the default model, no thread context.
    func probeFresh() {
        do {
            try DGC.spawnDetached(["worker", "--fresh"])
            if var snap = snapshot {
                snap.globalRunning = true
                snap.overall.running += 1
                snapshot = snap
            }
        } catch {
            lastError = error.localizedDescription
        }
        Task { try? await Task.sleep(for: .seconds(2)); await refresh() }
    }

    func resume(_ thread: ThreadInfo) async {
        do { _ = try await DGC.run(["resume", "--thread", thread.id]) } catch { lastError = error.localizedDescription }
        await refresh()
    }

    func setConfig(_ key: String, _ value: String) async {
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
        } catch {
            lastError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
