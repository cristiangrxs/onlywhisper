import CoreGraphics
import XCTest
@testable import OnlyWhisper

final class NotchMetricsTests: XCTestCase {
    func testNotchWidthIsTheGapBetweenTheMenuBarAreas() {
        XCTAssertEqual(NotchMetrics.notchWidth(leftMaxX: 412, rightMinX: 612), 200)
        XCTAssertNil(NotchMetrics.notchWidth(leftMaxX: 100, rightMinX: 120))
        XCTAssertNil(NotchMetrics.notchWidth(leftMaxX: 200, rightMinX: 180))
    }

    func testMeasureCentersOnTheGapAndUsesTheMenuBarBand() {
        let left = CGRect(x: 0, y: 800, width: 400, height: 32)
        let right = CGRect(x: 600, y: 800, width: 400, height: 32)
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 832)
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let metrics = NotchMetrics.measure(
            left: left,
            right: right,
            screenFrame: screen,
            visibleFrame: visible,
            safeAreaTop: 0
        )
        XCTAssertEqual(metrics?.width, 200)
        XCTAssertEqual(metrics?.midX, 500)
        XCTAssertEqual(metrics?.band, 32)
    }

    func testMeasureFallsBackWhenTheReportedCenterIsOffScreen() {
        let metrics = NotchMetrics.measure(
            left: CGRect(x: 0, y: 0, width: 100, height: 24),
            right: CGRect(x: 280, y: 0, width: 100, height: 24),
            screenFrame: CGRect(x: 1920, y: 0, width: 400, height: 800),
            visibleFrame: CGRect(x: 1920, y: 0, width: 400, height: 776),
            safeAreaTop: 0
        )
        XCTAssertEqual(metrics?.width, 180)
        XCTAssertEqual(metrics?.midX, 2120)
        XCTAssertEqual(metrics?.band, 24)
    }

    func testHiddenMenuBarUsesSafeAreaThenACompactBand() {
        let left = CGRect(x: 0, y: 0, width: 100, height: 10)
        let right = CGRect(x: 280, y: 0, width: 100, height: 10)
        let screen = CGRect(x: 0, y: 0, width: 400, height: 800)
        let withSafeArea = NotchMetrics.measure(
            left: left,
            right: right,
            screenFrame: screen,
            visibleFrame: screen,
            safeAreaTop: 28
        )
        let fallback = NotchMetrics.measure(
            left: left,
            right: right,
            screenFrame: screen,
            visibleFrame: screen,
            safeAreaTop: 0
        )
        XCTAssertEqual(withSafeArea?.band, 28)
        XCTAssertEqual(fallback?.band, 32)
    }

    func testMissingAuxiliaryAreasAreNotANotch() {
        let metrics = NotchMetrics.measure(
            left: nil,
            right: nil,
            screenFrame: .zero,
            visibleFrame: .zero,
            safeAreaTop: 0
        )
        XCTAssertNil(metrics)
    }
}
