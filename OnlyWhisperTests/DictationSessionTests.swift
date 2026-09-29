import XCTest
@testable import OnlyWhisper

final class DictationSessionTests: XCTestCase {
    func testOpenTextGrowsWhileSpeaking() {
        var session = DictationSession()
        XCTAssertTrue(session.updateOpen("um so"))
        XCTAssertTrue(session.updateOpen("um so yeah let's meet"))
        XCTAssertEqual(session.text, "um so yeah let's meet")
        XCTAssertEqual(session.settled, "")
    }

    func testOpenEndingCorrectsItself() {
        var session = DictationSession()
        session.updateOpen("let's meet on tues")
        XCTAssertTrue(session.updateOpen("let's meet on Tuesday"))
        XCTAssertEqual(session.text, "let's meet on Tuesday")
    }

    func testUnchangedUpdateReportsNoChange() {
        var session = DictationSession()
        session.updateOpen("Hallo Welt")
        XCTAssertFalse(session.updateOpen(" Hallo Welt "))
    }

    func testSettlingKeepsTheTextAndStartsANewSegment() {
        var session = DictationSession()
        session.updateOpen("um so yeah")
        session.settleOpen()
        XCTAssertEqual(session.settled, "um so yeah")
        XCTAssertEqual(session.open, "")
        session.updateOpen("let's meet")
        XCTAssertEqual(session.text, "um so yeah let's meet")
    }

    func testSettlingAnEmptySegmentAddsNothing() {
        var session = DictationSession()
        session.updateOpen("Hallo")
        session.settleOpen()
        session.settleOpen()
        XCTAssertEqual(session.text, "Hallo")
    }

    func testEscapeClearsTheDraft() {
        var session = DictationSession()
        session.updateOpen("Hallo")
        session.settleOpen()
        session.updateOpen("noch etwas")
        session.reset()
        XCTAssertEqual(session.text, "")
    }

    func testShortTextIsPolishedInOnePass() {
        XCTAssertEqual(DictationSession.polishChunks("Hallo. Wie geht es?", limit: 100), ["Hallo. Wie geht es?"])
        XCTAssertEqual(DictationSession.polishChunks("  ", limit: 100), [])
    }

    func testLongTextSplitsAtSentenceEnds() {
        let chunks = DictationSession.polishChunks("Erster Satz. Zweiter Satz! Dritter ohne Ende", limit: 26)
        XCTAssertEqual(chunks, ["Erster Satz. Zweiter Satz!", "Dritter ohne Ende"])
    }

    func testTrailingPauseSettlesTheWholeSegment() {
        let speech = [Float](repeating: 0.2, count: 16_000)
        let silence = [Float](repeating: 0, count: 9_600)
        let samples = speech + silence
        XCTAssertEqual(SpeechPause.settlePoint(in: samples, from: 0, to: samples.count), samples.count)
    }

    func testOngoingSpeechStaysOpen() {
        let samples = [Float](repeating: 0.2, count: 3 * 16_000)
        XCTAssertNil(SpeechPause.settlePoint(in: samples, from: 0, to: samples.count))
    }

    func testLongSegmentSettlesAtTheQuietestRecentFrame() {
        var samples = [Float](repeating: 0.2, count: 9 * 16_000)
        let gap = 7 * 16_000
        for index in gap..<(gap + 1_600) {
            samples[index] = 0.01
        }
        XCTAssertEqual(SpeechPause.settlePoint(in: samples, from: 0, to: samples.count), gap + 800)
    }
}
