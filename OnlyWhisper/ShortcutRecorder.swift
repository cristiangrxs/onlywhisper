import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts
import SwiftUI

/// Records a shortcut and shows the keys that are held, with a trailing plus until the chord is complete.
struct ShortcutRecorder: View {
    @Environment(AppModel.self) private var model
    var mode: ShortcutCaptureMode
    var keys: [String]
    var allowsClear: Bool
    var onCommit: (DictationKey) -> Void
    var onClear: () -> Void

    @State private var recordingID: UUID?
    @State private var preview: [String] = []
    @State private var capture: ShortcutCapture

    init(
        mode: ShortcutCaptureMode,
        keys: [String],
        allowsClear: Bool,
        onCommit: @escaping (DictationKey) -> Void,
        onClear: @escaping () -> Void = {}
    ) {
        self.mode = mode
        self.keys = keys
        self.allowsClear = allowsClear
        self.onCommit = onCommit
        self.onClear = onClear
        _capture = State(initialValue: ShortcutCapture(mode: mode))
    }

    var body: some View {
        let _ = model.shortcutCaptureID
        let recording = recordingID != nil
        HStack(spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 4) {
                    if recording {
                        if preview.isEmpty {
                            Text(t("Press shortcut", "Kurzbefehl drücken"))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        } else {
                            KeyCaps(keys: preview)
                            OpenKeySlot()
                        }
                    } else if keys.isEmpty {
                        Text(t("Record", "Festlegen"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    } else {
                        KeyCaps(keys: keys)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 8)
                .padding(.trailing, 8)
                .frame(minWidth: 132, minHeight: 24, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if allowsClear, !recording, !keys.isEmpty {
                Button(action: onClear) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)
                .accessibilityLabel(t("Clear shortcut", "Kurzbefehl löschen"))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(recording ? 0.08 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(recording ? Color.accentColor : Color.primary.opacity(0.16), lineWidth: recording ? 1.5 : 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(t("Shortcut", "Kurzbefehl"))
        .accessibilityValue(recording ? (preview.isEmpty ? t("Waiting", "Wartet") : preview.joined(separator: " ")) : keys.joined(separator: " "))
        .accessibilityHint(t(
            "Click, then press the new shortcut. Escape cancels.",
            "Klicken, dann den neuen Kurzbefehl drücken. Escape bricht ab."
        ))
        .background(RecorderMonitor(isActive: recording, onEvent: handle))
        .onChange(of: model.shortcutCaptureID) { _, id in
            guard let recordingID, recordingID != id else { return }
            self.recordingID = nil
            preview = []
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func toggle() {
        if recordingID != nil {
            stopRecording()
        } else {
            capture = ShortcutCapture(mode: mode)
            preview = []
            recordingID = model.beginShortcutCapture()
        }
    }

    private func stopRecording() {
        guard let id = recordingID else { return }
        recordingID = nil
        preview = []
        model.endShortcutCapture(id)
    }

    private func handle(_ event: NSEvent, inside: Bool) -> Bool {
        guard recordingID != nil else { return false }
        switch event.type {
        case .leftMouseDown, .rightMouseDown:
            if !inside { stopRecording() }
            return false
        case .flagsChanged:
            apply(capture.handle(.flagsChanged(keyCode: Int(event.keyCode), flags: Self.flags(of: event))))
            return false
        case .keyDown:
            if event.isARepeat { return true }
            let flags = Self.flags(of: event)
            let result = capture.handle(.keyDown(keyCode: Int(event.keyCode), flags: flags))
            let passTab = event.keyCode == UInt16(kVK_Tab) && result == .cancel
            apply(result)
            return !passTab
        default:
            return false
        }
    }

    private func apply(_ result: ShortcutCaptureResult?) {
        switch result {
        case .preview(let next):
            preview = ShortcutSymbols.keycaps(next)
        case .commit(let key):
            onCommit(key)
            stopRecording()
        case .clear:
            onClear()
            stopRecording()
        case .cancel:
            stopRecording()
        case .reject:
            NSSound.beep()
        case nil:
            break
        }
    }

    private static func flags(of event: NSEvent) -> UInt64 {
        if let cg = event.cgEvent {
            return cg.flags.rawValue
        }
        return UInt64(event.modifierFlags.rawValue)
    }
}

/// Dashed slot after the plus, so it is obvious the chord is still open.
private struct OpenKeySlot: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .strokeBorder(Color.secondary.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            .frame(width: 20, height: 20)
            .accessibilityHidden(true)
    }
}

private struct RecorderMonitor: NSViewRepresentable {
    var isActive: Bool
    var onEvent: (NSEvent, Bool) -> Bool

    func makeNSView(context: Context) -> RecorderMonitorView {
        let view = RecorderMonitorView()
        view.isActive = isActive
        view.onEvent = onEvent
        return view
    }

    func updateNSView(_ nsView: RecorderMonitorView, context: Context) {
        nsView.isActive = isActive
        nsView.onEvent = onEvent
        nsView.syncMonitor()
    }
}

private final class RecorderMonitorView: NSView {
    var isActive = false
    var onEvent: ((NSEvent, Bool) -> Bool)?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncMonitor()
    }

    func syncMonitor() {
        if let monitor, !isActive || window == nil {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        guard isActive, window != nil, monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            nonisolated(unsafe) let event = event
            let handled = MainActor.assumeIsolated {
                guard let self, self.isActive else { return false }
                let inside = event.window === self.window
                    && self.bounds.contains(self.convert(event.locationInWindow, from: nil))
                return self.onEvent?(event, inside) ?? false
            }
            return handled ? nil : event
        }
    }
}

struct GlobalShortcutRecorder: View {
    @Environment(AppModel.self) private var model
    var name: KeyboardShortcuts.Name

    var body: some View {
        let _ = model.shortcutRevision
        let shortcut = KeyboardShortcuts.getShortcut(for: name)
        let keys = shortcut.map {
            ShortcutSymbols.keycaps(keyCode: $0.carbonKeyCode, carbonModifiers: $0.carbonModifiers, function: false)
        } ?? []
        ShortcutRecorder(
            mode: .global,
            keys: keys,
            allowsClear: true,
            onCommit: { key in
                guard case .chord(let keyCode, let carbonModifiers, _) = key else { return }
                KeyboardShortcuts.setShortcut(
                    .init(carbonKeyCode: keyCode, carbonModifiers: carbonModifiers),
                    for: name
                )
                model.refreshShortcutConflicts()
            },
            onClear: {
                KeyboardShortcuts.setShortcut(nil, for: name)
                model.refreshShortcutConflicts()
            }
        )
    }
}
