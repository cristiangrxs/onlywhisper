import Foundation

enum ModelPaths {
    static var root: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "OnlyWhisper/Models", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var parakeet: URL { root.appending(path: "Parakeet", directoryHint: .isDirectory) }
    static var whisper: URL { root.appending(path: "Whisper", directoryHint: .isDirectory) }
    static var qwen: URL { root.appending(path: "Qwen3-4B-Instruct-2507-4bit", directoryHint: .isDirectory) }
    static var diarization: URL { root.appending(path: "Diarization", directoryHint: .isDirectory) }
    static var readyMarker: URL { root.appending(path: "ready.json") }

    static let qwenRepository = "mlx-community/Qwen3-4B-Instruct-2507-4bit"
    static let whisperModelName = "large-v3-v20240930_turbo"
}
