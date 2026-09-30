import XCTest
@testable import OnlyWhisper

final class SpeechRoutingTests: XCTestCase {
    func testAutomaticHasNoLanguageCode() {
        XCTAssertNil(SpeechChoice.automatic.code)
        XCTAssertTrue(SpeechChoice.automatic.usesWhisper)
    }

    func testEveryLanguageUsesWhisper() {
        for choice in SpeechChoice.allCases {
            XCTAssertTrue(choice.usesWhisper, choice.rawValue)
        }
    }

    func testWhisperLanguages() {
        let whisper: [SpeechChoice] = [
            .irish, .japanese, .chinese, .korean, .arabic, .turkish, .indonesian, .vietnamese,
            .hebrew, .hindi, .thai, .malay, .persian, .urdu, .bengali, .tamil, .cantonese,
            .tagalog, .catalan, .norwegian, .afrikaans, .welsh, .basque, .icelandic, .serbian,
            .macedonian, .albanian, .azerbaijani, .armenian, .georgian, .swahili, .galician,
        ]
        XCTAssertEqual(whisper.count, 32)
        for choice in whisper {
            XCTAssertTrue(choice.usesWhisper, choice.rawValue)
            XCTAssertNotNil(choice.code, choice.rawValue)
        }
        XCTAssertEqual(SpeechChoice.allCases.count, 58)
    }

    func testWhisperModelPrefersTurboWhenListed() {
        XCTAssertEqual(
            WhisperModelChoice.name(
                supported: [
                    "openai_whisper-\(WhisperModelChoice.turbo)",
                    "openai_whisper-\(WhisperModelChoice.turbo)_632MB",
                    "openai_whisper-\(WhisperModelChoice.compact)",
                ],
                fallback: "openai_whisper-base"
            ),
            WhisperModelChoice.turbo
        )
    }

    func testWhisperModelUsesCompactWhenTurboIsMissing() {
        XCTAssertEqual(
            WhisperModelChoice.name(
                supported: ["openai_whisper-\(WhisperModelChoice.compact)"],
                fallback: "openai_whisper-base"
            ),
            WhisperModelChoice.compact
        )
    }

    func testWhisperModelUsesDeviceFallbackWhenNeitherFits() {
        XCTAssertEqual(
            WhisperModelChoice.name(supported: ["openai_whisper-tiny"], fallback: "openai_whisper-base"),
            "openai_whisper-base"
        )
    }
}
