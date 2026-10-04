import XCTest
@testable import OnlyWhisper

final class PolisherTests: XCTestCase {
    func testRemovesGermanFillers() {
        XCTAssertEqual(RulePolisher.apply("Ähm das Meeting ist äh morgen"), "das Meeting ist morgen")
    }

    func testAppliesSelfCorrection() {
        XCTAssertEqual(RulePolisher.apply("Freitag, nein Montag"), "Montag")
    }

    func testDictionaryReplacesWholeWords() {
        let dictionary = CustomDictionary(entries: [
            CustomDictionary.Entry(heard: "Onlywisper", written: "OnlyWhisper")
        ])
        XCTAssertEqual(dictionary.apply(to: "Onlywisper bleibt lokal"), "OnlyWhisper bleibt lokal")
    }

    func testRomanianToGermanTranslates() {
        XCTAssertEqual(
            DictationPostprocess.step(polish: false, spoken: .romanian, target: .german),
            .translate(.german, keepExisting: false)
        )
        XCTAssertEqual(
            DictationPostprocess.step(polish: true, spoken: .romanian, target: .german),
            .polishAndTranslate(.german, keepExisting: false)
        )
    }

    func testSameLanguageSkipsTranslation() {
        XCTAssertEqual(
            DictationPostprocess.step(polish: false, spoken: .german, target: .german),
            .none
        )
        XCTAssertEqual(
            DictationPostprocess.step(polish: true, spoken: .german, target: .german),
            .polish
        )
    }

    func testOffSkipsTranslation() {
        XCTAssertEqual(
            DictationPostprocess.step(polish: false, spoken: .romanian, target: nil),
            .none
        )
        XCTAssertEqual(
            DictationPostprocess.step(polish: true, spoken: .romanian, target: nil),
            .polish
        )
    }

    func testAutomaticStillTranslates() {
        XCTAssertEqual(
            DictationPostprocess.step(polish: false, spoken: .automatic, target: .german),
            .translate(.german, keepExisting: true)
        )
        XCTAssertEqual(
            DictationPostprocess.step(polish: true, spoken: .automatic, target: .german),
            .polishAndTranslate(.german, keepExisting: true)
        )
    }

    func testTranslationPromptNamesTheTargetAndDoesNotKeepTheLanguage() {
        let kind = PolishKind.dictationTranslate(target: SpeechChoice.german.promptName, polish: false, keepExisting: false)
        XCTAssertTrue(kind.system.contains("German"))
        XCTAssertTrue(kind.system.contains("Always translate"))
        XCTAssertTrue(kind.system.contains("Return only the translation"))
        XCTAssertFalse(kind.system.contains("Keep their language"))
        XCTAssertTrue(kind.userContent(for: "Bună ziua").contains("Translate into German"))

        let cleaned = PolishKind.dictationTranslate(target: "German", polish: true, keepExisting: false)
        XCTAssertTrue(cleaned.system.contains("German"))
        XCTAssertTrue(cleaned.system.contains("Remove fillers and self-corrections"))
        XCTAssertFalse(cleaned.system.contains("Keep their language"))
        XCTAssertTrue(cleaned.userContent(for: "Bună").contains("Clean and translate into German"))
    }

    func testEveryListedLanguageIsRequestedByName() {
        let spoken = SpeechChoice.romanian
        for language in SpeechChoice.allCases where language != .automatic && language != spoken {
            let step = DictationPostprocess.step(polish: false, spoken: spoken, target: language)
            guard case .translate(let target, let keepExisting) = step else {
                XCTFail("\(language.promptName) was not translated")
                continue
            }
            XCTAssertEqual(target, language)
            XCTAssertFalse(keepExisting)
            let kind = step.polishKind
            XCTAssertTrue(kind?.system.contains("Always translate it into \(language.promptName)") == true)
            XCTAssertTrue(kind?.userContent(for: "Bună").contains("Write only in \(language.promptName)") == true)
            XCTAssertFalse(kind?.system.contains("Keep their language") == true)
            XCTAssertFalse(language.promptName.isEmpty)
            XCTAssertNotNil(language.code)
        }
    }

    func testRewriteNamesEveryListedLanguageInEnglish() {
        for language in SpeechChoice.allCases where language != .automatic {
            let instruction = RewriteAction.translate.instruction(target: language)
            XCTAssertTrue(instruction.contains("Write only in \(language.promptName)"))
            XCTAssertFalse(instruction.contains("Keep their language"))
        }
    }

    func testMeetingSummaryUsesTheTargetLanguage() {
        let translated = PolishKind.meeting("German").system
        XCTAssertTrue(translated.contains("in German"))
        XCTAssertFalse(translated.contains("in its language"))

        let original = PolishKind.meeting(nil).system
        XCTAssertTrue(original.contains("in its language"))
    }
}
