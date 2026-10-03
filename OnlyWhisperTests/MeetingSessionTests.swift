import XCTest
@testable import OnlyWhisper

final class MeetingSessionTests: XCTestCase {
    func testPauseKeepsSamplesAndResumeDoesNotDuplicateThem() {
        let buffer = SampleBuffer()
        buffer.append([1, 2, 3])
        buffer.setAccepting(false)
        buffer.append([9])
        XCTAssertEqual(buffer.snapshot(), [1, 2, 3])
        buffer.setAccepting(true)
        XCTAssertEqual(buffer.snapshot(), [1, 2, 3])
        buffer.append([4])
        XCTAssertEqual(buffer.snapshot(), [1, 2, 3, 4])
    }

    func testZoomWithMicrophoneAndOutputIsACall() {
        let found = MeetingDetector.detect(processes: [
            MeetingProcess(pid: 10, bundleID: "us.zoom.xos", input: true, output: false),
            MeetingProcess(pid: 11, bundleID: "us.zoom.CptHost", input: false, output: true),
        ], ownPID: 1)
        XCTAssertEqual(found?.kind, .zoom)
        XCTAssertEqual(found?.isBrowser, false)
    }

    func testOpenZoomIsNotACall() {
        let found = MeetingDetector.detect(processes: [
            MeetingProcess(pid: 10, bundleID: "us.zoom.xos", input: false, output: false),
        ], ownPID: 1)
        XCTAssertNil(found)
    }

    func testOwnProcessIsNeverACall() {
        let found = MeetingDetector.detect(processes: [
            MeetingProcess(pid: 4, bundleID: "us.zoom.xos", input: true, output: true),
        ], ownPID: 4)
        XCTAssertNil(found)
    }

    func testUnknownAppIsNotACall() {
        let found = MeetingDetector.detect(processes: [
            MeetingProcess(pid: 8, bundleID: "com.example.voice", input: true, output: true),
        ], ownPID: 1)
        XCTAssertNil(found)
    }

    func testSpeechServicesAreNotACall() {
        let found = MeetingDetector.detect(processes: [
            MeetingProcess(pid: 3, bundleID: "com.apple.CoreSpeech", input: true, output: true),
        ], ownPID: 1)
        XCTAssertNil(found)
    }

    func testSuggestedMeetingAppsSortAheadOfOtherOpenApps() {
        let apps = MeetingDetector.audioApps(
            from: [
                LaunchableApp(name: "Mail", bundleID: "com.apple.mail", dockVisible: true),
                LaunchableApp(name: "Zoom", bundleID: "us.zoom.xos", dockVisible: true),
                LaunchableApp(name: "Notes", bundleID: "com.apple.Notes", dockVisible: true),
                LaunchableApp(name: "OnlyWhisper", bundleID: "app.onlywhisper.mac", dockVisible: true),
                LaunchableApp(name: "Helper", bundleID: "us.zoom.CptHost", dockVisible: false),
            ],
            ownBundleID: "app.onlywhisper.mac",
            runningBundleIDs: ["us.zoom.xos", "us.zoom.CptHost", "com.apple.mail"],
            meetWindow: false
        )
        XCTAssertEqual(apps.map(\.name), ["Zoom", "Mail", "Notes"])
        XCTAssertEqual(apps.map(\.suggested), [true, false, false])
        XCTAssertEqual(
            MeetingDetector.captureBundleIDs(for: "us.zoom.xos", running: ["us.zoom.xos", "us.zoom.CptHost", "com.apple.mail"]),
            ["us.zoom.CptHost", "us.zoom.xos"]
        )
    }

    func testBrowserIsSuggestedOnlyWhileMeetIsOpen() {
        let chrome = LaunchableApp(name: "Google Chrome", bundleID: "com.google.Chrome", dockVisible: true)
        let closed = MeetingDetector.audioApps(from: [chrome], ownBundleID: "app.own", runningBundleIDs: ["com.google.Chrome", "com.google.Chrome.helper"], meetWindow: false)
        XCTAssertEqual(closed.first?.suggested, false)
        let open = MeetingDetector.audioApps(from: [chrome], ownBundleID: "app.own", runningBundleIDs: ["com.google.Chrome", "com.google.Chrome.helper", "com.apple.Safari"], meetWindow: true)
        XCTAssertEqual(open.first?.suggested, true)
        XCTAssertEqual(open.first?.browser, true)
        XCTAssertEqual(
            MeetingDetector.captureBundleIDs(for: "com.google.Chrome", running: ["com.google.Chrome", "com.google.Chrome.helper", "com.apple.Safari"]),
            ["com.google.Chrome", "com.google.Chrome.helper"]
        )
    }

    func testUnrelatedAppDoesNotPullInOtherAudio() {
        XCTAssertEqual(
            MeetingDetector.captureBundleIDs(for: "com.apple.mail", running: ["com.apple.mail", "us.zoom.xos", "com.google.Chrome"]),
            ["com.apple.mail"]
        )
    }

    func testSameSpeakerMergesAcrossAShortGap() {
        let turns = MeetingMerger.turns(
            utterances: [
                MeetingUtterance(start: 0, end: 2, text: "Hello", track: .remote),
                MeetingUtterance(start: 2.4, end: 4, text: "there", track: .remote),
            ],
            speakers: [SpeakerSpan(id: "s-1", start: 0, end: 5, finalized: true)],
            separatesLocalVoice: true
        )
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns[0].text, "Hello there")
        XCTAssertEqual(turns[0].speakerID, "s-1")
    }

    func testSpeakerChangeSplits() {
        let turns = MeetingMerger.turns(
            utterances: [
                MeetingUtterance(start: 0, end: 2, text: "One", track: .remote),
                MeetingUtterance(start: 2.1, end: 4, text: "Two", track: .remote),
            ],
            speakers: [
                SpeakerSpan(id: "s-0", start: 0, end: 2, finalized: true),
                SpeakerSpan(id: "s-1", start: 2, end: 4, finalized: true),
            ],
            separatesLocalVoice: true
        )
        XCTAssertEqual(turns.map(\.speakerID), ["s-0", "s-1"])
    }

    func testPauseSplitsTheSameSpeaker() {
        let turns = MeetingMerger.turns(
            utterances: [
                MeetingUtterance(start: 0, end: 2, text: "Before", track: .remote),
                MeetingUtterance(start: 4, end: 6, text: "After", track: .remote),
            ],
            speakers: [SpeakerSpan(id: "s-0", start: 0, end: 6, finalized: true)],
            separatesLocalVoice: true
        )
        XCTAssertEqual(turns.count, 2)
        XCTAssertEqual(turns.map(\.speakerID), ["s-0", "s-0"])
    }

    func testLaterLabelReplacesUnknown() {
        let utterances = [MeetingUtterance(start: 1, end: 3, text: "Hi", track: .remote)]
        let unlabeled = MeetingMerger.turns(utterances: utterances, speakers: [], separatesLocalVoice: true)
        XCTAssertEqual(unlabeled[0].speakerID, MeetingMerger.unknownSpeakerID)
        let labeled = MeetingMerger.turns(
            utterances: utterances,
            speakers: [SpeakerSpan(id: "s-2", start: 0, end: 4, finalized: true)],
            separatesLocalVoice: true
        )
        XCTAssertEqual(labeled[0].speakerID, "s-2")
    }

    func testRenameAppliesToEveryTurnOfThatSpeaker() {
        let turns = MeetingMerger.turns(
            utterances: [
                MeetingUtterance(start: 0, end: 1, text: "Hello", track: .remote),
                MeetingUtterance(start: 3, end: 4, text: "Again", track: .remote),
            ],
            speakers: [SpeakerSpan(id: "s-1", start: 0, end: 5, finalized: true)],
            separatesLocalVoice: true
        )
        let text = MeetingMerger.plainTranscript(
            turns: turns,
            names: ["s-1": "Ada"],
            separatesLocalVoice: true
        )
        XCTAssertEqual(turns.count, 2)
        XCTAssertEqual(text, "Ada: Hello\nAda: Again")
    }

    func testLocalVoiceStaysSeparateFromTheCall() {
        let turns = MeetingMerger.turns(
            utterances: [
                MeetingUtterance(start: 0, end: 1, text: "Me", track: .local),
                MeetingUtterance(start: 1.1, end: 2, text: "Them", track: .remote),
            ],
            speakers: [SpeakerSpan(id: "s-0", start: 0, end: 2, finalized: true)],
            separatesLocalVoice: true
        )
        XCTAssertEqual(turns.map(\.speakerID), [MeetingMerger.localSpeakerID, "s-0"])
        XCTAssertEqual(turns.map(\.isLocal), [true, false])
    }

    func testHistoryWithoutMeetingStillDecodes() throws {
        let json = """
        [{"id":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE","date":0,"source":"dictation","raw":"hello","polished":"hello"}]
        """.data(using: .utf8)!
        let entries = try JSONDecoder().decode([HistoryEntry].self, from: json)
        XCTAssertEqual(entries.count, 1)
        XCTAssertNil(entries[0].meeting)
        XCTAssertEqual(entries[0].raw, "hello")
    }

    func testHistoryMeetingRoundTrip() throws {
        let record = MeetingRecord(
            duration: 12,
            turns: [MeetingTurn(id: "local@0", speakerID: "local", start: 0, end: 1, text: "Hi", isLocal: true)],
            notes: MeetingNotes(summary: "A call", decisions: [], tasks: []),
            names: ["local": "Du"],
            separatesLocalVoice: true
        )
        let entry = HistoryEntry(source: "meeting", title: "Zoom", raw: "Du: Hi", polished: "A call", meeting: record)
        let data = try JSONEncoder().encode([entry])
        let decoded = try JSONDecoder().decode([HistoryEntry].self, from: data)
        XCTAssertEqual(decoded[0].meeting, record)
        XCTAssertEqual(decoded[0].title, "Zoom")
    }

    func testLiveProcessQueryDoesNotCrash() {
        _ = MeetingDetector.current(ownPID: ProcessInfo.processInfo.processIdentifier)
    }
}
