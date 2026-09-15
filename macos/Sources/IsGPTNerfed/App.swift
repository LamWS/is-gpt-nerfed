import AppKit
import SwiftUI

// MARK: - Menu bar icon: template glyph normally, red on any confirmed downgrade, orange while suspicious.

enum MenuBarIcon {
    static func image(alert: Bool, warn: Bool = false, running: Bool) -> NSImage {
        let name = (alert || warn) ? "pawprint.fill" : (running ? "pawprint.circle" : "pawprint")
        let base = NSImage(systemSymbolName: name, accessibilityDescription: "is-gpt-nerfed")!
        let size = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        if alert || warn {
            let colored = size.applying(NSImage.SymbolConfiguration(paletteColors: [alert ? .systemRed : .systemOrange]))
            let img = base.withSymbolConfiguration(colored) ?? base
            img.isTemplate = false
            return img
        }
        let img = base.withSymbolConfiguration(size) ?? base
        img.isTemplate = true
        return img
    }
}

// MARK: - App delegate (accessory app; --preview opens the panel in a window; --render writes a self-portrait PNG)

final class AppDelegate: NSObject, NSApplicationDelegate {
    var previewWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render"), i + 1 < args.count {
            render(to: args[i + 1])
            return
        }
        if args.contains("--preview") {
            let hosting = NSHostingController(rootView: PanelView().environment(Store.shared))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Inspector Astra"
            window.styleMask = [.titled, .closable]
            window.setFrameOrigin(NSPoint(x: 80, y: 120))
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            previewWindow = window
        }
    }

    /// Headless self-portrait for verification and README screenshots (ImageRenderer cannot composite Liquid Glass,
    /// so the panel renders with its flat fallback). Also writes the menu bar glyphs next to the panel image.
    private func render(to path: String) {
        Task { @MainActor in
            let store = Store.shared
            for _ in 0..<40 where store.snapshot == nil {
                await store.refresh()
                try? await Task.sleep(for: .milliseconds(250))
            }
            for (suffix, settings) in [("", false), ("-settings", true)] {
                let renderer = ImageRenderer(content: PanelView(showSettings: settings).environment(store).environment(\.plainRendering, true)
                                                .frame(width: 460).padding(8).background(Color(nsColor: .windowBackgroundColor)))
                renderer.scale = 2
                if let img = renderer.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: path.replacingOccurrences(of: ".png", with: "\(suffix).png")))
                }
            }
            for (suffix, alert, warn) in [("icon-normal", false, false), ("icon-warn", false, true), ("icon-alert", true, false)] {
                let icon = MenuBarIcon.image(alert: alert, warn: warn, running: false)
                let canvas = NSImage(size: NSSize(width: 44, height: 44))
                canvas.lockFocus()
                NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
                NSRect(x: 0, y: 0, width: 44, height: 44).fill()
                let tinted = icon.copy() as! NSImage
                if icon.isTemplate {
                    tinted.lockFocus()
                    NSColor.white.set()
                    NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
                    tinted.unlockFocus()
                    tinted.isTemplate = false
                }
                tinted.draw(in: NSRect(x: 12, y: 12, width: 20, height: 20), from: .zero, operation: .sourceOver, fraction: 1)
                canvas.unlockFocus()
                if let tiff = canvas.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: path.replacingOccurrences(of: ".png", with: "-\(suffix).png")))
                }
            }
            NSApplication.shared.terminate(nil)
        }
    }
}

// MARK: - App

@main
struct IsGPTNerfedApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let store = Store.shared

    init() {
        Store.shared.start()
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView().environment(store)
        } label: {
            Image(nsImage: MenuBarIcon.image(alert: store.isAlert, warn: store.isWarn, running: store.isRunning))
        }
        .menuBarExtraStyle(.window)

        Window("is-gpt-nerfed report", id: "report") {
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
