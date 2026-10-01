import Foundation

struct HuggingFaceFile: Decodable, Sendable {
    let path: String
    let size: Int?
    let type: String
}

/// How an existing local file should be treated before curl starts.
enum DownloadTransferPlan: Equatable, Sendable {
    case alreadyComplete
    case resume
    case fresh

    static func decide(localSize: Int64, expected: Int64) -> DownloadTransferPlan {
        if expected > 0, localSize == expected {
            return .alreadyComplete
        }
        if localSize > 0, expected > localSize {
            return .resume
        }
        return .fresh
    }
}

enum DownloadByteCount {
    /// `URL.resourceValues` caches the first size it sees, so a file that is still downloading stays at 0.
    static func at(_ url: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }
}

enum DirectoryByteCount {
    /// Bytes of regular files under `root` whose path contains `marker`, including unfinished downloads.
    static func at(_ root: URL, containing marker: String) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil
        ) else {
            return 0
        }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard url.path.contains(marker) else { continue }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else { continue }
            total += DownloadByteCount.at(url)
        }
        return total
    }
}

enum ModelByteFormat {
    /// Decimal gigabytes or megabytes, matching the byte total of the files that will be downloaded.
    static func string(from bytes: Int64, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        formatter.roundingMode = .halfUp
        let gigabytes = Double(bytes) / 1_000_000_000
        if gigabytes >= 1 {
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
            let number = formatter.string(from: NSNumber(value: gigabytes)) ?? String(format: "%.2f", gigabytes)
            return "\(number) GB"
        }
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        let megabytes = Double(bytes) / 1_000_000
        let number = formatter.string(from: NSNumber(value: megabytes)) ?? String(format: "%.0f", megabytes)
        return "\(number) MB"
    }
}
enum DownloadStop {
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }
}

/// Lets the settings card stop an in-flight curl without dropping a partial file.
final class DownloadRun: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func reset() {
        lock.lock()
        cancelled = false
        process = nil
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let process = self.process
        lock.unlock()
        guard let process else { return }
        stop(process)
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func begin(_ process: Process) {
        lock.lock()
        self.process = process
        let shouldStop = cancelled
        lock.unlock()
        if shouldStop {
            stop(process)
        }
    }

    func end() {
        lock.lock()
        process = nil
        lock.unlock()
    }

    private func stop(_ process: Process) {
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        if pid > 0 {
            kill(pid, SIGKILL)
        } else {
            process.terminate()
        }
    }
}

enum HuggingFaceDownloader {
    static func list(repository: String, directory: String? = nil) async throws -> [HuggingFaceFile] {
        var address = "https://huggingface.co/api/models/\(repository)/tree/main"
        if let directory, !directory.isEmpty {
            let encoded = directory.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? directory
            address += "/\(encoded)?recursive=1"
        }
        let url = URL(string: address)!
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
        run: DownloadRun,
        onProgress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws {
        let destination = directory.appending(path: file.path)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let expected = Int64(file.size ?? 0)
        let plan = DownloadTransferPlan.decide(localSize: DownloadByteCount.at(destination), expected: expected)
        switch plan {
        case .alreadyComplete:
            onProgress(expected, expected)
            return
        case .fresh:
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
        case .resume:
            break
        }
        if run.isCancelled {
            throw CancellationError()
        }

        let remote = "https://huggingface.co/\(repository)/resolve/main/\(file.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file.path)"
        var arguments = [
            "-sS", "-L", "--fail", "--retry", "30", "--retry-delay", "2", "--retry-all-errors",
            "--speed-limit", "80000", "--speed-time", "25",
        ]
        if plan == .resume {
            arguments += ["-C", "-"]
        }
        arguments += ["-o", destination.path, remote]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        run.begin(process)
        defer { run.end() }
        try process.run()

        while process.isRunning {
            if run.isCancelled || Task.isCancelled {
                run.cancel()
                break
            }
            let size = DownloadByteCount.at(destination)
            onProgress(size, max(expected, size))
            do {
                try await Task.sleep(for: .milliseconds(400))
            } catch is CancellationError {
                run.cancel()
                break
            }
        }
        let completed = DownloadByteCount.at(destination)
        onProgress(completed, max(expected, completed))
        if expected > 0, completed == expected {
            return
        }
        if run.isCancelled {
            throw CancellationError()
        }
        guard process.terminationStatus == 0 else {
            throw DownloadError.failed
        }
        if expected > 0 {
            throw DownloadError.failed
        }
    }
}

enum DownloadError: LocalizedError {
    case failed

    var errorDescription: String? {
        switch self {
        case .failed:
            t(
                "The download did not finish. Check your connection and try again.",
                "Der Download wurde nicht fertig. Prüfe die Verbindung und versuche es erneut."
            )
        }
    }
}
