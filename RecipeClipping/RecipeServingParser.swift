import Foundation

/// レシピ本文やJSON-LDの `recipeYield` から「何人分」を抽出する。
/// 材料行の「うどん 2人前」を人数と誤認しないよう、本文では見出し・分量ラベル・
/// 単独行に限定して判定する。
enum RecipeServingParser {
    nonisolated static func extract(from text: String, explicitYield: String? = nil) -> String? {
        if let explicit = normalizedExplicitYield(explicitYield) {
            return explicit
        }

        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for line in lines {
            let lower = line.lowercased()
            let hasServingContext = [
                "材料", "レシピ", "分量", "何人分", "ingredients",
                "serving", "serves", "yield"
            ].contains { lower.contains($0) }
            let isStandaloneServing = line.range(
                of: #"^[\p{So}\p{Sk}\p{P}\s]*"# + japaneseServingPattern + #"[\p{So}\p{Sk}\p{P}\s]*$"#,
                options: .regularExpression
            ) != nil
            guard hasServingContext || isStandaloneServing else { continue }

            if let japanese = firstCapture(pattern: japaneseServingPattern, in: line) {
                return compact(japanese)
            }
            if let english = englishServingCount(in: line) {
                return "\(english)人分"
            }
        }
        return nil
    }

    private nonisolated static func normalizedExplicitYield(_ rawValue: String?) -> String? {
        guard let value = rawValue?
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        if let japanese = firstCapture(pattern: japaneseServingPattern, in: value) {
            return compact(japanese)
        }
        if let english = englishServingCount(in: value) {
            return "\(english)人分"
        }
        if value.range(of: #"^[0-9０-９]+(?:\s*[〜～~\-–—]\s*[0-9０-９]+)?$"#, options: .regularExpression) != nil {
            return "\(compact(value))人分"
        }
        return nil
    }

    private nonisolated static func englishServingCount(in text: String) -> String? {
        firstCapture(
            pattern: #"(?i)(?:serves?|servings?|yield)\s*[:：]?\s*([0-9]+(?:\s*[-–—]\s*[0-9]+)?)"#,
            in: text
        ) ?? firstCapture(
            pattern: #"(?i)([0-9]+(?:\s*[-–—]\s*[0-9]+)?)\s*(?:servings?|serves?)"#,
            in: text
        )
    }

    private nonisolated static var japaneseServingPattern: String {
        #"((?:約\s*)?[0-9０-９]+(?:[./／][0-9０-９]+)?(?:\s*[〜～~\-–—]\s*[0-9０-９]+(?:[./／][0-9０-９]+)?)?\s*(?:人分|人前))"#
    }

    private nonisolated static func compact(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }

    private nonisolated static func firstCapture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: text,
                range: NSRange(text.startIndex..<text.endIndex, in: text)
              ),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }
}
