import Foundation

struct HuggingFaceFile: Decodable, Sendable {
    let path: String
    let size: Int?
    let type: String
}

enum HuggingFaceDownloader {
    static func list(repository: String) async throws -> [HuggingFaceFile] {
        let url = URL(string: "https://huggingface.co/api/models/\(repository)/tree/main")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([HuggingFaceFile].self, from: data)
            .filter { $0.type == "file" && $0.path != ".gitattributes" && $0.path != "README.md" }
    }

    static func download(
        repository: String,
        file: HuggingFaceFile,
        to directory: URL,
        onProgress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws {
        let destination = directory.appending(path: file.path)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let expected = Int64(file.size ?? 0)
        if expected > 0, fileSize(destination) == expected {
            onProgress(expected, expected)
            return
        }
        if !FileManager.default.fileExists(atPath: destination.path) {
            FileManager.default.createFile(atPath: destination.path, contents: nil)
        }

        let remote = "https://huggingface.co/\(repository)/resolve/main/\(file.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file.path)"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = [
            "-sS", "-L", "--fail", "--retry", "30", "--retry-delay", "2", "--retry-all-errors",
            "--speed-limit", "80000", "--speed-time", "25",
            "-C", "-", "-o", destination.path, remote
        ]
        let errors = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        try process.run()

        while process.isRunning {
            let size = fileSize(destination)
            onProgress(size, max(expected, size))
            try await Task.sleep(for: .milliseconds(400))
        }
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        let completed = fileSize(destination)
        onProgress(completed, max(expected, completed))
        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw DownloadError.failed(message?.isEmpty == false ? message! : "Download failed (\(process.terminationStatus))")
        }
        if expected > 0, completed != expected {
            throw DownloadError.failed("Downloaded \(completed) of \(expected) bytes")
        }
    }

    private static func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }
}

private enum DownloadError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message): message
        }
    }
}
