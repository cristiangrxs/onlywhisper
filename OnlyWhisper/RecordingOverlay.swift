import AppKit
import SwiftUI

@MainActor
final class OverlayPanel {
    static let shared = OverlayPanel()
    private var panel: NSPanel?
    private let size = NSSize(width: 320, height: 76)

    func show() {
        if panel == nil {
            let view = NSHostingView(rootView: RecordingOverlay().environment(AppModel.shared))
            let panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.ignoresMouseEvents = true
            // The capsule draws its own shadow, a window shadow would not follow its changing width.
            panel.hasShadow = false
            panel.contentView = view
            self.panel = panel
        }
        let mouse = NSEvent.mouseLocation
        panel?.setFrameOrigin(NSPoint(x: mouse.x - size.width / 2, y: mouse.y + 8))
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }
}

struct RecordingOverlay: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            indicator
            Waveform(level: model.level, animated: !reduceMotion && isListening)
                .frame(width: 52, height: 22)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .contentTransition(.opacity)
            Spacer(minLength: 4)
            KeyCap("esc")
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .frame(height: 44)
        .fixedSize(horizontal: true, vertical: false)
        .glassPanel(cornerRadius: 22)
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.snappy(duration: 0.2), value: title)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var indicator: some View {
        if isListening {
            Image(systemName: "circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(.red)
                .symbolEffect(.pulse, isActive: !reduceMotion)
        } else {
            ProgressView()
                .controlSize(.mini)
        }
    }

    private var isListening: Bool {
        !model.isSmoothing && (model.phase == .recording || model.phase == .handsFree)
    }

    private var title: String {
        if model.isSmoothing {
            return t("Smoothing", "Glättet")
        }
        switch model.phase {
        case .working(let text): return text
        case .recording: return t("Listening", "Hört zu")
        case .handsFree: return t("Hands-free", "Freisprechen")
        default: return t("Recording", "Aufnahme")
        }
    }
}

private struct Waveform: View {
    var level: Float
    var animated: Bool
    private static let weights: [CGFloat] = [0.45, 0.75, 1, 0.85, 0.6, 0.9, 0.5]

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Self.weights.indices, id: \.self) { index in
                Capsule()
                    .fill(.primary.opacity(0.85))
                    .frame(width: 3, height: height(for: index))
            }
        }
        .animation(animated ? .smooth(duration: 0.12) : nil, value: level)
    }

    private func height(for index: Int) -> CGFloat {
        guard animated else { return 6 }
        let boosted = min(1, CGFloat(level) * 1.6)
        let wobble = 0.75 + 0.25 * abs(sin(Double(index) * 1.7 + Double(level) * 12))
        return 4 + 18 * boosted * Self.weights[index] * CGFloat(wobble)
    }
}
