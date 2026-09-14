import SwiftUI

// Liquid Glass everywhere in the real menu bar panel; a flat fallback when the panel renders itself
// offscreen (ImageRenderer cannot composite glass), used by `DoesGPTCheat --render`.

private struct PlainRenderingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var plainRendering: Bool {
        get { self[PlainRenderingKey.self] }
        set { self[PlainRenderingKey.self] = newValue }
    }
}

struct DGCGlass: ViewModifier {
    @Environment(\.plainRendering) private var plain
    var tint: Color? = nil
    var radius: CGFloat = 16

    func body(content: Content) -> some View {
        if plain {
            content
                .background((tint ?? Color.primary).opacity(tint == nil ? 0.06 : 0.16),
                            in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Color.primary.opacity(0.08)))
        } else if let tint {
            content.glassEffect(.regular.tint(tint), in: .rect(cornerRadius: radius))
        } else {
            content.glassEffect(.regular, in: .rect(cornerRadius: radius))
        }
    }
}

extension View {
    func dgcGlass(tint: Color? = nil, radius: CGFloat = 16) -> some View {
        modifier(DGCGlass(tint: tint, radius: radius))
    }
}

struct DGCButton: View {
    @Environment(\.plainRendering) private var plain
    let title: String
    let systemImage: String
    var prominent = false
    var iconOnly = false
    let action: () -> Void

    var body: some View {
        if plain {
            styled(Button(title, systemImage: systemImage, action: action).buttonStyle(.bordered))
        } else if prominent {
            styled(Button(title, systemImage: systemImage, action: action).buttonStyle(.glassProminent))
        } else {
            styled(Button(title, systemImage: systemImage, action: action).buttonStyle(.glass))
        }
    }

    @ViewBuilder private func styled<V: View>(_ v: V) -> some View {
        if iconOnly { v.labelStyle(.iconOnly) } else { v }
    }
}
