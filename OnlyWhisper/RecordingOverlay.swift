import AppKit
import SwiftUI

@MainActor
final class OverlayPanel {
    static let shared = OverlayPanel()
    private var panel: NSPanel?

    func show() {
        if panel == nil {
            let view = NSHostingView(rootView: RecordingOverlay().environment(AppModel.shared))
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 220, height: 72),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hasShadow = false
            panel.contentView = view
            self.panel = panel
        }
        let mouse = NSEvent.mouseLocation
        panel?.setFrameOrigin(NSPoint(x: mouse.x - 110, y: mouse.y + 12))
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
        HStack(spacing: 12) {
            Waveform(level: model.level, animated: !reduceMotion)
                .frame(width: 72, height: 28)
                .accessibilityLabel(t("Recording", "Aufnahme"))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text("Esc")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var title: String {
        if model.isSmoothing {
            return t("Smoothing", "Glättet")
        }
        switch model.phase {
        case .working(let text): return text
        case .recording, .handsFree: return t("Listening", "Hört zu")
        default: return t("Recording", "Aufnahme")
        }
    }
}

private struct Waveform: View {
    var level: Float
    var animated: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<7, id: \.self) { index in
                Capsule()
                    .fill(.primary)
                    .frame(width: 3, height: height(for: index))
            }
        }
    }

    private func height(for index: Int) -> CGFloat {
        guard animated else { return 8 }
        let wave = abs(sin(Double(index) + Double(level) * 8))
        return 6 + CGFloat(level) * 22 * CGFloat(wave)
    }
}
