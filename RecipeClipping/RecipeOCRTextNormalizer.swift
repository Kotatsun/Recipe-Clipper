import Foundation
import CoreGraphics

/// Vision OCR が返す文字片を、レシピ解析に渡せる「見た目どおりの行」へ組み直す。
///
/// `VNRecognizedTextObservation` は同じ表示行でも、材料名・分量・手順番号などを
/// 別々の observation として返すことがある。そのまま改行で連結すると、改行単位で
/// 材料と手順を扱うパーサーへ誤った区切りが渡るため、座標が重なる文字片を先に結合する。
nonisolated struct RecipeOCRTextFragment: Sendable {
    let text: String
    let boundingBox: CGRect
}

enum RecipeOCRTextNormalizer {
    nonisolated static func reconstructedText(from fragments: [RecipeOCRTextFragment]) -> String {
        let cleanedFragments = fragments.compactMap { fragment -> RecipeOCRTextFragment? in
            let text = fragment.text
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return RecipeOCRTextFragment(text: text, boundingBox: fragment.boundingBox)
        }

        var rows: [TextRow] = []
        for fragment in cleanedFragments.sorted(by: readingOrder) {
            if let rowIndex = bestMatchingRow(for: fragment, in: rows) {
                rows[rowIndex].append(fragment)
            } else {
                rows.append(TextRow(fragment: fragment))
            }
        }

        let visualText = rows
            .sorted { lhs, rhs in
                if abs(lhs.centerY - rhs.centerY) > 0.002 {
                    return lhs.centerY > rhs.centerY
                }
                return lhs.minX < rhs.minX
            }
            .map(\.text)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        return normalizedText(visualText)
    }

    /// 「読み取った元の文字」をユーザーが編集して再抽出する場合にも、OCR特有の
    /// 見出し内スペースや不揃いな改行だけを安全に正規化する。
    nonisolated static func normalizedText(_ rawText: String) -> String {
        var text = rawText
            .replacingOccurrences(
                of: #"(?i)材\s*料"#,
                with: "材料",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"作\s*り\s*(?:方|かた)|つ\s*く\s*り\s*方"#,
                with: "作り方",
                options: .regularExpression
            )

        // 既存の本文正規化を通すことで、見出しや行中の手順番号の直前にも改行を補う。
        text = PlainRecipeTextParser.normalizedText(text)

        let lines = text.components(separatedBy: .newlines)
        var result: [String] = []
        var isInsideInstructions = false
        var pendingStepMarker: String?

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                if pendingStepMarker == nil, result.last?.isEmpty == false {
                    result.append("")
                }
                continue
            }

            if isInstructionHeading(line) {
                if let marker = pendingStepMarker {
                    result.append(marker)
                    pendingStepMarker = nil
                }
                isInsideInstructions = true
                result.append(line)
                continue
            }
            if isIngredientHeading(line) {
                if let marker = pendingStepMarker {
                    result.append(marker)
                    pendingStepMarker = nil
                }
                isInsideInstructions = false
                result.append(line)
                continue
            }

            if isInsideInstructions, isStandaloneStepMarker(line) {
                if let pendingStepMarker {
                    result.append(pendingStepMarker)
                }
                pendingStepMarker = line
                continue
            }

            if let marker = pendingStepMarker {
                result.append(joinedStep(marker: marker, body: line))
                pendingStepMarker = nil
            } else {
                result.append(line)
            }
        }

        if let pendingStepMarker {
            result.append(pendingStepMarker)
        }

        return result
            .joined(separator: "\n")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated struct TextRow {
        var fragments: [RecipeOCRTextFragment]
        var minY: CGFloat
        var maxY: CGFloat
        var centerY: CGFloat
        var minX: CGFloat

        init(fragment: RecipeOCRTextFragment) {
            fragments = [fragment]
            minY = fragment.boundingBox.minY
            maxY = fragment.boundingBox.maxY
            centerY = fragment.boundingBox.midY
            minX = fragment.boundingBox.minX
        }

        var height: CGFloat { max(maxY - minY, 0.001) }

        var text: String {
            let sorted = fragments.sorted { lhs, rhs in
                lhs.boundingBox.minX < rhs.boundingBox.minX
            }
            guard var value = sorted.first?.text else { return "" }

            for pair in zip(sorted, sorted.dropFirst()) {
                let previous = pair.0
                let current = pair.1
                let gap = current.boundingBox.minX - previous.boundingBox.maxX
                let compactThreshold = max(0.004, min(previous.boundingBox.height, current.boundingBox.height) * 0.18)
                let separator = needsNoSeparator(after: value, before: current.text) || gap <= compactThreshold ? "" : " "
                value += separator + current.text
            }
            return value
        }

        mutating func append(_ fragment: RecipeOCRTextFragment) {
            let count = CGFloat(fragments.count)
            fragments.append(fragment)
            minY = min(minY, fragment.boundingBox.minY)
            maxY = max(maxY, fragment.boundingBox.maxY)
            minX = min(minX, fragment.boundingBox.minX)
            centerY = ((centerY * count) + fragment.boundingBox.midY) / (count + 1)
        }
    }

    private nonisolated static func readingOrder(_ lhs: RecipeOCRTextFragment, _ rhs: RecipeOCRTextFragment) -> Bool {
        if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) > 0.002 {
            return lhs.boundingBox.midY > rhs.boundingBox.midY
        }
        return lhs.boundingBox.minX < rhs.boundingBox.minX
    }

    private nonisolated static func bestMatchingRow(for fragment: RecipeOCRTextFragment, in rows: [TextRow]) -> Int? {
        rows.indices
            .compactMap { index -> (index: Int, distance: CGFloat)? in
                let row = rows[index]
                let intersection = max(0, min(row.maxY, fragment.boundingBox.maxY) - max(row.minY, fragment.boundingBox.minY))
                let overlapRatio = intersection / max(min(row.height, fragment.boundingBox.height), 0.001)
                let centerDistance = abs(row.centerY - fragment.boundingBox.midY)
                let centerTolerance = max(0.006, min(row.height, fragment.boundingBox.height) * 0.55)
                guard overlapRatio >= 0.42 || centerDistance <= centerTolerance else { return nil }
                return (index, centerDistance)
            }
            .min { $0.distance < $1.distance }?
            .index
    }

    private nonisolated static func needsNoSeparator(after lhs: String, before rhs: String) -> Bool {
        let noSpaceAfter = "（([「『【〈《/／"
        let noSpaceBefore = "、。，．,.!！?？:：;；）)]」』】〉》/／"
        return lhs.last.map(noSpaceAfter.contains) == true || rhs.first.map(noSpaceBefore.contains) == true
    }

    private nonisolated static func isIngredientHeading(_ line: String) -> Bool {
        line.range(
            of: #"^[\p{So}\p{Sk}\p{P}\s]*(?:材料|具材|使うもの|ingredients)(?:[\s:：】》〉\]（(]|$)"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private nonisolated static func isInstructionHeading(_ line: String) -> Bool {
        line.range(
            of: #"^[\p{So}\p{Sk}\p{P}\s]*(?:作り方|手順|instructions|how to)(?:[\s:：】》〉\]（(]|$)"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private nonisolated static func isStandaloneStepMarker(_ line: String) -> Bool {
        line.range(
            of: #"^(?:\(?[0-9０-９]+\)?|（[0-9０-９]+）|【[0-9０-９]+】|\[[0-9０-９]+\]|[①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳❶❷❸❹❺❻❼❽❾❿]|\d\ufe0f?\u20e3|\x{1F51F}|(?i:step)\s*[0-9０-９]+)[\.)）:：．。]?$"#,
            options: .regularExpression
        ) != nil
    }

    private nonisolated static func joinedStep(marker: String, body: String) -> String {
        if marker.range(of: #"^[0-9０-９]+$"#, options: .regularExpression) != nil {
            return "\(marker). \(body)"
        }
        return "\(marker) \(body)"
    }
}
