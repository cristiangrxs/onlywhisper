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
}
