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
    case amharic
    case assamese
    case bashkir
    case belarusian
    case bosnian
    case breton
    case burmese
    case faroese
    case gujarati
    case haitianCreole
    case hausa
    case hawaiian
    case javanese
    case kannada
    case kazakh
    case khmer
    case lao
    case latin
    case lingala
    case luxembourgish
    case malagasy
    case malayalam
    case maori
    case marathi
    case mongolian
    case nepali
    case nynorsk
    case occitan
    case pashto
    case punjabi
    case sanskrit
    case shona
    case sindhi
    case sinhala
    case somali
    case sundanese
    case tajik
    case tatar
    case telugu
    case tibetan
    case turkmen
    case uzbek
    case yiddish
    case yoruba

    var id: String { rawValue }

    var code: String? { spec.code }

    /// Whisper transcribes every language. A missing code asks it to detect the language.
    var usesWhisper: Bool { true }

    /// Parakeet Ultra covers these European languages. Automatic stays inside that set.
    var supportsParakeet: Bool {
        self == .automatic || spec.parakeet
    }

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
        case .serbian: ("sr", "Serbian", "Serbisch", true)
        case .macedonian: ("mk", "Macedonian", "Mazedonisch", false)
        case .albanian: ("sq", "Albanian", "Albanisch", false)
        case .azerbaijani: ("az", "Azerbaijani", "Aserbaidschanisch", false)
        case .armenian: ("hy", "Armenian", "Armenisch", false)
        case .georgian: ("ka", "Georgian", "Georgisch", false)
        case .swahili: ("sw", "Swahili", "Swahili", false)
        case .galician: ("gl", "Galician", "Galicisch", false)
        case .amharic: ("am", "Amharic", "Amharisch", false)
        case .assamese: ("as", "Assamese", "Assamesisch", false)
        case .bashkir: ("ba", "Bashkir", "Baschkirisch", false)
        case .belarusian: ("be", "Belarusian", "Belarussisch", true)
        case .bosnian: ("bs", "Bosnian", "Bosnisch", true)
        case .breton: ("br", "Breton", "Bretonisch", false)
        case .burmese: ("my", "Burmese", "Birmanisch", false)
        case .faroese: ("fo", "Faroese", "Färöisch", false)
        case .gujarati: ("gu", "Gujarati", "Gujarati", false)
        case .haitianCreole: ("ht", "Haitian Creole", "Haitianisch-Kreolisch", false)
        case .hausa: ("ha", "Hausa", "Haussa", false)
        case .hawaiian: ("haw", "Hawaiian", "Hawaiisch", false)
        case .javanese: ("jw", "Javanese", "Javanisch", false)
        case .kannada: ("kn", "Kannada", "Kannada", false)
        case .kazakh: ("kk", "Kazakh", "Kasachisch", false)
        case .khmer: ("km", "Khmer", "Khmer", false)
        case .lao: ("lo", "Lao", "Laotisch", false)
        case .latin: ("la", "Latin", "Latein", false)
        case .lingala: ("ln", "Lingala", "Lingala", false)
        case .luxembourgish: ("lb", "Luxembourgish", "Luxemburgisch", false)
        case .malagasy: ("mg", "Malagasy", "Malagassi", false)
        case .malayalam: ("ml", "Malayalam", "Malayalam", false)
        case .maori: ("mi", "Maori", "Maori", false)
        case .marathi: ("mr", "Marathi", "Marathi", false)
        case .mongolian: ("mn", "Mongolian", "Mongolisch", false)
        case .nepali: ("ne", "Nepali", "Nepalesisch", false)
        case .nynorsk: ("nn", "Norwegian Nynorsk", "Norwegisch (Nynorsk)", false)
        case .occitan: ("oc", "Occitan", "Okzitanisch", false)
        case .pashto: ("ps", "Pashto", "Paschtu", false)
        case .punjabi: ("pa", "Punjabi", "Panjabi", false)
        case .sanskrit: ("sa", "Sanskrit", "Sanskrit", false)
        case .shona: ("sn", "Shona", "Shona", false)
        case .sindhi: ("sd", "Sindhi", "Sindhi", false)
        case .sinhala: ("si", "Sinhala", "Singhalesisch", false)
        case .somali: ("so", "Somali", "Somali", false)
        case .sundanese: ("su", "Sundanese", "Sundanesisch", false)
        case .tajik: ("tg", "Tajik", "Tadschikisch", false)
        case .tatar: ("tt", "Tatar", "Tatarisch", false)
        case .telugu: ("te", "Telugu", "Telugu", false)
        case .tibetan: ("bo", "Tibetan", "Tibetisch", false)
        case .turkmen: ("tk", "Turkmen", "Turkmenisch", false)
        case .uzbek: ("uz", "Uzbek", "Usbekisch", false)
        case .yiddish: ("yi", "Yiddish", "Jiddisch", false)
        case .yoruba: ("yo", "Yoruba", "Yoruba", false)
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

/// The speech model that transcribes. Qwen stays separate and is always installed with it.
enum SpeechEngine: String, Codable, CaseIterable, Identifiable, Sendable {
    case parakeet
    case whisper

    var id: String { rawValue }

    var modelID: ModelID {
        switch self {
        case .parakeet: .parakeet
        case .whisper: .whisper
        }
    }

    var other: SpeechEngine {
        switch self {
        case .parakeet: .whisper
        case .whisper: .parakeet
        }
    }
}

@MainActor
@Observable
final class SettingsStore {
    var language: SpeechChoice {
        didSet { save() }
    }
    /// Installed choice used for dictation, files, and meetings. Missing settings stay on Whisper.
    var speechModel: SpeechEngine {
        didSet { save() }
    }
    /// A model the user picked that is still downloading. The active model keeps transcribing until this one is usable.
    var pendingSpeechModel: SpeechEngine? {
        didSet { save() }
    }
    /// When the pending model becomes usable, remove the one it replaces.
    var removePendingPredecessor: Bool {
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
    /// Nil means translation is off and the text stays as it is.
    var translateTarget: SpeechChoice? {
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
        speechModel = stored?.speechModel ?? .whisper
        pendingSpeechModel = stored?.pendingSpeechModel
        removePendingPredecessor = stored?.removePendingPredecessor ?? false
        polishEnabled = stored?.polishEnabled ?? true
        launchAtLogin = stored?.launchAtLogin ?? false
        dictationKey = stored?.dictationKey ?? .rightOption
        systemAudioInMeetings = stored?.systemAudioInMeetings ?? false
        if let stored {
            translateTarget = stored.translateTarget
        } else {
            translateTarget = .english
        }
        setupCompleted = stored?.setupCompleted ?? false
        if speechModel == .parakeet, !language.supportsParakeet {
            language = .automatic
            save()
        }
    }

    private func save() {
        let stored = Stored(
            language: language,
            speechModel: speechModel,
            pendingSpeechModel: pendingSpeechModel,
            removePendingPredecessor: removePendingPredecessor,
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
        var speechModel: SpeechEngine?
        var pendingSpeechModel: SpeechEngine?
        var removePendingPredecessor: Bool?
        var polishEnabled: Bool
        var launchAtLogin: Bool
        var dictationKey: DictationKey
        var systemAudioInMeetings: Bool
        /// Nil is an explicit Off. A missing key stays English so older settings keep translating.
        var translateTarget: SpeechChoice?
        var setupCompleted: Bool?

        enum CodingKeys: String, CodingKey {
            case language
            case speechModel
            case pendingSpeechModel
            case removePendingPredecessor
            case polishEnabled
            case launchAtLogin
            case dictationKey
            case systemAudioInMeetings
            case translateTarget
            case setupCompleted
        }

        init(
            language: SpeechChoice,
            speechModel: SpeechEngine?,
            pendingSpeechModel: SpeechEngine?,
            removePendingPredecessor: Bool?,
            polishEnabled: Bool,
            launchAtLogin: Bool,
            dictationKey: DictationKey,
            systemAudioInMeetings: Bool,
            translateTarget: SpeechChoice?,
            setupCompleted: Bool?
        ) {
            self.language = language
            self.speechModel = speechModel
            self.pendingSpeechModel = pendingSpeechModel
            self.removePendingPredecessor = removePendingPredecessor
            self.polishEnabled = polishEnabled
            self.launchAtLogin = launchAtLogin
            self.dictationKey = dictationKey
            self.systemAudioInMeetings = systemAudioInMeetings
            self.translateTarget = translateTarget
            self.setupCompleted = setupCompleted
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            language = Self.speechChoice(from: container, forKey: .language) ?? .automatic
            speechModel = try container.decodeIfPresent(SpeechEngine.self, forKey: .speechModel)
            pendingSpeechModel = try container.decodeIfPresent(SpeechEngine.self, forKey: .pendingSpeechModel)
            removePendingPredecessor = try container.decodeIfPresent(Bool.self, forKey: .removePendingPredecessor)
            polishEnabled = try container.decode(Bool.self, forKey: .polishEnabled)
            launchAtLogin = try container.decode(Bool.self, forKey: .launchAtLogin)
            dictationKey = try container.decode(DictationKey.self, forKey: .dictationKey)
            systemAudioInMeetings = try container.decode(Bool.self, forKey: .systemAudioInMeetings)
            if container.contains(.translateTarget) {
                translateTarget = Self.speechChoice(from: container, forKey: .translateTarget)
            } else {
                translateTarget = .english
            }
            setupCompleted = try container.decodeIfPresent(Bool.self, forKey: .setupCompleted)
        }

        /// Unknown values, such as a language this build no longer offers, stay usable.
        /// Speech falls back to automatic. A translation target falls back to off.
        private static func speechChoice(
            from container: KeyedDecodingContainer<CodingKeys>,
            forKey key: CodingKeys
        ) -> SpeechChoice? {
            guard let raw = try? container.decode(String.self, forKey: key) else { return nil }
            return SpeechChoice(rawValue: raw)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(language, forKey: .language)
            try container.encodeIfPresent(speechModel, forKey: .speechModel)
            try container.encodeIfPresent(pendingSpeechModel, forKey: .pendingSpeechModel)
            try container.encodeIfPresent(removePendingPredecessor, forKey: .removePendingPredecessor)
            try container.encode(polishEnabled, forKey: .polishEnabled)
            try container.encode(launchAtLogin, forKey: .launchAtLogin)
            try container.encode(dictationKey, forKey: .dictationKey)
            try container.encode(systemAudioInMeetings, forKey: .systemAudioInMeetings)
            if let translateTarget {
                try container.encode(translateTarget, forKey: .translateTarget)
            } else {
                try container.encodeNil(forKey: .translateTarget)
            }
            try container.encodeIfPresent(setupCompleted, forKey: .setupCompleted)
        }
    }
}
