import Carbon.HIToolbox
import CoreGraphics
import IOKit.hidsystem
import XCTest
@testable import OnlyWhisper

final class ShortcutCaptureTests: XCTestCase {
    private var rightOption: UInt64 {
        UInt64(NX_DEVICERALTKEYMASK) | CGEventFlags.maskAlternate.rawValue
    }

    private var leftShift: UInt64 {
        UInt64(NX_DEVICELSHIFTKEYMASK) | CGEventFlags.maskShift.rawValue
    }

    func testOptionThenShiftShowsAnOpenPlusUntilTheKey() {
        var capture = ShortcutCapture(mode: .global)
        let option = capture.handle(.flagsChanged(keyCode: Int(kVK_RightOption), flags: rightOption))
        XCTAssertEqual(option, .preview(ShortcutPreview(tokens: [.option(.right)], showsPlus: true)))
        XCTAssertEqual(ShortcutSymbols.keycaps(ShortcutPreview(tokens: [.option(.right)], showsPlus: true)), [t("Right ⌥", "Rechts ⌥"), "+"])

        let both = capture.handle(.flagsChanged(keyCode: Int(kVK_Shift), flags: rightOption | leftShift))
        guard case .preview(let preview) = both else {
            return XCTFail("Expected a preview")
        }
        XCTAssertEqual(ShortcutSymbols.keycaps(preview), ["⌥", "⇧", "+"])

        let committed = capture.handle(.keyDown(keyCode: Int(kVK_ANSI_O), flags: rightOption | leftShift))
        XCTAssertEqual(committed, .commit(.chord(
            keyCode: Int(kVK_ANSI_O),
            carbonModifiers: Int(optionKey) | Int(shiftKey),
            function: false
        )))
    }

    func testOptionFUsesTheKeyCode() {
        var capture = ShortcutCapture(mode: .global)
        _ = capture.handle(.flagsChanged(keyCode: Int(kVK_RightOption), flags: rightOption))
        let committed = capture.handle(.keyDown(keyCode: Int(kVK_ANSI_F), flags: rightOption))
        XCTAssertEqual(committed, .commit(.chord(
            keyCode: Int(kVK_ANSI_F),
            carbonModifiers: Int(optionKey),
            function: false
        )))
        XCTAssertEqual(
            ShortcutSymbols.keycaps(keyCode: Int(kVK_ANSI_F), carbonModifiers: Int(optionKey), function: false),
            ["⌥", "F"]
        )
    }

    func testEscapeCancelsAndShiftAloneIsRejected() {
        var capture = ShortcutCapture(mode: .global)
        XCTAssertEqual(capture.handle(.keyDown(keyCode: Int(kVK_Escape), flags: 0)), .cancel)
        XCTAssertEqual(capture.handle(.keyDown(keyCode: Int(kVK_Escape), flags: rightOption)), .cancel)
        _ = capture.handle(.flagsChanged(keyCode: Int(kVK_Shift), flags: leftShift))
        XCTAssertEqual(capture.handle(.keyDown(keyCode: Int(kVK_ANSI_F), flags: leftShift)), .reject)
    }

    func testBackspaceClearsAGlobalShortcutOnly() {
        var global = ShortcutCapture(mode: .global)
        XCTAssertEqual(global.handle(.keyDown(keyCode: Int(kVK_Delete), flags: 0)), .clear)
        var dictation = ShortcutCapture(mode: .dictation)
        XCTAssertEqual(dictation.handle(.keyDown(keyCode: Int(kVK_Delete), flags: 0)), .reject)
    }

    func testDictationCommitsASingleModifierOnRelease() {
        var capture = ShortcutCapture(mode: .dictation)
        _ = capture.handle(.flagsChanged(keyCode: Int(kVK_RightOption), flags: rightOption))
        XCTAssertEqual(
            capture.handle(.flagsChanged(keyCode: Int(kVK_RightOption), flags: 0)),
            .commit(.modifier(.rightOption))
        )
    }

    func testDictationDoesNotCommitWhenSeveralModifiersAreReleased() {
        var capture = ShortcutCapture(mode: .dictation)
        _ = capture.handle(.flagsChanged(keyCode: Int(kVK_RightOption), flags: rightOption | leftShift))
        XCTAssertEqual(
            capture.handle(.flagsChanged(keyCode: 0, flags: 0)),
            .preview(.empty)
        )
    }

    func testDictationRejectsABareLetterAndAcceptsOptionF() {
        var capture = ShortcutCapture(mode: .dictation)
        XCTAssertEqual(capture.handle(.keyDown(keyCode: Int(kVK_ANSI_A), flags: 0)), .reject)
        let committed = capture.handle(.keyDown(keyCode: Int(kVK_ANSI_F), flags: rightOption))
        XCTAssertEqual(committed, .commit(.chord(
            keyCode: Int(kVK_ANSI_F),
            carbonModifiers: Int(optionKey),
            function: false
        )))
    }

    func testLegacyDictationKeyDecodesAndAChordRoundTrips() throws {
        let right = try JSONDecoder().decode(DictationKey.self, from: Data(#""rightOption""#.utf8))
        let left = try JSONDecoder().decode(DictationKey.self, from: Data(#""leftOption""#.utf8))
        XCTAssertEqual(right, .rightOption)
        XCTAssertEqual(left, .leftOption)

        let chord = DictationKey.chord(keyCode: Int(kVK_ANSI_F), carbonModifiers: Int(optionKey), function: false)
        let data = try JSONEncoder().encode(chord)
        XCTAssertEqual(try JSONDecoder().decode(DictationKey.self, from: data), chord)
    }
}
