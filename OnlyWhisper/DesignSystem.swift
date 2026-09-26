import AppKit
import SwiftUI

enum DS {
    static let spacingXS: CGFloat = 4
    static let spacingS: CGFloat = 8
    static let spacingM: CGFloat = 12
    static let spacingL: CGFloat = 16
    static let spacingXL: CGFloat = 20

    static let panelRadius: CGFloat = 16
    static let cardRadius: CGFloat = 12
    static let rowRadius: CGFloat = 8
    static let tileRadius: CGFloat = 6

    static let rowHeight: CGFloat = 40
    static let searchHeight: CGFloat = 56
    static let actionBarHeight: CGFloat = 40
    static let panelWidth: CGFloat = 750
    static let panelHeight: CGFloat = 474

    static let selection = Color.primary.opacity(0.09)
    static let hover = Color.primary.opacity(0.05)
    static let cardFill = Color.primary.opacity(0.045)
    static let hairline = Color.primary.opacity(0.08)
}

// MARK: - Icons and key caps

struct IconTile: View {
    var symbol: String
    var tint: Color
    var size: CGFloat = 22

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: size * 0.52, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.gradient, in: shape)
            .overlay(shape.strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
            .shadow(color: tint.opacity(0.25), radius: size * 0.08, y: size * 0.04)
            .accessibilityHidden(true)
    }
}

struct KeyCap: View {
    var key: String

    init(_ key: String) {
        self.key = key
    }

    var body: some View {
        Text(key)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .frame(minWidth: 20, minHeight: 20)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

struct KeyCaps: View {
    var keys: [String]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                KeyCap(key)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(keys.joined(separator: " "))
    }
}

struct ShortcutHint: View {
    var label: String
    var keys: [String]

    var body: some View {
        HStack(spacing: DS.spacingS) {
            Text(label)
            Spacer(minLength: DS.spacingS)
            KeyCaps(keys: keys)
        }
    }
}

// MARK: - Lists

struct PaletteRow: View {
    var symbol: String
    var tint: Color
    var title: String
    var subtitle: String?
    var accessory: String?
    var keys: [String] = []
    var isSelected: Bool
    var isEnabled = true

    var body: some View {
        HStack(spacing: DS.spacingM) {
            IconTile(symbol: symbol, tint: tint, size: 22)
                .saturation(isEnabled ? 1 : 0)
            HStack(spacing: DS.spacingS) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: DS.spacingS)
            if let accessory {
                Text(accessory)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if !keys.isEmpty {
                KeyCaps(keys: keys)
            }
        }
        .padding(.horizontal, DS.spacingS)
        .frame(height: DS.rowHeight)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: DS.rowRadius, style: .continuous)
                    .fill(DS.selection)
            }
        }
        .opacity(isEnabled ? 1 : 0.5)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

struct SectionHeader: View {
    var title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.spacingS)
            .padding(.top, DS.spacingS)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }
}

struct EmptyStateView: View {
    var symbol: String
    var title: String
    var message: String?

    var body: some View {
        VStack(spacing: DS.spacingS) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            if let message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct StatusBadge: View {
    var title: String
    var tint: Color

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

// MARK: - Search field

struct PaletteSearchField: View {
    var placeholder: String
    @Binding var text: String
    var focus: FocusState<Bool>.Binding
    var fontSize: CGFloat = 18

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: fontSize))
            .focused(focus)
            .padding(.horizontal, DS.spacingL + 2)
            .frame(height: DS.searchHeight)
    }
}

// MARK: - Action bar

struct ActionBar<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: DS.spacingS) {
            leading
            Spacer(minLength: DS.spacingS)
            trailing
        }
        .padding(.horizontal, DS.spacingM)
        .frame(height: DS.actionBarHeight)
        .background(Color.primary.opacity(0.03))
        .overlay(alignment: .top) {
            Rectangle().fill(DS.hairline).frame(height: 1)
        }
    }
}

struct ActionBarButton: View {
    var title: String
    var keys: [String]
    var isPrimary = false
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: isPrimary ? .semibold : .medium))
                    .foregroundStyle(isPrimary ? .primary : .secondary)
                KeyCaps(keys: keys)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovering ? DS.hover : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(title)
    }
}

struct ActionBarDivider: View {
    var body: some View {
        Rectangle()
            .fill(DS.hairline)
            .frame(width: 1, height: 16)
    }
}

struct AppBadge: View {
    var text: String

    var body: some View {
        HStack(spacing: DS.spacingS) {
            IconTile(symbol: "waveform", tint: .indigo, size: 18)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

// MARK: - Action menu (Cmd+K)

struct MenuAction: Identifiable {
    let id: String
    let title: String
    let symbol: String
    var keys: [String] = []
    var isDestructive = false
    let perform: @MainActor () -> Void
}

struct ActionMenu: View {
    var title: String
    var actions: [MenuAction]
    @Binding var selection: Int
    var onRun: (MenuAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, DS.spacingS)
                .padding(.vertical, 4)
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                HStack(spacing: DS.spacingS) {
                    Image(systemName: action.symbol)
                        .frame(width: 16)
                        .foregroundStyle(action.isDestructive ? Color.red : Color.secondary)
                    Text(action.title)
                        .foregroundStyle(action.isDestructive ? Color.red : Color.primary)
                    Spacer(minLength: DS.spacingM)
                    KeyCaps(keys: action.keys)
                }
                .font(.system(size: 13))
                .padding(.horizontal, DS.spacingS)
                .frame(height: 30)
                .background {
                    if index == selection {
                        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(DS.selection)
                    }
                }
                .contentShape(Rectangle())
                .onHover { if $0 { selection = index } }
                .onTapGesture { onRun(action) }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
            }
        }
        .padding(6)
        .frame(width: 280)
        .glassPanel(cornerRadius: DS.cardRadius)
        .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
    }
}

// MARK: - Surfaces

struct GlassPanel: ViewModifier {
    var cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if reduceTransparency {
            content
                .background(Color(nsColor: .windowBackgroundColor), in: shape)
                .clipShape(shape)
                .overlay(shape.strokeBorder(DS.hairline))
        } else {
            content
                .clipShape(shape)
                .glassEffect(.regular, in: shape)
        }
    }
}

struct GlassWindow: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .containerBackground(Color(nsColor: .windowBackgroundColor), for: .window)
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            content
                .containerBackground(.thinMaterial, for: .window)
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        }
    }
}

struct Card: ViewModifier {
    var padding: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.cardFill, in: shape)
            .overlay(shape.strokeBorder(DS.hairline))
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = DS.panelRadius) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius))
    }

    func glassWindow() -> some View {
        modifier(GlassWindow())
    }

    func card(padding: CGFloat = DS.spacingL) -> some View {
        modifier(Card(padding: padding))
    }

    /// Handles key presses for the view's window before text fields see them. Return true to consume the event.
    func onKeyDown(_ handler: @escaping @MainActor (NSEvent) -> Bool) -> some View {
        background(KeyDownMonitor(handler: handler))
    }
}

// MARK: - Keyboard

enum Key {
    static let returnKey: UInt16 = 36
    static let enter: UInt16 = 76
    static let escape: UInt16 = 53
    static let up: UInt16 = 126
    static let down: UInt16 = 125
    static let delete: UInt16 = 51

    static func isReturn(_ event: NSEvent) -> Bool {
        event.keyCode == returnKey || event.keyCode == enter
    }

    static func modifiers(_ event: NSEvent) -> NSEvent.ModifierFlags {
        event.modifierFlags.intersection([.command, .shift, .option, .control])
    }

    static func character(_ event: NSEvent) -> String {
        event.charactersIgnoringModifiers?.lowercased() ?? ""
    }

    /// The event in the same notation the UI shows in key caps, e.g. ["⌘", "↵"].
    static func symbols(_ event: NSEvent) -> [String] {
        let flags = modifiers(event)
        var result: [String] = []
        if flags.contains(.control) { result.append("⌃") }
        if flags.contains(.option) { result.append("⌥") }
        if flags.contains(.shift) { result.append("⇧") }
        if flags.contains(.command) { result.append("⌘") }
        switch event.keyCode {
        case returnKey, enter: result.append("↵")
        case delete: result.append("⌫")
        case escape: result.append("esc")
        default: result.append(character(event).uppercased())
        }
        return result
    }

    static func matches(_ event: NSEvent, _ keys: [String]) -> Bool {
        !keys.isEmpty && symbols(event) == keys.map { $0.uppercased() == "ESC" ? "esc" : $0.uppercased() }
    }
}

private struct KeyDownMonitor: NSViewRepresentable {
    var handler: @MainActor (NSEvent) -> Bool

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.handler = handler
        return view
    }

    func updateNSView(_ nsView: MonitorView, context: Context) {
        nsView.handler = handler
    }

    final class MonitorView: NSView {
        var handler: (@MainActor (NSEvent) -> Bool)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                nonisolated(unsafe) let event = event
                let handled = MainActor.assumeIsolated {
                    guard let self, let window = self.window, event.window === window else { return false }
                    return self.handler?(event) ?? false
                }
                return handled ? nil : event
            }
        }
    }
}
