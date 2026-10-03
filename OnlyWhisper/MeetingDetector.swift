import AppKit
import CoreAudio
import CoreGraphics
import Foundation

enum MeetingAppKind: Equatable, Sendable {
    case zoom
    case teams
    case faceTime
    case webex
    case slack
    case discord
    case browser

    var localizedName: String {
        switch self {
        case .zoom: "Zoom"
        case .teams: "Teams"
        case .faceTime: "FaceTime"
        case .webex: "Webex"
        case .slack: "Slack"
        case .discord: "Discord"
        case .browser: "Google Meet"
        }
    }
}

struct MeetingProcess: Equatable, Sendable {
    var pid: Int32
    var bundleID: String
    var input: Bool
    var output: Bool
}

struct DetectedMeeting: Equatable, Sendable {
    var kind: MeetingAppKind
    var bundleIDs: [String]
    var isBrowser: Bool
}

struct LaunchableApp: Equatable, Sendable {
    var name: String
    var bundleID: String
    var dockVisible: Bool
}

/// A dock app the user can record. Suggested meeting apps sort ahead of everything else.
struct MeetingAudioApp: Identifiable, Equatable, Sendable {
    var id: String { bundleID }
    var name: String
    var bundleID: String
    var suggested: Bool
    var browser: Bool
}

enum MeetingDetector {
    private static let ignoredPrefixes = [
        "com.apple.CoreSpeech",
        "com.apple.Siri",
        "com.apple.assistantd",
        "com.apple.speech.",
    ]

    /// A call is a known app that holds the microphone and is also playing audio. Merely running does not count.
    static func detect(processes: [MeetingProcess], ownPID: Int32, windowTitles: [String] = []) -> DetectedMeeting? {
        let relevant = processes.filter { process in
            process.pid != ownPID && !ignoredPrefixes.contains { process.bundleID.hasPrefix($0) }
        }
        let families: [(MeetingAppKind, (String) -> Bool)] = [
            (.zoom, isZoom),
            (.teams, isTeams),
            (.faceTime, { $0 == "com.apple.FaceTime" }),
            (.webex, { $0.localizedCaseInsensitiveContains("webex") }),
            (.slack, { $0 == "com.tinyspeck.slackmacgap" || $0.hasPrefix("com.tinyspeck.slack") }),
            (.discord, { $0 == "com.hnc.Discord" || $0.hasPrefix("com.hnc.Discord") }),
        ]
        for (kind, matches) in families {
            let members = relevant.filter { matches($0.bundleID) }
            if members.contains(where: \.input), members.contains(where: \.output) {
                return DetectedMeeting(
                    kind: kind,
                    bundleIDs: uniqueIDs(members.map(\.bundleID)),
                    isBrowser: false
                )
            }
        }
        let browsers = relevant.filter { isBrowser($0.bundleID) }
        let live = browsers.contains(where: \.input) && browsers.contains(where: \.output)
        guard live, windowTitles.contains(where: isMeetTitle) else { return nil }
        return DetectedMeeting(kind: .browser, bundleIDs: uniqueIDs(browsers.map(\.bundleID)), isBrowser: true)
    }

    static func current(ownPID: Int32 = ProcessInfo.processInfo.processIdentifier) -> DetectedMeeting? {
        detect(processes: liveProcesses(), ownPID: ownPID, windowTitles: windowTitles())
    }

    /// Dock-visible apps, suggested meeting apps first. Pass `runningBundleIDs` so a chosen app can include its helper processes.
    static func audioApps(
        from apps: [LaunchableApp],
        ownBundleID: String,
        runningBundleIDs: [String],
        meetWindow: Bool
    ) -> [MeetingAudioApp] {
        var seen: Set<String> = []
        var listed: [MeetingAudioApp] = []
        for app in apps {
            let bundleID = app.bundleID
            guard app.dockVisible, !bundleID.isEmpty, bundleID != ownBundleID, seen.insert(bundleID).inserted else { continue }
            let name = app.name.trimmingCharacters(in: .whitespacesAndNewlines)
            listed.append(MeetingAudioApp(
                name: name.isEmpty ? bundleID : name,
                bundleID: bundleID,
                suggested: isSuggested(bundleID, meetWindow: meetWindow),
                browser: isBrowser(bundleID)
            ))
        }
        return listed.sorted { lhs, rhs in
            if lhs.suggested != rhs.suggested { return lhs.suggested }
            let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if order == .orderedSame { return lhs.bundleID < rhs.bundleID }
            return order == .orderedAscending
        }
    }

    static func openApps(ownBundleID: String = Bundle.main.bundleIdentifier ?? "") -> [MeetingAudioApp] {
        let running = NSWorkspace.shared.runningApplications
        let apps = running.map {
            LaunchableApp(
                name: $0.localizedName ?? "",
                bundleID: $0.bundleIdentifier ?? "",
                dockVisible: $0.activationPolicy == .regular
            )
        }
        let ids = running.compactMap(\.bundleIdentifier)
        return audioApps(
            from: apps,
            ownBundleID: ownBundleID,
            runningBundleIDs: ids,
            meetWindow: windowTitles().contains(where: isMeetTitle)
        )
    }

    /// Bundle IDs whose audio belongs to the chosen app, including Zoom and Teams helper processes.
    static func captureBundleIDs(for bundleID: String, running: [String]) -> [String] {
        let family = familyMatch(bundleID)
        return uniqueIDs(running.filter(family) + [bundleID])
    }

    static func sameAudioFamily(_ lhs: String, _ rhs: String) -> Bool {
        lhs == rhs || familyMatch(lhs)(rhs)
    }

    static func isMeetTitle(_ title: String) -> Bool {
        let lower = title.lowercased()
        return lower.contains("meet.google")
            || lower.contains("google meet")
            || lower.contains("meet -")
            || lower.contains("meet –")
            || lower.contains("meet —")
    }

    private static func isZoom(_ bundleID: String) -> Bool {
        bundleID == "us.zoom.xos" || bundleID.hasPrefix("us.zoom.") || bundleID.localizedCaseInsensitiveContains("CptHost")
    }

    private static func isTeams(_ bundleID: String) -> Bool {
        bundleID == "com.microsoft.teams"
            || bundleID == "com.microsoft.teams2"
            || bundleID == "com.microsoft.vcxpc"
            || bundleID.hasPrefix("com.microsoft.teams")
    }

    private static let browserRoots = [
        "com.google.Chrome",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "company.thebrowser.Browser",
        "com.apple.Safari",
        "com.apple.WebKit",
    ]

    private static func isBrowser(_ bundleID: String) -> Bool {
        browserRoots.contains { bundleID == $0 || bundleID.hasPrefix($0 + ".") || bundleID.hasPrefix($0) }
    }

    private static func isSuggested(_ bundleID: String, meetWindow: Bool) -> Bool {
        if isZoom(bundleID) || isTeams(bundleID) || isFaceTime(bundleID) || isWebex(bundleID) || isSlack(bundleID) || isDiscord(bundleID) {
            return true
        }
        return isBrowser(bundleID) && meetWindow
    }

    private static func isFaceTime(_ bundleID: String) -> Bool {
        bundleID == "com.apple.FaceTime" || bundleID.hasPrefix("com.apple.FaceTime.")
    }

    private static func isWebex(_ bundleID: String) -> Bool {
        bundleID.localizedCaseInsensitiveContains("webex")
    }

    private static func isSlack(_ bundleID: String) -> Bool {
        bundleID == "com.tinyspeck.slackmacgap" || bundleID.hasPrefix("com.tinyspeck.slack")
    }

    private static func isDiscord(_ bundleID: String) -> Bool {
        bundleID == "com.hnc.Discord" || bundleID.hasPrefix("com.hnc.Discord")
    }

    /// Apps that share one audio stream with the chosen bundle, so a helper is recorded with its parent and nothing else.
    private static func familyMatch(_ bundleID: String) -> (String) -> Bool {
        if isZoom(bundleID) { return isZoom }
        if isTeams(bundleID) { return isTeams }
        if isFaceTime(bundleID) { return isFaceTime }
        if isWebex(bundleID) { return isWebex }
        if isSlack(bundleID) { return isSlack }
        if isDiscord(bundleID) { return isDiscord }
        if let root = browserRoots.first(where: { bundleID == $0 || bundleID.hasPrefix($0 + ".") || bundleID.hasPrefix($0) }) {
            return { $0 == root || $0.hasPrefix(root + ".") || $0.hasPrefix(root) }
        }
        return { $0 == bundleID }
    }

    private static func uniqueIDs(_ ids: [String]) -> [String] {
        Array(Set(ids)).sorted()
    }

    private static func liveProcesses() -> [MeetingProcess] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var ids = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap(process(for:))
    }

    private static func process(for object: AudioObjectID) -> MeetingProcess? {
        guard let bundleID = bundleID(of: object), !bundleID.isEmpty else { return nil }
        return MeetingProcess(
            pid: pid(of: object),
            bundleID: bundleID,
            input: flag(object, kAudioProcessPropertyIsRunningInput),
            output: flag(object, kAudioProcessPropertyIsRunningOutput)
        )
    }

    private static func pid(of object: AudioObjectID) -> Int32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Int32 = 0
        var size = UInt32(MemoryLayout<Int32>.size)
        _ = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
        return value
    }

    private static func flag(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return false }
        return value != 0
    }

    private static func bundleID(of object: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, UnsafeMutableRawPointer(pointer))
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func windowTitles() -> [String] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return info.compactMap { $0[kCGWindowName as String] as? String }
    }
}
