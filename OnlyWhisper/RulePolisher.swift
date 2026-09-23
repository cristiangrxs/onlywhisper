import Foundation

enum RulePolisher {
    private static let fillers = [
        "äh", "ähm", "ähem", "hm", "hmm", "uh", "um", "er", "ähh", "uhm"
    ]

    static func apply(_ text: String) -> String {
        var result = text
        result = applySelfCorrections(result)
        result = removeFillers(result)
        result = collapseWhitespace(result)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func applySelfCorrections(_ text: String) -> String {
        var result = text
        let patterns = [
            #"\bnicht\s+[^,.]{1,60}?,?\s*sondern\s+"#,
            #"\b[^,.!?]{1,80}?,\s*(?:nein|nee|no|sorry|actually|wait|doch)\s+"#
        ]
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            var previous = ""
            while previous != result {
                previous = result
                let range = NSRange(result.startIndex..<result.endIndex, in: result)
                result = expression.stringByReplacingMatches(in: result, range: range, withTemplate: "")
            }
        }
        return result
    }

    private static func removeFillers(_ text: String) -> String {
        var result = text
        for filler in fillers {
            let pattern = "(?i)\\b\(NSRegularExpression.escapedPattern(for: filler))\\b[,.]?"
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = expression.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }
        return result
    }

    private static func collapseWhitespace(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+([,.;:!?])"#, with: "$1", options: .regularExpression)
    }
}
