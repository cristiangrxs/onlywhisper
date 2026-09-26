import SwiftUI
import XCTest
@testable import OnlyWhisper

@MainActor
final class PaletteSearchTests: XCTestCase {
    private func command(_ id: String, _ title: String, keywords: [String] = []) -> PaletteCommand {
        PaletteCommand(id: id, section: .app, title: title, symbol: "circle", tint: .gray, keywords: keywords)
    }

    func testEmptyQueryKeepsOrder() {
        let commands = [command("a", "Settings"), command("b", "History")]
        XCTAssertEqual(PaletteSearch.filter(commands, query: "  ").map(\.id), ["a", "b"])
    }

    func testTitlePrefixRanksAboveKeywordMatch() {
        let commands = [
            command("files", "Transcribe files", keywords: ["meeting"]),
            command("meeting", "Meeting"),
        ]
        XCTAssertEqual(PaletteSearch.filter(commands, query: "mee").map(\.id), ["meeting", "files"])
    }

    func testEveryWordMustMatch() {
        let commands = [command("rewrite", "Rewrite selection"), command("dictate", "Start dictation")]
        XCTAssertEqual(PaletteSearch.filter(commands, query: "rew sel").map(\.id), ["rewrite"])
        XCTAssertTrue(PaletteSearch.filter(commands, query: "rew xyz").isEmpty)
    }

    func testIgnoresCaseAndDiacritics() {
        XCTAssertNotNil(PaletteSearch.score(title: "Übersetzen", keywords: [], query: "uber"))
        XCTAssertNotNil(PaletteSearch.score(title: "Einstellungen", keywords: [], query: "EIN"))
    }

    func testMatchesInsideWords() {
        XCTAssertNotNil(PaletteSearch.score(title: "OnlyWhisper beenden", keywords: [], query: "whisper"))
    }

    func testNoMatchReturnsNil() {
        XCTAssertNil(PaletteSearch.score(title: "History", keywords: ["verlauf"], query: "quit"))
    }
}
