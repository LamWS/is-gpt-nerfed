import SwiftUI

// The menu bar popover is already Liquid Glass; content inside stays flat and quiet.
// `plainRendering` is set only by `DoesGPTCheat --render`, where AppKit-backed controls cannot be drawn.

private struct PlainRenderingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var plainRendering: Bool {
        get { self[PlainRenderingKey.self] }
        set { self[PlainRenderingKey.self] = newValue }
    }
}

/// Type scale: exactly two sizes and two weights.
///   title  13pt semibold   thread titles, pet name
///   text   11pt regular    everything else; semibold only for the verdict word and section headers
enum Type {
    static let title = Font.system(size: 13, weight: .semibold)
    static let text = Font.system(size: 11)
    static let strong = Font.system(size: 11, weight: .semibold)
}

/// A quiet group: one level of containment, hairline separators between rows, no nested cards.
struct Group<Content: View>: View {
    let title: String
    var trailing: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(Type.strong).foregroundStyle(.secondary)
                Spacer()
                if let trailing { Text(trailing).font(Type.text).foregroundStyle(.tertiary).lineLimit(1) }
            }
            .padding(.horizontal, 2)
            VStack(spacing: 0) { content }
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }
}

struct RowSeparator: View {
    var body: some View { Divider().opacity(0.6).padding(.leading, 10) }
}

/// Text-only action (Probe / Retry / Resume / Settings / Report / Quit). No icons anywhere in the panel.
struct TextButton: View {
    @Environment(\.plainRendering) private var plain
    let title: String
    var color: Color = .accentColor
    let action: () -> Void

    var body: some View {
        if plain {  // ImageRenderer cannot draw AppKit-backed buttons; the real panel shows the same text as a button
            Text(title).font(Type.strong).foregroundStyle(color)
        } else {
            Button(action: action) {
                Text(title).font(Type.strong).foregroundStyle(color)
            }
            .buttonStyle(.borderless)
        }
    }
}

// MARK: - Faux controls for offscreen rendering

struct PlainValue: View {
    let text: String
    var body: some View {
        HStack(spacing: 4) {
            Text(text).font(Type.text)
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
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
                Text(o).font(o == selected ? Type.strong : Type.text)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(o == selected ? Color(nsColor: .controlBackgroundColor) : .clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .shadow(color: .black.opacity(o == selected ? 0.08 : 0), radius: 1, y: 1)
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct PlainField: View {
    let text: String
    var body: some View {
        Text(text).font(Type.text)
            .padding(.horizontal, 6).padding(.vertical, 3).frame(width: 150, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Color.primary.opacity(0.15)))
    }
}
