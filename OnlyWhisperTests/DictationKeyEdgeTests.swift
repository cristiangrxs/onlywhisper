import CoreGraphics
import IOKit.hidsystem
import XCTest
@testable import OnlyWhisper

final class DictationKeyEdgeTests: XCTestCase {
    private let right = DictationKey.rightOption.keyCode
    private let left = DictationKey.leftOption.keyCode
    private let rightBit = UInt64(NX_DEVICERALTKEYMASK)
    private let leftBit = UInt64(NX_DEVICELALTKEYMASK)
    private let alternate = CGEventFlags.maskAlternate.rawValue

    func testRightOptionPressAndReleaseWithKeyCodeZero() {
        var edge = DictationKeyEdge(keyCode: right)
        XCTAssertEqual(edge.handle(flags: rightBit, eventKeyCode: 0), .pressed)
        XCTAssertTrue(edge.isDown)
        XCTAssertEqual(edge.handle(flags: 0, eventKeyCode: 0), .released)
        XCTAssertFalse(edge.isDown)
    }

    func testLeftOptionDoesNotTriggerRight() {
        var edge = DictationKeyEdge(keyCode: right)
        XCTAssertNil(edge.handle(flags: leftBit | alternate, eventKeyCode: left))
        XCTAssertFalse(edge.isDown)
    }

    func testRightOptionDoesNotTriggerLeft() {
        var edge = DictationKeyEdge(keyCode: left)
        XCTAssertNil(edge.handle(flags: rightBit | alternate, eventKeyCode: right))
        XCTAssertFalse(edge.isDown)
        XCTAssertEqual(edge.handle(flags: leftBit, eventKeyCode: 0), .pressed)
    }

    func testFallbackWithoutDeviceBits() {
        var edge = DictationKeyEdge(keyCode: right)
        XCTAssertNil(edge.handle(flags: alternate, eventKeyCode: left))
        XCTAssertEqual(edge.handle(flags: alternate, eventKeyCode: right), .pressed)
        XCTAssertEqual(edge.handle(flags: 0, eventKeyCode: right), .released)
    }

    func testMissedKeyUpIsCorrectedOnNextFlagsEvent() {
        var edge = DictationKeyEdge(keyCode: right)
        XCTAssertEqual(edge.handle(flags: rightBit, eventKeyCode: 0), .pressed)
        let shift = UInt64(NX_DEVICELSHIFTKEYMASK)
        XCTAssertEqual(edge.handle(flags: shift, eventKeyCode: 56), .released)
        XCTAssertFalse(edge.isDown)
    }

    func testHoldingBothSidesTracksRightUntilItIsReleased() {
        var edge = DictationKeyEdge(keyCode: right)
        XCTAssertEqual(edge.handle(flags: rightBit | leftBit, eventKeyCode: 0), .pressed)
        XCTAssertNil(edge.handle(flags: rightBit | leftBit, eventKeyCode: 0))
        XCTAssertEqual(edge.handle(flags: leftBit, eventKeyCode: 0), .released)
    }

    func testReconcileEndsAMissedHoldWithoutStartingANewOne() {
        var edge = DictationKeyEdge(keyCode: right)
        XCTAssertEqual(edge.handle(flags: rightBit, eventKeyCode: 0), .pressed)
        XCTAssertEqual(edge.reconcile(flags: 0), .released)
        XCTAssertNil(edge.reconcile(flags: rightBit))
        XCTAssertFalse(edge.isDown)
    }
}
