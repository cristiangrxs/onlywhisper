import Carbon.HIToolbox
import XCTest
@testable import OnlyWhisper

final class ShortcutStatusTests: XCTestCase {
    func testAvailableRegistrationIsNotAConflict() {
        XCTAssertEqual(HotkeyRegistration.interpret(noErr), .available)
        XCTAssertFalse(HotkeyRegistration.available.isConflict)
    }

    func testExistingHotkeyIsAConflict() {
        let taken = HotkeyRegistration.interpret(OSStatus(eventHotKeyExistsErr))
        XCTAssertEqual(taken, .taken)
        XCTAssertTrue(taken.isConflict)
    }

    func testOtherRegistrationErrorsAreConflicts() {
        let status = OSStatus(Int32(paramErr))
        let failed = HotkeyRegistration.interpret(status)
        XCTAssertEqual(failed, .failed(status))
        XCTAssertTrue(failed.isConflict)
    }

    func testRewriteRequiresAccessibilityBeforeSelection() {
        XCTAssertEqual(
            RewriteGate.evaluate(accessibilityGranted: false, selectedText: "Hello"),
            .needsAccessibility
        )
    }

    func testRewriteWithoutSelectionShowsHint() {
        XCTAssertEqual(
            RewriteGate.evaluate(accessibilityGranted: true, selectedText: nil),
            .needsSelection
        )
        XCTAssertEqual(
            RewriteGate.evaluate(accessibilityGranted: true, selectedText: ""),
            .needsSelection
        )
        XCTAssertEqual(
            RewriteGate.needsSelectionMessage,
            t("Select text first", "Erst Text markieren")
        )
    }

    func testRewriteProceedsWhenTextIsSelected() {
        XCTAssertEqual(
            RewriteGate.evaluate(accessibilityGranted: true, selectedText: "Hello"),
            .ready("Hello")
        )
    }
}
