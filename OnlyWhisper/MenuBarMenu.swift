import AppKit
@preconcurrency import KeyboardShortcuts
import SwiftUI

/// A menu shortcut shown on the right of a status item. It is not a second global hotkey.
struct MenuKey: Equatable {
    var key: KeyEquivalent
    var modifiers: EventModifiers

    init(_ key: KeyEquivalent, modifiers: EventModifiers) {
        self.key = key
        self.modifiers = modifiers
    }

    /// Left and right modifiers share one menu glyph. A chord uses the same column as the other commands.
    init?(dictation key: DictationKey) {
        switch key {
        case .modifier(let side):
            guard let symbol = Self.modifierSymbol(side) else { return nil }
            self.init(KeyEquivalent(symbol), modifiers: [])
        case .chord(let keyCode, let carbonModifiers, false):
            self.init(shortcut: KeyboardShortcuts.Shortcut(carbonKeyCode: keyCode, carbonModifiers: carbonModifiers))
        case .chord:
            return nil
        }
    }

    private static func modifierSymbol(_ side: DictationKey.SideModifier) -> Character? {
        switch side {
        case .leftOption, .rightOption, .option: "⌥"
        case .leftControl, .rightControl, .control: "⌃"
        case .leftShift, .rightShift, .shift: "⇧"
        case .leftCommand, .rightCommand, .command: "⌘"
        case .function: nil
        }
    }

    init?(shortcut: KeyboardShortcuts.Shortcut) {
        guard let key = shortcut.key, let equivalent = Self.equivalent(for: key) else { return nil }
        self.key = equivalent
        var modifiers = EventModifiers()
        if shortcut.modifiers.contains(.command) { modifiers.insert(.command) }
        if shortcut.modifiers.contains(.shift) { modifiers.insert(.shift) }
        if shortcut.modifiers.contains(.option) { modifiers.insert(.option) }
        if shortcut.modifiers.contains(.control) { modifiers.insert(.control) }
        self.modifiers = modifiers
    }

    private static func equivalent(for key: KeyboardShortcuts.Key) -> KeyEquivalent? {
        if let character = character(for: key) {
            return KeyEquivalent(character)
        }
        switch key {
        case .space: return .space
        case .tab: return .tab
        case .return: return .return
        case .escape: return .escape
        case .delete: return .delete
        case .deleteForward: return .deleteForward
        case .upArrow: return .upArrow
        case .downArrow: return .downArrow
        case .leftArrow: return .leftArrow
        case .rightArrow: return .rightArrow
        case .home: return .home
        case .end: return .end
        case .pageUp: return .pageUp
        case .pageDown: return .pageDown
        default: return nil
        }
    }

    private static func character(for key: KeyboardShortcuts.Key) -> Character? {
        switch key {
        case .a: "a"
        case .b: "b"
        case .c: "c"
        case .d: "d"
        case .e: "e"
        case .f: "f"
        case .g: "g"
        case .h: "h"
        case .i: "i"
        case .j: "j"
        case .k: "k"
        case .l: "l"
        case .m: "m"
        case .n: "n"
        case .o: "o"
        case .p: "p"
        case .q: "q"
        case .r: "r"
        case .s: "s"
        case .t: "t"
        case .u: "u"
        case .v: "v"
        case .w: "w"
        case .x: "x"
        case .y: "y"
        case .z: "z"
        case .zero: "0"
        case .one: "1"
        case .two: "2"
        case .three: "3"
        case .four: "4"
        case .five: "5"
        case .six: "6"
        case .seven: "7"
        case .eight: "8"
        case .nine: "9"
        case .comma: ","
        case .period: "."
        case .slash: "/"
        case .backslash: "\\"
        case .minus: "-"
        case .equal: "="
        case .quote: "'"
        case .semicolon: ";"
        case .backtick: "`"
        case .leftBracket: "["
        case .rightBracket: "]"
        default: nil
        }
    }
}

struct MenuBarSnapshot: Equatable {
    var phase: CapturePhase = .idle
    var meetingActive = false
    var meetingPaused = false
    var detectedMeetingName: String?
    var needsSetup = false
    var launchAtLogin = false
    var canCheckForUpdates = true
    var dictationKey: DictationKey = .rightOption
    var rewriteShortcut: MenuKey?
    var paletteShortcut: MenuKey?

    static let idle = MenuBarSnapshot()
}

struct MenuBarItem: Equatable, Identifiable {
    enum Kind: Equatable {
        case action
        case toggle(isOn: Bool)
    }

    var id: String
    var title: String
    var enabled: Bool = true
    var shortcut: MenuKey?
    var kind: Kind = .action
}

enum MenuBarRow: Equatable {
    case header(String)
    case item(MenuBarItem)
    case separator
}

struct MenuBarBlock: Identifiable, Equatable {
    var id: Int
    var header: String?
    var items: [MenuBarItem]
    var showsSeparatorAfter: Bool
}

enum MenuBarMenuModel {
    static let settingsShortcut = MenuKey(KeyEquivalent(","), modifiers: .command)
    static let quitShortcut = MenuKey(KeyEquivalent("q"), modifiers: .command)

    static func rows(for snapshot: MenuBarSnapshot) -> [MenuBarRow] {
        var rows: [MenuBarRow] = []
        let status = statusItems(snapshot)
        if !status.isEmpty {
            rows.append(contentsOf: status.map { .item($0) })
            rows.append(.separator)
        }

        rows.append(.header(t("Dictation", "Diktat")))
        rows.append(.item(MenuBarItem(
            id: "dictate",
            title: t("Start dictation", "Diktat starten"),
            enabled: snapshot.phase == .idle,
            shortcut: MenuKey(dictation: snapshot.dictationKey)
        )))
        rows.append(.item(MenuBarItem(
            id: "rewrite",
            title: t("Rewrite selection", "Markierung umschreiben"),
            enabled: snapshot.phase == .idle,
            shortcut: snapshot.rewriteShortcut
        )))
        rows.append(.separator)

        rows.append(.header(t("Transcribe", "Transkribieren")))
        rows.append(.item(MenuBarItem(id: "meeting", title: t("Meeting", "Meeting"))))
        rows.append(.item(MenuBarItem(id: "files", title: t("Transcribe files", "Dateien transkribieren"))))
        rows.append(.separator)

        rows.append(.item(MenuBarItem(id: "history", title: t("History", "Verlauf"))))
        rows.append(.item(MenuBarItem(
            id: "palette",
            title: t("Search commands", "Befehle suchen"),
            shortcut: snapshot.paletteShortcut
        )))
        rows.append(.item(MenuBarItem(
            id: "settings",
            title: t("Settings", "Einstellungen"),
            shortcut: settingsShortcut
        )))
        rows.append(.item(MenuBarItem(
            id: "launchAtLogin",
            title: t("Launch at login", "Beim Anmelden starten"),
            kind: .toggle(isOn: snapshot.launchAtLogin)
        )))
        rows.append(.item(MenuBarItem(
            id: "updates",
            title: t("Check for updates", "Nach Updates suchen"),
            enabled: snapshot.canCheckForUpdates
        )))
        rows.append(.separator)
        rows.append(.item(MenuBarItem(
            id: "quit",
            title: t("Quit OnlyWhisper", "OnlyWhisper beenden"),
            shortcut: quitShortcut
        )))
        return rows
    }

    static func blocks(from rows: [MenuBarRow]) -> [MenuBarBlock] {
        var blocks: [MenuBarBlock] = []
        var header: String?
        var items: [MenuBarItem] = []

        func flush(separator: Bool) {
            guard header != nil || !items.isEmpty else { return }
            blocks.append(MenuBarBlock(
                id: blocks.count,
                header: header,
                items: items,
                showsSeparatorAfter: separator
            ))
            header = nil
            items = []
        }

        for row in rows {
            switch row {
            case .header(let title):
                if header != nil || !items.isEmpty {
                    flush(separator: false)
                }
                header = title
            case .item(let item):
                items.append(item)
            case .separator:
                flush(separator: true)
            }
        }
        flush(separator: false)
        return blocks
    }

    private static func statusItems(_ snapshot: MenuBarSnapshot) -> [MenuBarItem] {
        var items: [MenuBarItem] = []
        switch snapshot.phase {
        case .recording, .handsFree:
            items.append(MenuBarItem(id: "finish", title: t("Finish dictation", "Diktat beenden")))
            items.append(MenuBarItem(id: "cancel", title: t("Cancel dictation", "Diktat abbrechen")))
        case .working(let text):
            items.append(MenuBarItem(id: "working", title: text, enabled: false))
        case .idle:
            break
        }

        if snapshot.meetingActive {
            items.append(MenuBarItem(
                id: "meeting.status",
                title: snapshot.meetingPaused
                    ? t("Meeting is paused", "Meeting pausiert")
                    : t("Meeting is recording", "Meeting läuft"),
                enabled: false
            ))
            items.append(MenuBarItem(id: "meeting.show", title: t("Show Meeting", "Meeting zeigen")))
            items.append(MenuBarItem(id: "meeting.stop", title: t("Stop Meeting", "Meeting beenden")))
        } else if let name = snapshot.detectedMeetingName {
            items.append(MenuBarItem(
                id: "meeting.detected",
                title: t("\(name) call", "\(name)-Anruf")
            ))
        }

        if snapshot.needsSetup {
            items.append(MenuBarItem(id: "setup", title: t("Finish setup", "Einrichtung abschließen")))
        }
        return items
    }
}

struct MenuBarMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let blocks = MenuBarMenuModel.blocks(from: MenuBarMenuModel.rows(for: snapshot))
        ForEach(blocks) { block in
            if let header = block.header {
                Text(header)
            }
            items(block.items)
            if block.showsSeparatorAfter {
                Divider()
            }
        }
    }

    private var snapshot: MenuBarSnapshot {
        let _ = model.shortcutRevision
        return MenuBarSnapshot(
            phase: model.phase,
            meetingActive: model.meetingActive,
            meetingPaused: model.meetingPaused,
            detectedMeetingName: model.detectedMeeting?.kind.localizedName,
            needsSetup: model.needsSetup,
            launchAtLogin: model.settings.launchAtLogin,
            canCheckForUpdates: Updater.shared.canCheckForUpdates,
            dictationKey: model.settings.dictationKey,
            rewriteShortcut: KeyboardShortcuts.getShortcut(for: .rewriteSelection).flatMap(MenuKey.init),
            paletteShortcut: KeyboardShortcuts.getShortcut(for: .commandPalette).flatMap(MenuKey.init)
        )
    }

    @ViewBuilder
    private func items(_ items: [MenuBarItem]) -> some View {
        ForEach(items) { item in
            menuItem(item)
        }
    }

    @ViewBuilder
    private func menuItem(_ item: MenuBarItem) -> some View {
        switch item.kind {
        case .action:
            Button(item.title) { perform(item.id) }
                .disabled(!item.enabled)
                .modifier(MenuShortcutModifier(shortcut: item.shortcut))
        case .toggle:
            Toggle(item.title, isOn: launchAtLogin)
                .disabled(!item.enabled)
        }
    }

    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { model.settings.launchAtLogin },
            set: { model.setLaunchAtLogin($0) }
        )
    }

    private func perform(_ id: String) {
        switch id {
        case "finish":
            model.finishHandsFree()
        case "cancel":
            model.cancelCapture()
        case "meeting.show", "meeting", "meeting.detected":
            model.open("meeting")
        case "meeting.stop":
            Task { await model.stopMeeting() }
        case "setup":
            model.open("setup")
        case "dictate":
            model.returnFocus { model.startHandsFree() }
        case "rewrite":
            model.returnFocus { model.beginRewrite() }
        case "files":
            model.open("files")
        case "history":
            model.open("history")
        case "palette":
            Task { @MainActor in
                CommandPaletteController.shared.show()
            }
        case "settings":
            model.showSettings()
        case "updates":
            Updater.shared.checkForUpdates()
        case "quit":
            NSApp.terminate(nil)
        default:
            break
        }
    }
}

/// Pauses global shortcuts while a menu is tracking, so a shown key equivalent does not also fire when the menu closes.
@MainActor
enum MenuTrackingGate {
    private static var depth = 0
    private static var restoreEnabled = false

    static func begin() {
        if depth == 0 {
            restoreEnabled = ShortcutProbe.isEnabled
            if restoreEnabled {
                ShortcutProbe.setEnabled(false)
            }
        }
        depth += 1
    }

    static func end() {
        depth = max(0, depth - 1)
        guard depth == 0, restoreEnabled else { return }
        restoreEnabled = false
        ShortcutProbe.setEnabled(true)
    }
}

private struct MenuTrackingShortcutPause: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
                MenuTrackingGate.begin()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
                MenuTrackingGate.end()
            }
    }
}

extension View {
    func pausesGlobalShortcutsWhileMenuIsOpen() -> some View {
        modifier(MenuTrackingShortcutPause())
    }
}

private struct MenuShortcutModifier: ViewModifier {
    var shortcut: MenuKey?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let shortcut {
            content.keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
        } else {
            content
        }
    }
}
