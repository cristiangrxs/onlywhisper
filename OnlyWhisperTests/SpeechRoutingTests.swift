import XCTest
@testable import OnlyWhisper

final class SpeechRoutingTests: XCTestCase {
    func testAutomaticHasNoLanguageCode() {
        XCTAssertNil(SpeechChoice.automatic.code)
        XCTAssertTrue(SpeechChoice.automatic.usesWhisper)
    }

    func testSwitchingBackStillAsksWhenTheSpeechModelAlreadyFinished() {
        let choice = SpeechSwitchPlanner.choose(
            engine: .whisper,
            active: .whisper,
            pending: .parakeet,
            engineUsable: true,
            qwenUsable: false,
            engineTransferring: false,
            qwenTransferring: true,
            otherUsable: false,
            otherTransferring: false
        )
        XCTAssertEqual(choice, .askToCancelDownload(.parakeet))
        XCTAssertEqual(
            SpeechSwitchPlanner.confirmCancel(target: .whisper, downloading: .parakeet, targetUsable: false),
            [.remove(.parakeet), .download(.whisper)]
        )
    }

    func testSwitchingBackDuringDownloadAsksToCancel() {
        let choice = SpeechSwitchPlanner.choose(
            engine: .whisper,
            active: .whisper,
            pending: .parakeet,
            engineUsable: true,
            qwenUsable: true,
            engineTransferring: false,
            qwenTransferring: false,
            otherUsable: false,
            otherTransferring: true
        )
        XCTAssertEqual(choice, .askToCancelDownload(.parakeet))
        XCTAssertEqual(
            SpeechSwitchPlanner.confirmCancel(target: .whisper, downloading: .parakeet, targetUsable: true),
            [.remove(.parakeet), .activate(.whisper)]
        )
    }

    func testRemoveDeletesTheInstalledModelBeforeTheNewDownload() {
        XCTAssertEqual(
            SpeechSwitchPlanner.confirmReplace(target: .parakeet, removeOther: true, other: .whisper, targetUsable: false),
            [.remove(.whisper), .download(.parakeet)]
        )
        XCTAssertEqual(
            SpeechSwitchPlanner.confirmReplace(target: .parakeet, removeOther: false, other: .whisper, targetUsable: false),
            [.download(.parakeet)]
        )
    }

    func testInstalledModelAsksBeforeItIsReplaced() {
        let choice = SpeechSwitchPlanner.choose(
            engine: .parakeet,
            active: .whisper,
            pending: nil,
            engineUsable: false,
            qwenUsable: true,
            engineTransferring: false,
            qwenTransferring: false,
            otherUsable: true,
            otherTransferring: false
        )
        XCTAssertEqual(choice, .askToReplace(.whisper))
    }

    func testParakeetCoversEuropeanLanguagesAndAutomatic() {
        XCTAssertTrue(SpeechChoice.automatic.supportsParakeet)
        XCTAssertTrue(SpeechChoice.german.supportsParakeet)
        XCTAssertTrue(SpeechChoice.ukrainian.supportsParakeet)
        XCTAssertFalse(SpeechChoice.japanese.supportsParakeet)
        XCTAssertFalse(SpeechChoice.norwegian.supportsParakeet)
        XCTAssertEqual(SpeechEngine.parakeet.modelID, .parakeet)
        XCTAssertEqual(SpeechEngine.whisper.other, .parakeet)
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

    func testConfidentSilenceIsDropped() {
        XCTAssertNil(WhisperEngine.keepSegment(
            text: "Thank you",
            noSpeechProb: 0.9,
            compressionRatio: 1.1,
            avgLogprob: -0.2,
            live: true
        ))
    }

    func testRepeatedPhraseIsDropped() {
        XCTAssertNil(WhisperEngine.keepSegment(
            text: "thank you thank you",
            noSpeechProb: 0.1,
            compressionRatio: 3.0,
            avgLogprob: -0.2,
            live: true
        ))
    }

    func testUncertainLiveWordIsKept() {
        XCTAssertEqual(
            WhisperEngine.keepSegment(
                text: "hel",
                noSpeechProb: 0.2,
                compressionRatio: 1.1,
                avgLogprob: -2.0,
                live: true
            ),
            "hel"
        )
    }

    func testUncertainFinalWordIsDropped() {
        XCTAssertNil(WhisperEngine.keepSegment(
            text: "hel",
            noSpeechProb: 0.2,
            compressionRatio: 1.1,
            avgLogprob: -2.0,
            live: false
        ))
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
