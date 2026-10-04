import Foundation

/// What the writing model does after speech has been transcribed.
enum DictationPostprocess: Equatable {
    case none
    case polish
    /// `keepExisting` is only for automatic speech, where the text may already be in the target language.
    case translate(SpeechChoice, keepExisting: Bool)
    case polishAndTranslate(SpeechChoice, keepExisting: Bool)

    /// Translation runs when a target is set and it differs from a fixed spoken language.
    /// Automatic speech still translates. The same language, or Off, does not.
    static func step(polish: Bool, spoken: SpeechChoice, target: SpeechChoice?) -> Self {
        switch (polish, translationRequest(spoken: spoken, target: target)) {
        case (false, nil):
            return .none
        case (true, nil):
            return .polish
        case (false, let request?):
            return .translate(request.language, keepExisting: request.keepExisting)
        case (true, let request?):
            return .polishAndTranslate(request.language, keepExisting: request.keepExisting)
        }
    }

    var usesWritingModel: Bool {
        self != .none
    }

    var translates: Bool {
        switch self {
        case .translate, .polishAndTranslate: true
        case .none, .polish: false
        }
    }

    var polishKind: PolishKind? {
        switch self {
        case .none:
            nil
        case .polish:
            .dictation
        case .translate(let language, let keepExisting):
            .dictationTranslate(target: language.promptName, polish: false, keepExisting: keepExisting)
        case .polishAndTranslate(let language, let keepExisting):
            .dictationTranslate(target: language.promptName, polish: true, keepExisting: keepExisting)
        }
    }

    var workingTitle: String {
        switch self {
        case .none:
            ""
        case .polish:
            t("Polishing…", "Poliert…")
        case .translate, .polishAndTranslate:
            t("Translating…", "Wird übersetzt…")
        }
    }

    /// Shown when dictation keeps the spoken text because translation or polishing failed.
    var fallbackHint: String {
        switch self {
        case .none, .polish:
            t(
                "Polishing was not possible. The original text was inserted.",
                "Glätten nicht möglich, Rohtext eingefügt."
            )
        case .translate, .polishAndTranslate:
            t(
                "Translation was not possible. The original text was inserted.",
                "Übersetzung nicht möglich, Originaltext eingefügt."
            )
        }
    }

    /// Shown when a file transcript stays in the spoken language.
    static var fileTranslationKept: String {
        t(
            "Translation was not possible. The transcript was kept.",
            "Übersetzung nicht möglich, Transkript behalten."
        )
    }

    private struct Request: Equatable {
        var language: SpeechChoice
        var keepExisting: Bool
    }

    /// Every language in the picker is a target. A fixed spoken language that matches the target is left as it is.
    private static func translationRequest(spoken: SpeechChoice, target: SpeechChoice?) -> Request? {
        guard let target, target != .automatic else { return nil }
        if spoken != .automatic, spoken == target { return nil }
        return Request(language: target, keepExisting: spoken == .automatic)
    }
}
