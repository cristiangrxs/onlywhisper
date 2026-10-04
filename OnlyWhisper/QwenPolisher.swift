import Foundation
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

actor QwenPolisher {
    private var container: ModelContainer?
    private var loading: Task<ModelContainer, Error>?
    private var generation = 0

    func polish(raw: String, kind: PolishKind) async throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        let container = try await load()
        let excerpt = String(trimmed.prefix(6000))
        let parameters = GenerateParameters(
            maxTokens: Self.tokenBudget(for: excerpt, kind: kind),
            maxKVSize: 4096,
            temperature: 0.2
        )
        let session = ChatSession(container, instructions: kind.system, generateParameters: parameters)
        let reply = try await session.respond(to: kind.userContent(for: excerpt))
        let cleaned = reply
            .replacingOccurrences(of: "<think>[\\s\\S]*?</think>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? trimmed : cleaned
    }

    /// Translation needs room for a longer target language. Other passes stay short so they do not ramble.
    static func tokenBudget(for text: String, kind: PolishKind) -> Int {
        switch kind {
        case .dictationTranslate:
            return min(2048, max(640, text.count))
        case .dictation, .rewrite, .meeting:
            return max(480, text.count / 2)
        }
    }

    /// Loads the model while the user is still speaking, so polishing starts right after release.
    func prewarm() async {
        _ = try? await load()
    }

    func unload() {
        generation += 1
        container = nil
        loading?.cancel()
        loading = nil
    }

    /// Concurrent callers share one load. A load that finishes after `unload()` is dropped.
    private func load() async throws -> ModelContainer {
        if let container { return container }
        let task: Task<ModelContainer, Error>
        if let loading {
            task = loading
        } else {
            task = Task {
                try await LLMModelFactory.shared.loadContainer(
                    from: ModelPaths.qwen,
                    using: #huggingFaceTokenizerLoader()
                )
            }
            loading = task
        }
        let started = generation
        do {
            let loaded = try await task.value
            guard ModelLoadGuard.keeps(started: started, current: generation) else {
                throw CancellationError()
            }
            container = loaded
            loading = nil
            return loaded
        } catch {
            if ModelLoadGuard.keeps(started: started, current: generation) {
                loading = nil
            }
            throw error
        }
    }
}

enum PolishKind: Sendable {
    case dictation
    /// `keepExisting` allows text that is already in `target` to stay. A known other source language never takes that path.
    case dictationTranslate(target: String, polish: Bool, keepExisting: Bool)
    case rewrite(String)
    /// Nil keeps the summary in the transcript's language.
    case meeting(String?)

    var system: String {
        switch self {
        case .dictation:
            return """
            You clean dictated speech into text the person can send. Keep their language. \
            Remove fillers and self-corrections. Apply spoken formatting instructions. \
            Do not add facts. Return only the finished text.
            """
        case .dictationTranslate(let target, let polish, let keepExisting):
            return Self.translationInstructions(target: target, polish: polish, keepExisting: keepExisting)
        case .rewrite(let instruction):
            return """
            You revise selected text. Follow this instruction: \(instruction) \
            Return only the revised text.
            """
        case .meeting(let target):
            let language = target.map { "in \($0)" } ?? "in its language"
            return """
            Summarize the transcript \(language). Return JSON with keys \
            summary (string), decisions (array of strings), and tasks (array of strings). \
            Do not add facts that are not in the transcript.
            """
        }
    }

    /// The user turn names the target language. A 4B model follows that more reliably than a system prompt alone.
    func userContent(for text: String) -> String {
        switch self {
        case .dictation, .meeting:
            return text
        case .dictationTranslate(let target, let polish, _):
            let action = polish ? "Clean and translate into" : "Translate into"
            return """
            \(action) \(target). Write only in \(target).

            \(text)
            """
        case .rewrite(let instruction):
            return """
            \(instruction)

            \(text)
            """
        }
    }

    private static func translationInstructions(target: String, polish: Bool, keepExisting: Bool) -> String {
        if polish, keepExisting {
            return """
            Clean the dictated speech and translate it into \(target). \
            Remove fillers and self-corrections. Apply spoken formatting instructions. \
            If the text is already entirely in \(target), return it cleaned without translating. \
            Do not answer in any other language. \
            Do not add facts. Return only the finished text.
            """
        }
        if polish {
            return """
            Clean the dictated speech and translate it into \(target). \
            The source is not \(target). Always translate it into \(target). \
            Remove fillers and self-corrections. Apply spoken formatting instructions. \
            Do not answer in the source language. \
            Do not add facts. Return only the finished text.
            """
        }
        if keepExisting {
            return """
            Translate the dictated speech into \(target). \
            If the text is already entirely in \(target), return it unchanged. \
            Do not answer in any other language. \
            Do not add facts. Return only the translation.
            """
        }
        return """
        Translate the dictated speech into \(target). \
        The source is not \(target). Always translate it into \(target). \
        Do not answer in the source language. \
        Do not add facts. Return only the translation.
        """
    }
}
