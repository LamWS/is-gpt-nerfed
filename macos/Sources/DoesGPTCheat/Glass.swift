import SwiftUI

// Liquid Glass everywhere in the real menu bar panel; a flat fallback when the panel renders itself
// offscreen (ImageRenderer cannot composite glass or AppKit-backed controls), used by `DoesGPTCheat --render`.

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
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            content
                .background(Color(nsColor: .controlBackgroundColor), in: shape)
                .background((tint ?? .clear).opacity(tint == nil ? 0 : 0.6), in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.07)))
                .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
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

// MARK: - Faux controls for offscreen rendering (AppKit-backed pickers/toggles/fields do not render there)

struct PlainValue: View {
    let text: String
    var body: some View {
        HStack(spacing: 4) {
            Text(text).font(.system(size: 11))
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.primary.opacity(0.1)))
    }
}

struct PlainSwitch: View {
    let on: Bool
    var body: some View {
        Capsule()
            .fill(on ? Color.green : Color.secondary.opacity(0.3))
            .frame(width: 26, height: 15)
            .overlay(alignment: on ? .trailing : .leading) {
                Circle().fill(.white).frame(width: 13, height: 13).padding(1).shadow(color: .black.opacity(0.2), radius: 0.5, y: 0.5)
            }
    }
}

struct PlainSegments: View {
    let options: [String]
    let selected: String
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { o in
                Text(o).font(.system(size: 11, weight: o == selected ? .semibold : .regular))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(o == selected ? Color(nsColor: .controlBackgroundColor) : .clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .shadow(color: .black.opacity(o == selected ? 0.08 : 0), radius: 1, y: 1)
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct PlainField: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 11))
            .padding(.horizontal, 6).padding(.vertical, 3).frame(width: 150, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Color.primary.opacity(0.15)))
    }
}
