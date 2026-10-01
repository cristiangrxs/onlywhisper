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
    /// The mel spectrogram is shared by both builds and is required to transcribe without a network call.
    static func weightRequirements(for modelName: String) -> [String: Int64] {
        var requirements: [String: Int64]
        if modelName == compact || modelName.hasSuffix(compact) {
            requirements = [
                "config.json": 1149,
                "AudioEncoder.mlmodelc/weights/weight.bin": 421_968_768,
                "TextDecoder.mlmodelc/weights/weight.bin": 203_199_860,
            ]
        } else {
            requirements = [
                "config.json": 1149,
                "AudioEncoder.mlmodelc/weights/weight.bin": 1_273_974_400,
                "TextDecoder.mlmodelc/weights/weight.bin": 343_933_748,
            ]
        }
        requirements.merge(melRequirements) { _, new in new }
        return requirements
    }

    private static let melRequirements: [String: Int64] = [
        "MelSpectrogram.mlmodelc/weights/weight.bin": 373_376,
        "MelSpectrogram.mlmodelc/model.mil": 10_143,
        "MelSpectrogram.mlmodelc/coremldata.bin": 329,
    ]

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
        return ModelFileSet.isComplete(directory: folder, requirements: expected)
    }
}

/// Exact byte sizes for the files WhisperKit loads as `openai/whisper-large-v3`.
/// They live beside the Core ML weights, under the download base, and are deleted with Whisper.
enum WhisperTokenizerFiles {
    static let repository = "openai/whisper-large-v3"
    static let requirements: [String: Int64] = [
        "tokenizer.json": 2_480_617,
        "tokenizer_config.json": 282_843,
    ]

    /// Matches WhisperKit's hub cache: `downloadBase/models/openai/whisper-large-v3`.
    static func folder(downloadBase: URL) -> URL {
        downloadBase
            .appending(component: "models")
            .appending(component: "openai/whisper-large-v3")
    }

    static func isInstalled(downloadBase: URL) -> Bool {
        ModelFileSet.isComplete(directory: folder(downloadBase: downloadBase), requirements: requirements)
    }
}

/// Qwen is usable only when the weights and the tokenizer are the full files, not empty placeholders.
enum QwenModelFiles {
    static let requirements: [String: Int64] = [
        "config.json": 938,
        "model.safetensors": 2_263_022_417,
        "tokenizer.json": 11_422_654,
        "tokenizer_config.json": 5_440,
    ]

    static func isInstalled(at directory: URL) -> Bool {
        ModelFileSet.isComplete(directory: directory, requirements: requirements)
    }
}

enum ModelFileSet {
    static func isComplete(directory: URL, requirements: [String: Int64]) -> Bool {
        requirements.allSatisfy { relative, size in
            DownloadByteCount.at(directory.appending(path: relative)) == size
        }
    }
}
