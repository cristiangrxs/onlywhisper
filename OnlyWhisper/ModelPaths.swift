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
    /// Weights FluidAudio writes beside `parakeet`, after stripping that last path component.
    static var parakeetWeights: URL { root.appending(path: "parakeet-ultra-coreml", directoryHint: .isDirectory) }
    static var diarization: URL { root.appending(path: "Diarization", directoryHint: .isDirectory) }
    static var installations: URL { root.appending(path: "installations.json") }

    static func whisperLegacyPresent(fileManager: FileManager = .default) -> Bool {
        let base = whisper.appending(path: "models/argmaxinc/whisperkit-coreml", directoryHint: .isDirectory)
        let names = (try? fileManager.contentsOfDirectory(atPath: base.path)) ?? []
        return WhisperModelChoice.hasLegacyInstall(folderNames: names, currentModelName: whisperModelName)
    }

    static let qwenRepository = "mlx-community/Qwen3-4B-Instruct-2507-4bit"
    static let whisperRepository = "argmaxinc/whisperkit-coreml"
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

    /// Completed weight files are this exact size. A shorter file is a cancelled download, not an install.
    static func weightRequirements(for modelName: String) -> [String: Int64] {
        if modelName == compact || modelName.hasSuffix(compact) {
            return [
                "config.json": 1149,
                "AudioEncoder.mlmodelc/weights/weight.bin": 421_968_768,
                "TextDecoder.mlmodelc/weights/weight.bin": 203_199_860,
            ]
        }
        return [
            "config.json": 1149,
            "AudioEncoder.mlmodelc/weights/weight.bin": 1_273_974_400,
            "TextDecoder.mlmodelc/weights/weight.bin": 343_933_748,
        ]
    }

    static func folderName(for modelName: String) -> String {
        modelName.hasPrefix("openai_whisper-") ? modelName : "openai_whisper-\(modelName)"
    }

    static func installedFolder(downloadBase: URL, modelName: String) -> URL {
        downloadBase.appending(
            path: "models/argmaxinc/whisperkit-coreml/\(folderName(for: modelName))",
            directoryHint: .isDirectory
        )
    }

    /// An older Whisper build is still on disk while the build this app expects is not that folder.
    static func hasLegacyInstall(folderNames: [String], currentModelName: String) -> Bool {
        let current = folderName(for: currentModelName)
        return folderNames.contains { name in
            name.hasPrefix("openai_whisper-") && name != current
        }
    }

    static func isInstalled(
        downloadBase: URL,
        modelName: String,
        requirements: [String: Int64]? = nil
    ) -> Bool {
        let folder = installedFolder(downloadBase: downloadBase, modelName: modelName)
        let expected = requirements ?? weightRequirements(for: modelName)
        return expected.allSatisfy { relative, size in
            DownloadByteCount.at(folder.appending(path: relative)) == size
        }
    }
}
