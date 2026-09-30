import Foundation
import WhisperKit

enum ModelPaths {
    static var root: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "OnlyWhisper/Models", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// FluidAudio strips the last path component and writes `parakeet-ultra-coreml` next to it.
    static var parakeet: URL { root.appending(path: "Parakeet", directoryHint: .isDirectory) }
    static var whisper: URL { root.appending(path: "Whisper", directoryHint: .isDirectory) }
    static var qwen: URL { root.appending(path: "Qwen3-4B-Instruct-2507-4bit", directoryHint: .isDirectory) }
    static var diarization: URL { root.appending(path: "Diarization", directoryHint: .isDirectory) }
    static var readyMarker: URL { root.appending(path: "ready.json") }

    static let qwenRepository = "mlx-community/Qwen3-4B-Instruct-2507-4bit"
    static var whisperModelName: String { WhisperModelChoice.current }
}

enum WhisperModelChoice {
    static let turbo = "large-v3-v20240930_turbo"
    static let compact = "large-v3-v20240930_626MB"

    /// Turbo when WhisperKit lists it for this Mac. The M1 family does not, so it gets the smaller build of the same checkpoint.
    /// WhisperKit's support list uses the `openai_whisper-` folder name; the app loads the short name.
    static func name(supported: [String], fallback: String) -> String {
        if supported.contains(where: { matches($0, turbo) }) { return turbo }
        if supported.contains(where: { matches($0, compact) }) { return compact }
        return fallback
    }

    private static func matches(_ listed: String, _ model: String) -> Bool {
        listed == model || listed.hasSuffix(model)
    }

    static var current: String {
        let support = WhisperKit.recommendedModels()
        return name(supported: support.supported, fallback: support.default)
    }

    static var usesTurbo: Bool { current == turbo }

    static var displayName: String {
        usesTurbo ? "Whisper Large v3 Turbo" : "Whisper Large v3"
    }

    static var displaySize: String {
        usesTurbo ? "≈ 1.6 GB" : "≈ 0.6 GB"
    }

    static func isInstalled(downloadBase: URL, modelName: String) -> Bool {
        let folder = modelName.hasPrefix("openai_whisper-") ? modelName : "openai_whisper-\(modelName)"
        let config = downloadBase
            .appending(path: "models/argmaxinc/whisperkit-coreml/\(folder)", directoryHint: .isDirectory)
            .appending(path: "config.json")
        return FileManager.default.fileExists(atPath: config.path)
    }
}
