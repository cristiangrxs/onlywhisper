import Foundation

enum PolishFallback {
    struct Step: Equatable {
        let text: String
        let fellBack: Bool
    }

    /// A polish that fails or comes back empty keeps the words the person already said.
    static func resolve(original: String, result: Result<String, Error>) -> Step {
        switch result {
        case .success(let polished):
            let cleaned = polished.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.isEmpty {
                return Step(text: original, fellBack: true)
            }
            return Step(text: cleaned, fellBack: false)
        case .failure:
            return Step(text: original, fellBack: true)
        }
    }
}
