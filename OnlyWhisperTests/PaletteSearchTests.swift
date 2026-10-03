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

    func testEmptyQueryHidesTranscriptsUntilTheyMatch() {
        var transcript = command("history.1", "Hello world", keywords: ["meeting notes"])
        transcript.section = .transcribed
        transcript.isTranscript = true
        let commands = [command("settings", "Settings"), transcript]
        XCTAssertEqual(PaletteSearch.filter(commands, query: "").map(\.id), ["settings"])
        XCTAssertEqual(PaletteSearch.filter(commands, query: "hello").map(\.id), ["history.1"])
        XCTAssertEqual(PaletteSearch.filter(commands, query: "notes").map(\.id), ["history.1"])
        XCTAssertEqual(PaletteSearch.filter(commands, query: "set").map(\.id), ["settings"])
    }

    func testSearchKeepsCategoriesInSectionOrder() {
        var dictation = command("dictate", "Start dictation", keywords: ["notes"])
        dictation.section = .dictation
        var transcript = command("history.1", "Notes from the call")
        transcript.section = .transcribed
        transcript.isTranscript = true
        XCTAssertEqual(
            PaletteSearch.filter([transcript, dictation], query: "notes").map(\.id),
            ["dictate", "history.1"]
        )
    }

    func testTranscriptsUseSourceCategories() {
        XCTAssertEqual(PaletteSection.transcript("file"), .transcribed)
        XCTAssertEqual(PaletteSection.transcript("dictation"), .dictation)
        XCTAssertEqual(PaletteSection.transcript("meeting"), .meeting)
        XCTAssertEqual(PaletteSection.transcript("rewrite"), .rewrite)
        XCTAssertFalse(PaletteSection.allCases.contains { $0.title == "Recent" || $0.title == "Zuletzt" })
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
