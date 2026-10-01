import Foundation

enum AsyncDeadline {
    struct TimedOut: Error, Equatable, LocalizedError {
        var errorDescription: String? {
            t("This is taking too long.", "Das dauert zu lange.")
        }
    }

    /// Returns the first of `operation` or the deadline. Cancelling the caller cancels the wait.
    static func value<T: Sendable>(
        _ limit: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: limit)
                throw TimedOut()
            }
            do {
                guard let first = try await group.next() else { throw TimedOut() }
                group.cancelAll()
                return first
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }
}

enum ModelDeadline {
    /// First Core ML load after a reinstall can compile for a while.
    static let speechLoad: Duration = .seconds(120)
    static let liveTranscription: Duration = .seconds(45)
    static let finalTranscription: Duration = .seconds(90)
    static let polish: Duration = .seconds(90)
}
