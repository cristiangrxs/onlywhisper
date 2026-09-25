import Foundation

enum DictationKey: String, Codable, CaseIterable, Sendable {
    case rightOption
    case leftOption

    var keyCode: Int64 {
        switch self {
        case .rightOption: 61
        case .leftOption: 58
        }
    }

    var title: String {
        switch self {
        case .rightOption: t("Right Option", "Rechte Option")
        case .leftOption: t("Left Option", "Linke Option")
        }
    }
}

enum SpeechChoice: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case german
    case english
    case french
    case spanish
    case italian
    case portuguese
    case dutch
    case polish
    case swedish
    case danish
    case finnish
    case greek
    case czech
    case slovak
    case slovenian
    case croatian
    case romanian
    case hungarian
    case bulgarian
    case estonian
    case latvian
    case lithuanian
    case maltese
    case irish
    case russian
    case ukrainian
    case japanese
    case chinese
    case korean
    case arabic

    var id: String { rawValue }

    var code: String? {
        switch self {
        case .automatic: nil
        case .german: "de"
        case .english: "en"
        case .french: "fr"
        case .spanish: "es"
        case .italian: "it"
        case .portuguese: "pt"
        case .dutch: "nl"
        case .polish: "pl"
        case .swedish: "sv"
        case .danish: "da"
        case .finnish: "fi"
        case .greek: "el"
        case .czech: "cs"
        case .slovak: "sk"
        case .slovenian: "sl"
        case .croatian: "hr"
        case .romanian: "ro"
        case .hungarian: "hu"
        case .bulgarian: "bg"
        case .estonian: "et"
        case .latvian: "lv"
        case .lithuanian: "lt"
        case .maltese: "mt"
        case .irish: "ga"
        case .russian: "ru"
        case .ukrainian: "uk"
        case .japanese: "ja"
        case .chinese: "zh"
        case .korean: "ko"
        case .arabic: "ar"
        }
    }

    var usesWhisper: Bool {
        switch self {
        case .irish, .japanese, .chinese, .korean, .arabic:
            true
        default:
            false
        }
    }

    var title: String {
        switch self {
        case .automatic: t("Automatic", "Automatisch")
        case .german: t("German", "Deutsch")
        case .english: t("English", "Englisch")
        case .french: t("French", "Französisch")
        case .spanish: t("Spanish", "Spanisch")
        case .italian: t("Italian", "Italienisch")
        case .portuguese: t("Portuguese", "Portugiesisch")
        case .dutch: t("Dutch", "Niederländisch")
        case .polish: t("Polish", "Polnisch")
        case .swedish: t("Swedish", "Schwedisch")
        case .danish: t("Danish", "Dänisch")
        case .finnish: t("Finnish", "Finnisch")
        case .greek: t("Greek", "Griechisch")
        case .czech: t("Czech", "Tschechisch")
        case .slovak: t("Slovak", "Slowakisch")
        case .slovenian: t("Slovenian", "Slowenisch")
        case .croatian: t("Croatian", "Kroatisch")
        case .romanian: t("Romanian", "Rumänisch")
        case .hungarian: t("Hungarian", "Ungarisch")
        case .bulgarian: t("Bulgarian", "Bulgarisch")
        case .estonian: t("Estonian", "Estnisch")
        case .latvian: t("Latvian", "Lettisch")
        case .lithuanian: t("Lithuanian", "Litauisch")
        case .maltese: t("Maltese", "Maltesisch")
        case .irish: t("Irish", "Irisch")
        case .russian: t("Russian", "Russisch")
        case .ukrainian: t("Ukrainian", "Ukrainisch")
        case .japanese: t("Japanese", "Japanisch")
        case .chinese: t("Chinese", "Chinesisch")
        case .korean: t("Korean", "Koreanisch")
        case .arabic: t("Arabic", "Arabisch")
        }
    }
}

enum RewriteAction: String, CaseIterable, Identifiable, Sendable {
    case improve
    case shorten
    case expand
    case professional
    case casual
    case bullets
    case tasks
    case translate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .improve: t("Improve writing", "Schreiben verbessern")
        case .shorten: t("Shorten", "Kürzen")
        case .expand: t("Expand", "Erweitern")
        case .professional: t("Make professional", "Professionell")
        case .casual: t("Make casual", "Locker")
        case .bullets: t("Bullet list", "Aufzählung")
        case .tasks: t("To-do list", "Aufgaben")
        case .translate: t("Translate", "Übersetzen")
        }
    }

    func instruction(target: SpeechChoice) -> String {
        switch self {
        case .improve:
            "Fix grammar, punctuation, and clarity. Keep the meaning and the language."
        case .shorten:
            "Shorten the text. Keep the meaning and the language."
        case .expand:
            "Expand the text slightly so it reads as a complete message. Keep the language."
        case .professional:
            "Rewrite in a professional tone. Keep the language."
        case .casual:
            "Rewrite in a casual tone. Keep the language."
        case .bullets:
            "Turn the text into a short bullet list. Keep the language."
        case .tasks:
            "Turn the text into a to-do list. Keep the language."
        case .translate:
            "Translate the text into \(target.title). Return only the translation."
        }
    }
}

@MainActor
@Observable
final class SettingsStore {
    var language: SpeechChoice {
        didSet { save() }
    }
    var polishEnabled: Bool {
        didSet { save() }
    }
    var launchAtLogin: Bool {
        didSet { save() }
    }
    var dictationKey: DictationKey {
        didSet { save() }
    }
    var systemAudioInMeetings: Bool {
        didSet { save() }
    }
    var translateTarget: SpeechChoice {
        didSet { save() }
    }
    var setupCompleted: Bool {
        didSet { save() }
    }

    private let url: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "OnlyWhisper", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        url = support.appending(path: "settings.json")
        let stored = (try? Data(contentsOf: url)).flatMap {
            try? JSONDecoder().decode(Stored.self, from: $0)
        }
        language = stored?.language ?? .automatic
        polishEnabled = stored?.polishEnabled ?? true
        launchAtLogin = stored?.launchAtLogin ?? false
        dictationKey = stored?.dictationKey ?? .rightOption
        systemAudioInMeetings = stored?.systemAudioInMeetings ?? false
        translateTarget = stored?.translateTarget ?? .english
        setupCompleted = stored?.setupCompleted ?? false
    }

    private func save() {
        let stored = Stored(
            language: language,
            polishEnabled: polishEnabled,
            launchAtLogin: launchAtLogin,
            dictationKey: dictationKey,
            systemAudioInMeetings: systemAudioInMeetings,
            translateTarget: translateTarget,
            setupCompleted: setupCompleted
        )
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private struct Stored: Codable {
        var language: SpeechChoice
        var polishEnabled: Bool
        var launchAtLogin: Bool
        var dictationKey: DictationKey
        var systemAudioInMeetings: Bool
        var translateTarget: SpeechChoice
        var setupCompleted: Bool?

        init(
            language: SpeechChoice,
            polishEnabled: Bool,
            launchAtLogin: Bool,
            dictationKey: DictationKey,
            systemAudioInMeetings: Bool,
            translateTarget: SpeechChoice,
            setupCompleted: Bool?
        ) {
            self.language = language
            self.polishEnabled = polishEnabled
            self.launchAtLogin = launchAtLogin
            self.dictationKey = dictationKey
            self.systemAudioInMeetings = systemAudioInMeetings
            self.translateTarget = translateTarget
            self.setupCompleted = setupCompleted
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            language = try container.decode(SpeechChoice.self, forKey: .language)
            polishEnabled = try container.decode(Bool.self, forKey: .polishEnabled)
            launchAtLogin = try container.decode(Bool.self, forKey: .launchAtLogin)
            dictationKey = try container.decode(DictationKey.self, forKey: .dictationKey)
            systemAudioInMeetings = try container.decode(Bool.self, forKey: .systemAudioInMeetings)
            translateTarget = try container.decode(SpeechChoice.self, forKey: .translateTarget)
            setupCompleted = try container.decodeIfPresent(Bool.self, forKey: .setupCompleted)
        }
    }
}
