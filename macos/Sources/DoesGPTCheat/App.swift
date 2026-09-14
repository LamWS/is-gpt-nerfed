import AppKit
import SwiftUI

// MARK: - Menu bar icon (a red, non-template glyph when any thread is downgraded)

enum MenuBarIcon {
    static func image(alert: Bool, running: Bool) -> NSImage {
        let name = alert ? "pawprint.fill" : (running ? "pawprint.circle" : "pawprint")
        let base = NSImage(systemSymbolName: name, accessibilityDescription: "does-gpt-cheat")!
        let size = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        if alert {
            let red = size.applying(NSImage.SymbolConfiguration(paletteColors: [.systemRed]))
            let img = base.withSymbolConfiguration(red) ?? base
            img.isTemplate = false
            return img
        }
        let img = base.withSymbolConfiguration(size) ?? base
        img.isTemplate = true
        return img
    }
}

// MARK: - App delegate (accessory app; optional --preview window for screenshots)

final class AppDelegate: NSObject, NSApplicationDelegate {
    var previewWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render"), i + 1 < args.count {
            // Headless self-portrait for verification: render the panel (and the menu bar glyphs) to PNG, then quit.
            let path = args[i + 1]
            Task { @MainActor in
                let store = Store.shared
                for _ in 0..<40 where store.snapshot == nil {  // the poller may already be refreshing; wait for data
                    await store.refresh()
                    try? await Task.sleep(for: .milliseconds(250))
                }
                if ProcessInfo.processInfo.environment["DGC_FAKE_ALERT"] == "1", var snap = store.snapshot {
                    var fake = ProbeSummary(id: "fake000001", threadId: snap.threads.first?.id, mode: "fork", status: "done",
                                            finished: snap.generated, finishedAgo: "2m ago", verdict: "MISMATCH", direction: "downgrade",
                                            expected: "gpt-6-astra", prediction: "gpt-5.6-luna", probability: 0.91, usedOutputs: 3,
                                            queries: 3, elapsedS: 41, errors: [], quote: "Congrats! You've been downgraded!",
                                            isDowngrade: true, retryable: false, retries: 0)
                    if !snap.threads.isEmpty {
                        snap.threads[0].lastProbe = fake
                        snap.threads[0].alert = true
                        snap.threads[0].hardEvidence = 1
                        snap.threads[0].lastEvidence = "model gpt-6-astra → gpt-reserve with no settings change (downgrade)"
                    }
                    if snap.threads.count > 1 {
                        fake.verdict = "INVALID"; fake.status = "failed"; fake.isDowngrade = false; fake.retryable = true
                        fake.errors = ["codex thread/fork timed out after 45s"]
                        snap.threads[1].lastProbe = fake
                    }
                    snap.overall.downgraded = 1
                    snap.overall.status = "alert"
                    snap.overall.message = "1 thread downgraded"
                    store.snapshot = snap
                }
                let renderer = ImageRenderer(content: PanelView().environment(store).environment(\.plainRendering, true)
                                                .frame(width: 440).padding(8).background(Color(nsColor: .windowBackgroundColor)))
                renderer.scale = 2
                if let img = renderer.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: path))
                }
                for (suffix, alert) in [("icon-normal", false), ("icon-alert", true)] {
                    let icon = MenuBarIcon.image(alert: alert, running: false)
                    let canvas = NSImage(size: NSSize(width: 44, height: 44))
                    canvas.lockFocus()
                    NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
                    NSRect(x: 0, y: 0, width: 44, height: 44).fill()
                    let tinted = icon.copy() as! NSImage
                    if icon.isTemplate {  // emulate the menu bar's template rendering (white on dark)
                        tinted.lockFocus(); NSColor.white.set(); NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop); tinted.unlockFocus()
                        tinted.isTemplate = false
                    }
                    tinted.draw(in: NSRect(x: 12, y: 12, width: 20, height: 20), from: .zero, operation: .sourceOver, fraction: 1)
                    canvas.unlockFocus()
                    if let tiff = canvas.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
                        try? png.write(to: URL(fileURLWithPath: path.replacingOccurrences(of: ".png", with: "-\(suffix).png")))
                    }
                }
                NSApplication.shared.terminate(nil)
            }
            return
        }
        if CommandLine.arguments.contains("--preview") {
            let root = PanelView().environment(Store.shared)
            let hosting = NSHostingController(rootView: root)
            let window = NSWindow(contentViewController: hosting)
            window.title = "Inspector Astra"
            window.styleMask = [.titled, .closable]
            window.setFrameOrigin(NSPoint(x: 80, y: 120))
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            previewWindow = window
        }
    }
}

// MARK: - App

@main
struct DoesGPTCheatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let store = Store.shared

    init() {
        Store.shared.start()
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView().environment(store)
        } label: {
            Image(nsImage: MenuBarIcon.image(alert: store.isAlert, running: store.isRunning))
        }
        .menuBarExtraStyle(.window)

        Window("does-gpt-cheat report", id: "report") {
            ReportView().environment(store)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 760, height: 520)
    }
}

struct ReportView: View {
    @Environment(Store.self) private var store

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            Text(store.reportText ?? "Loading report…")
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 640, minHeight: 400)
        .task { await store.loadReport() }
    }
}
