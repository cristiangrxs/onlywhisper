import XCTest
@testable import OnlyWhisper

final class DictationSessionTests: XCTestCase {
    func testPartialTextAppears() {
        var session = DictationSession()
        session.updateOpenText("Hallo Welt")
        XCTAssertEqual(session.visibleText, "Hallo Welt")
        XCTAssertEqual(session.committed, "")
    }

    func testPauseCommitsPolishedSentence() {
        var session = DictationSession()
        session.updateOpenText("äh hallo")
        let request = session.polishRequest(paused: true)
        XCTAssertEqual(request?.sentence, "äh hallo")
        XCTAssertTrue(session.acceptPolish("Hallo.", generation: request!.generation))
        XCTAssertEqual(session.visibleText, "Hallo.")
        XCTAssertEqual(session.openText, "")
    }

    func testPunctuationKeepsTheUnfinishedTail() {
        var session = DictationSession()
        session.updateOpenText("Hallo. Wie geht")
        let request = session.polishRequest(paused: false)
        XCTAssertEqual(request?.sentence, "Hallo.")
        XCTAssertTrue(session.acceptPolish("Hallo.", generation: request!.generation))
        XCTAssertEqual(session.committed, "Hallo.")
        XCTAssertEqual(session.openText, "Wie geht")
        XCTAssertEqual(session.visibleText, "Hallo. Wie geht")
    }

    func testStalePolishDoesNotOverwrite() {
        var session = DictationSession()
        session.updateOpenText("Hallo")
        let request = session.polishRequest(paused: true)
        session.updateOpenText("Hallo Welt")
        XCTAssertFalse(session.acceptPolish("Hallo.", generation: request!.generation))
        XCTAssertEqual(session.visibleText, "Hallo Welt")
        XCTAssertEqual(session.committed, "")
    }

    func testEscapeClearsTheDraft() {
        var session = DictationSession()
        session.updateOpenText("Hallo")
        _ = session.polishRequest(paused: true)
        session.acceptPolish("Hallo.", generation: session.generation)
        session.updateOpenText("noch etwas")
        session.reset()
        XCTAssertEqual(session.visibleText, "")
        XCTAssertEqual(session.committed, "")
        XCTAssertEqual(session.openText, "")
        XCTAssertNil(session.polishRequest(paused: true))
    }
}
