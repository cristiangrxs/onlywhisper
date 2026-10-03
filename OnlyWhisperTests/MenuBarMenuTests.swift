import SwiftUI
import XCTest
@testable import OnlyWhisper

@MainActor
final class MenuBarMenuTests: XCTestCase {
    func testIdleMenuHasSectionsSeparatorsAndNoTranscripts() {
        let rows = MenuBarMenuModel.rows(for: .idle)
        let items = items(in: rows)

        XCTAssertEqual(items.filter { $0.id == "history" }.count, 1)
        XCTAssertFalse(items.contains { $0.id.hasPrefix("history.") })
        XCTAssertEqual(headers(in: rows), [t("Dictation", "Diktat"), t("Transcribe", "Transkribieren")])
        XCTAssertEqual(rows.filter { if case .separator = $0 { true } else { false } }.count, 3)
        XCTAssertFalse(items.contains { $0.id == "finish" || $0.id == "cancel" })
        XCTAssertEqual(items.first { $0.id == "dictate" }?.enabled, true)
    }

    func testGroupsUseASingleSeparator() {
        let rows = MenuBarMenuModel.rows(for: .idle)
        let symbols = rows.map { row -> String in
            switch row {
            case .header(let title): "H:\(title)"
            case .item(let item): item.id
            case .separator: "—"
            }
        }
        XCTAssertEqual(symbols, [
            "H:\(t("Dictation", "Diktat"))",
            "dictate",
            "rewrite",
            "—",
            "H:\(t("Transcribe", "Transkribieren"))",
            "meeting",
            "files",
            "—",
            "history",
            "palette",
            "settings",
            "launchAtLogin",
            "updates",
            "—",
            "quit",
        ])
    }

    func testQuitIsLastWithASeparatorBeforeIt() {
        let rows = MenuBarMenuModel.rows(for: .idle)
        guard case .item(let quit) = rows.last else {
            return XCTFail("Expected a quit item")
        }
        XCTAssertEqual(quit.id, "quit")
        XCTAssertEqual(quit.shortcut, MenuBarMenuModel.quitShortcut)
        guard case .separator = rows.dropLast().last else {
            return XCTFail("Expected a separator before quit")
        }
    }

    func testRecordingDisablesStartAndOffersFinish() {
        for phase in [CapturePhase.recording, .handsFree] {
            var snapshot = MenuBarSnapshot.idle
            snapshot.phase = phase
            let items = items(in: MenuBarMenuModel.rows(for: snapshot))
            XCTAssertEqual(items.first { $0.id == "dictate" }?.enabled, false, "\(phase)")
            XCTAssertEqual(items.first { $0.id == "rewrite" }?.enabled, false, "\(phase)")
            XCTAssertTrue(items.contains { $0.id == "finish" }, "\(phase)")
            XCTAssertTrue(items.contains { $0.id == "cancel" }, "\(phase)")
        }
    }

    func testWorkingShowsStatusWithoutFinish() {
        var snapshot = MenuBarSnapshot.idle
        snapshot.phase = .working(t("Transcribing…", "Wird erkannt…"))
        let items = items(in: MenuBarMenuModel.rows(for: snapshot))
        XCTAssertFalse(items.contains { $0.id == "finish" || $0.id == "cancel" })
        XCTAssertEqual(items.first { $0.id == "working" }?.enabled, false)
        XCTAssertEqual(items.first { $0.id == "dictate" }?.enabled, false)
    }

    func testMeetingAndSetupStayOutOfTheTranscriptList() {
        var recording = MenuBarSnapshot.idle
        recording.meetingActive = true
        recording.meetingPaused = true
        recording.needsSetup = true
        let items = items(in: MenuBarMenuModel.rows(for: recording))
        XCTAssertEqual(items.first { $0.id == "meeting.status" }?.title, t("Meeting is paused", "Meeting pausiert"))
        XCTAssertTrue(items.contains { $0.id == "meeting.show" })
        XCTAssertTrue(items.contains { $0.id == "meeting.stop" })
        XCTAssertTrue(items.contains { $0.id == "setup" })
        XCTAssertFalse(items.contains { $0.id == "meeting.detected" })
        XCTAssertEqual(items.filter { $0.id == "history" }.count, 1)
    }

    func testDetectedCallIsASingleStatusItem() {
        var snapshot = MenuBarSnapshot.idle
        snapshot.detectedMeetingName = "Zoom"
        let items = items(in: MenuBarMenuModel.rows(for: snapshot))
        XCTAssertEqual(items.first { $0.id == "meeting.detected" }?.title, t("Zoom call", "Zoom-Anruf"))
        XCTAssertFalse(items.contains { $0.id == "meeting.show" })
    }

    func testDictationShortcutUsesTheSettingsKey() {
        var modifier = MenuBarSnapshot.idle
        modifier.dictationKey = .leftOption
        let modifierItem = items(in: MenuBarMenuModel.rows(for: modifier)).first { $0.id == "dictate" }
        XCTAssertEqual(modifierItem?.shortcut, MenuKey(KeyEquivalent("⌥"), modifiers: []))
        modifier.dictationKey = .rightOption
        let rightItem = items(in: MenuBarMenuModel.rows(for: modifier)).first { $0.id == "dictate" }
        XCTAssertEqual(rightItem?.shortcut, modifierItem?.shortcut)

        var chord = MenuBarSnapshot.idle
        chord.dictationKey = .chord(keyCode: 14, carbonModifiers: 256, function: false)
        let chordItem = items(in: MenuBarMenuModel.rows(for: chord)).first { $0.id == "dictate" }
        XCTAssertEqual(chordItem?.shortcut, MenuKey(KeyEquivalent("e"), modifiers: .command))

        var heldFunction = MenuBarSnapshot.idle
        heldFunction.dictationKey = .chord(keyCode: 14, carbonModifiers: 256, function: true)
        XCTAssertNil(items(in: MenuBarMenuModel.rows(for: heldFunction)).first { $0.id == "dictate" }?.shortcut)
    }

    func testLaunchAtLoginAndUpdatesFollowTheSnapshot() {
        var snapshot = MenuBarSnapshot.idle
        snapshot.launchAtLogin = true
        snapshot.canCheckForUpdates = false
        snapshot.rewriteShortcut = MenuKey(KeyEquivalent("e"), modifiers: [.command, .shift])
        let items = items(in: MenuBarMenuModel.rows(for: snapshot))
        XCTAssertEqual(items.first { $0.id == "launchAtLogin" }?.kind, .toggle(isOn: true))
        XCTAssertEqual(items.first { $0.id == "updates" }?.enabled, false)
        XCTAssertEqual(items.first { $0.id == "rewrite" }?.shortcut, snapshot.rewriteShortcut)
        XCTAssertEqual(items.first { $0.id == "settings" }?.shortcut, MenuBarMenuModel.settingsShortcut)
    }

    private func items(in rows: [MenuBarRow]) -> [MenuBarItem] {
        rows.compactMap { row in
            if case .item(let item) = row { item } else { nil }
        }
    }

    private func headers(in rows: [MenuBarRow]) -> [String] {
        rows.compactMap { row in
            if case .header(let title) = row { title } else { nil }
        }
    }
}
