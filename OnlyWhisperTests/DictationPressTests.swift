import Carbon.HIToolbox
import CoreGraphics
import IOKit.hidsystem
import XCTest
@testable import OnlyWhisper

final class DictationPressTests: XCTestCase {
    private let right = Int64(kVK_RightOption)
    private let left = Int64(kVK_Option)
    private let rightBit = UInt64(NX_DEVICERALTKEYMASK)
    private let leftBit = UInt64(NX_DEVICELALTKEYMASK)
    private let alternate = CGEventFlags.maskAlternate.rawValue

    func testRightOptionPressAndReleaseWithKeyCodeZero() {
        var press = DictationPress(binding: .rightOption)
        XCTAssertEqual(press.handle(flags: rightBit, eventKeyCode: 0), .pressed)
        XCTAssertTrue(press.isDown)
        XCTAssertEqual(press.handle(flags: 0, eventKeyCode: 0), .released)
        XCTAssertFalse(press.isDown)
    }

    func testLeftOptionDoesNotTriggerRight() {
        var press = DictationPress(binding: .rightOption)
        XCTAssertNil(press.handle(flags: leftBit | alternate, eventKeyCode: left))
        XCTAssertFalse(press.isDown)
    }

    func testRightOptionDoesNotTriggerLeft() {
        var press = DictationPress(binding: .leftOption)
        XCTAssertNil(press.handle(flags: rightBit | alternate, eventKeyCode: right))
        XCTAssertFalse(press.isDown)
        XCTAssertEqual(press.handle(flags: leftBit, eventKeyCode: 0), .pressed)
    }

    func testFallbackWithoutDeviceBits() {
        var press = DictationPress(binding: .rightOption)
        XCTAssertNil(press.handle(flags: alternate, eventKeyCode: left))
        XCTAssertEqual(press.handle(flags: alternate, eventKeyCode: right), .pressed)
        XCTAssertEqual(press.handle(flags: 0, eventKeyCode: right), .released)
    }

    func testMissedKeyUpIsCorrectedOnNextFlagsEvent() {
        var press = DictationPress(binding: .rightOption)
        XCTAssertEqual(press.handle(flags: rightBit, eventKeyCode: 0), .pressed)
        let shift = UInt64(NX_DEVICELSHIFTKEYMASK)
        XCTAssertEqual(press.handle(flags: shift, eventKeyCode: Int64(kVK_Shift)), .released)
        XCTAssertFalse(press.isDown)
    }

    func testHoldingBothSidesTracksRightUntilItIsReleased() {
        var press = DictationPress(binding: .rightOption)
        XCTAssertEqual(press.handle(flags: rightBit | leftBit, eventKeyCode: 0), .pressed)
        XCTAssertNil(press.handle(flags: rightBit | leftBit, eventKeyCode: 0))
        XCTAssertEqual(press.handle(flags: leftBit, eventKeyCode: 0), .released)
    }

    func testReconcileEndsAMissedHoldWithoutStartingANewOne() {
        var press = DictationPress(binding: .rightOption)
        XCTAssertEqual(press.handle(flags: rightBit, eventKeyCode: 0), .pressed)
        XCTAssertEqual(press.reconcile(flags: 0), .released)
        XCTAssertNil(press.reconcile(flags: rightBit))
        XCTAssertFalse(press.isDown)
    }

    func testOptionFChordPressesOnlyWhileTheChordIsComplete() {
        var press = DictationPress(binding: .chord(keyCode: Int(kVK_ANSI_F), carbonModifiers: Int(optionKey), function: false))
        let option = rightBit | alternate
        XCTAssertNil(press.handle(event: .keyDown, flags: 0, eventKeyCode: Int64(kVK_ANSI_F)).change)
        XCTAssertFalse(press.handle(event: .keyDown, flags: 0, eventKeyCode: Int64(kVK_ANSI_F)).swallow)

        let down = press.handle(event: .keyDown, flags: option, eventKeyCode: Int64(kVK_ANSI_F))
        XCTAssertEqual(down.change, .pressed)
        XCTAssertTrue(down.swallow)
        XCTAssertTrue(press.isDown)

        let extra = press.handle(event: .keyDown, flags: option | UInt64(NX_DEVICELSHIFTKEYMASK) | CGEventFlags.maskShift.rawValue, eventKeyCode: Int64(kVK_ANSI_F))
        XCTAssertNil(extra.change)
        XCTAssertFalse(extra.swallow)

        let up = press.handle(event: .keyUp, flags: option, eventKeyCode: Int64(kVK_ANSI_F))
        XCTAssertEqual(up.change, .released)
        XCTAssertTrue(up.swallow)
        XCTAssertFalse(press.isDown)
    }

    func testChordKeyUpIsStillSwallowedAfterTheModifierIsReleased() {
        var press = DictationPress(binding: .chord(keyCode: Int(kVK_ANSI_F), carbonModifiers: Int(optionKey), function: false))
        let option = rightBit | alternate
        _ = press.handle(event: .keyDown, flags: option, eventKeyCode: Int64(kVK_ANSI_F))
        XCTAssertEqual(press.handle(event: .flagsChanged, flags: 0, eventKeyCode: right).change, .released)
        let up = press.handle(event: .keyUp, flags: 0, eventKeyCode: Int64(kVK_ANSI_F))
        XCTAssertNil(up.change)
        XCTAssertTrue(up.swallow)
    }
}
