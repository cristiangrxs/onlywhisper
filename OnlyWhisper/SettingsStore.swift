import Foundation

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
    case russian
    case ukrainian
    case irish
    case japanese
    case chinese
    case korean
    case arabic
    case turkish
    case indonesian
    case vietnamese
    case hebrew
    case hindi
    case thai
    case malay
    case persian
    case urdu
    case bengali
    case tamil
    case cantonese
    case tagalog
    case catalan
    case norwegian
    case afrikaans
    case welsh
    case basque
    case icelandic
    case serbian
    case macedonian
    case albanian
    case azerbaijani
    case armenian
    case georgian
    case swahili
    case galician

    var id: String { rawValue }

    var code: String? { spec.code }

    /// Whisper transcribes every language. A missing code asks it to detect the language.
    var usesWhisper: Bool { true }

    var title: String { t(spec.english, spec.german) }

    private var spec: (code: String?, english: String, german: String, parakeet: Bool) {
        switch self {
        case .automatic: (nil, "Automatic", "Automatisch", false)
        case .german: ("de", "German", "Deutsch", true)
        case .english: ("en", "English", "Englisch", true)
        case .french: ("fr", "French", "Französisch", true)
        case .spanish: ("es", "Spanish", "Spanisch", true)
        case .italian: ("it", "Italian", "Italienisch", true)
        case .portuguese: ("pt", "Portuguese", "Portugiesisch", true)
        case .dutch: ("nl", "Dutch", "Niederländisch", true)
        case .polish: ("pl", "Polish", "Polnisch", true)
        case .swedish: ("sv", "Swedish", "Schwedisch", true)
        case .danish: ("da", "Danish", "Dänisch", true)
        case .finnish: ("fi", "Finnish", "Finnisch", true)
        case .greek: ("el", "Greek", "Griechisch", true)
        case .czech: ("cs", "Czech", "Tschechisch", true)
        case .slovak: ("sk", "Slovak", "Slowakisch", true)
        case .slovenian: ("sl", "Slovenian", "Slowenisch", true)
        case .croatian: ("hr", "Croatian", "Kroatisch", true)
        case .romanian: ("ro", "Romanian", "Rumänisch", true)
        case .hungarian: ("hu", "Hungarian", "Ungarisch", true)
        case .bulgarian: ("bg", "Bulgarian", "Bulgarisch", true)
        case .estonian: ("et", "Estonian", "Estnisch", true)
        case .latvian: ("lv", "Latvian", "Lettisch", true)
        case .lithuanian: ("lt", "Lithuanian", "Litauisch", true)
        case .maltese: ("mt", "Maltese", "Maltesisch", true)
        case .russian: ("ru", "Russian", "Russisch", true)
        case .ukrainian: ("uk", "Ukrainian", "Ukrainisch", true)
        case .irish: ("ga", "Irish", "Irisch", false)
        case .japanese: ("ja", "Japanese", "Japanisch", false)
        case .chinese: ("zh", "Chinese", "Chinesisch", false)
        case .korean: ("ko", "Korean", "Koreanisch", false)
        case .arabic: ("ar", "Arabic", "Arabisch", false)
        case .turkish: ("tr", "Turkish", "Türkisch", false)
        case .indonesian: ("id", "Indonesian", "Indonesisch", false)
        case .vietnamese: ("vi", "Vietnamese", "Vietnamesisch", false)
        case .hebrew: ("he", "Hebrew", "Hebräisch", false)
        case .hindi: ("hi", "Hindi", "Hindi", false)
        case .thai: ("th", "Thai", "Thailändisch", false)
        case .malay: ("ms", "Malay", "Malaiisch", false)
        case .persian: ("fa", "Persian", "Persisch", false)
        case .urdu: ("ur", "Urdu", "Urdu", false)
        case .bengali: ("bn", "Bengali", "Bengalisch", false)
        case .tamil: ("ta", "Tamil", "Tamil", false)
        case .cantonese: ("yue", "Cantonese", "Kantonesisch", false)
        case .tagalog: ("tl", "Tagalog", "Tagalog", false)
        case .catalan: ("ca", "Catalan", "Katalanisch", false)
        case .norwegian: ("no", "Norwegian", "Norwegisch", false)
        case .afrikaans: ("af", "Afrikaans", "Afrikaans", false)
        case .welsh: ("cy", "Welsh", "Walisisch", false)
        case .basque: ("eu", "Basque", "Baskisch", false)
        case .icelandic: ("is", "Icelandic", "Isländisch", false)
        case .serbian: ("sr", "Serbian", "Serbisch", false)
        case .macedonian: ("mk", "Macedonian", "Mazedonisch", false)
        case .albanian: ("sq", "Albanian", "Albanisch", false)
        case .azerbaijani: ("az", "Azerbaijani", "Aserbaidschanisch", false)
        case .armenian: ("hy", "Armenian", "Armenisch", false)
        case .georgian: ("ka", "Georgian", "Georgisch", false)
        case .swahili: ("sw", "Swahili", "Swahili", false)
        case .galician: ("gl", "Galician", "Galicisch", false)
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
