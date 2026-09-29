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
        let parameters = GenerateParameters(
            maxTokens: max(480, trimmed.count / 2),
            maxKVSize: 4096,
            temperature: 0.2
        )
        let session = ChatSession(container, instructions: kind.system, generateParameters: parameters)
        let reply = try await session.respond(to: String(trimmed.prefix(6000)))
        let cleaned = reply
            .replacingOccurrences(of: "<think>[\\s\\S]*?</think>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? trimmed : cleaned
    }

    /// Loads the model while the user is still speaking, so polishing starts right after release.
    func prewarm() async {
        _ = try? await load()
    }

    func unload() {
        generation += 1
        container = nil
        loading = nil
    }

    /// Concurrent callers share one load. A load that finishes after `unload()` is handed back but not kept.
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
            if generation == started {
                container = loaded
                loading = nil
            }
            return loaded
        } catch {
            if generation == started {
                loading = nil
            }
            throw error
        }
    }
}

enum PolishKind: Sendable {
    case dictation
    case rewrite(String)
    case meeting

    var system: String {
        switch self {
        case .dictation:
            """
            You clean dictated speech into text the person can send. Keep their language. \
            Remove fillers and self-corrections. Apply spoken formatting instructions. \
            Do not add facts. Return only the finished text.
            """
        case .rewrite(let instruction):
            """
            You revise selected text. Follow this instruction: \(instruction) \
            Return only the revised text.
            """
        case .meeting:
            """
            Summarize the transcript in its language. Return JSON with keys \
            summary (string), decisions (array of strings), and tasks (array of strings). \
            Do not add facts that are not in the transcript.
            """
        }
    }
}
