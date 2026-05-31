import Foundation

final class PlainRecipeTextParser {
    enum Mode: String {
        case plainText
        case caption
        case description
    }

    nonisolated func parse(_ rawText: String, mode: Mode = .plainText, metadataTitle: String? = nil) -> ExtractedRecipeText {
        let normalized = Self.normalizedText(rawText)
        let lines = Self.lines(from: normalized)

        if Self.isURLOnly(lines) {
            return ExtractedRecipeText(
                title: nil,
                summary: nil,
                ingredients: [],
                instructions: [],
                warnings: ["本文から材料・作り方を抽出できませんでした。"],
                confidence: 0.1,
                rawText: normalized,
                ingredientSource: "none",
                instructionSource: "none"
            )
        }

        let ingredientSection = Self.sectionLines(in: lines, starts: Self.ingredientHeadings, ends: Self.instructionHeadings + Self.sectionEndHeadings)
        let instructionSection = Self.sectionLines(in: lines, starts: Self.instructionHeadings, ends: Self.ingredientHeadings + Self.sectionEndHeadings)
        let foundIngredientHeading = ingredientSection != nil
        let foundInstructionHeading = instructionSection != nil

        let ingredients: [String]
        let ingredientSource: String
        if let ingredientSection {
            ingredients = Self.unique(Self.ingredients(fromSection: ingredientSection))
            ingredientSource = ingredients.isEmpty ? "none" : "plainTextSection"
        } else {
            ingredients = Self.unique(Self.scoredIngredients(from: lines))
            ingredientSource = ingredients.isEmpty ? "none" : "plainTextScored"
        }

        let instructions: [String]
        let instructionSource: String
        if let instructionSection {
            instructions = Self.unique(Self.instructions(fromSection: instructionSection))
            instructionSource = instructions.isEmpty ? "none" : "plainTextSection"
        } else {
            instructions = Self.unique(Self.scoredInstructions(from: lines))
            instructionSource = instructions.isEmpty ? "none" : "plainTextScored"
        }

        var warnings: [String] = []
        if ingredients.isEmpty {
            warnings.append(foundIngredientHeading
                ? "材料見出しは見つかりましたが、材料を抽出できませんでした。PlainRecipeTextParserの確認が必要です。"
                : "材料を自動抽出できませんでした。")
        }
        if instructions.isEmpty {
            warnings.append(foundInstructionHeading
                ? "作り方見出しは見つかりましたが、手順を抽出できませんでした。PlainRecipeTextParserの確認が必要です。"
                : "作り方を自動抽出できませんでした。")
        } else if instructions.count <= 1 {
            warnings.append("作り方の本文が少ないため、保存前に確認してください。")
        }

        var confidence = 0.05
        if !ingredients.isEmpty { confidence += foundIngredientHeading ? 0.35 : 0.2 }
        if !instructions.isEmpty { confidence += foundInstructionHeading ? 0.35 : 0.2 }
        if Self.title(from: lines) != nil || metadataTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            confidence += 0.1
        }

        let title = Self.title(from: lines) ?? RecipeTextExtractor.cleanedTitle(metadataTitle)
        return ExtractedRecipeText(
            title: title,
            summary: Self.summary(from: lines, title: title),
            ingredients: ingredients,
            instructions: instructions,
            warnings: warnings,
            confidence: min(confidence, 1.0),
            rawText: normalized,
            ingredientSource: ingredientSource,
            instructionSource: instructionSource
        )
    }

    nonisolated static func normalizedText(_ rawText: String) -> String {
        var text = htmlDecoded(rawText)
            .replacingOccurrences(of: "\\\\n", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\\\r\\\\n", with: "\n")
            .replacingOccurrences(of: "\\r\\n", with: "\n")
            .replacingOccurrences(of: "\\\\t", with: " ")
            .replacingOccurrences(of: "\\t", with: " ")
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "　", with: " ")
        text = text.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "[\\u{200B}\\u{200C}\\u{200D}]", with: "", options: .regularExpression)
        text = insertLineBreaks(text)
        text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: " *\\n *", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 14695981039346656037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return String(format: "%016llx", hash)
    }

    private nonisolated static func insertLineBreaks(_ text: String) -> String {
        text
            .replacingOccurrences(
                of: #"(?<!^)(?<!\n)(?=\s*[【《〈■#]?\s*(?:材料はこちら|材料はこれ|材料|具材|使うもの|レシピ\s*[\/／]|ingredients)(?:[\s:：】》〉\]]|$|[0-9０-９]))"#,
                with: "\n",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(
                of: #"(?<!^)(?<!\n)(?<!材料・)(?<!材料/)(?<!材料／)(?<!材料と)(?=\s*[【《■#]?\s*(?:作り方|作りかた|つくり方|手順|レシピ|instructions|how to)(?:[\s:：】》\]]|$))"#,
                with: "\n",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(
                of: #"(?<!^)(?<!\n)(?=\s*(?:[①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳❶❷❸❹❺❻❼❽❾❿](?![にをでへと])|\d\ufe0f?\u20e3|[0-9０-９]+[\.)）．。]))"#,
                with: "\n",
                options: .regularExpression
            )
    }

    private nonisolated static func lines(from text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .flatMap(splitDenseLine)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { $0.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression) }
            .filter { !$0.isEmpty }
    }

    private nonisolated static func splitDenseLine(_ line: String) -> [String] {
        line
            .replacingOccurrences(
                of: #"(?<=\S)\s+(?=[・\-*●○◯]\s*)"#,
                with: "\n",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?<=。|！|!|？|\?)\s+(?=(?:[①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳❶❷❸❹❺❻❼❽❾❿](?![にをでへと])|\d\ufe0f?\u20e3|[0-9０-９]+[\.)）．。]))"#,
                with: "\n",
                options: .regularExpression
            )
            .components(separatedBy: .newlines)
    }

    private nonisolated static func sectionLines(in lines: [String], starts: [String], ends: [String]) -> [String]? {
        guard let startIndex = lines.firstIndex(where: { matchesHeading($0, headings: starts) }) else {
            return nil
        }

        var section: [String] = []
        if let remainder = headingRemainder(in: lines[startIndex], headings: starts),
           !remainder.isEmpty,
           !isNoiseLine(remainder),
           !looksLikeServingOnly(remainder) {
            section.append(remainder)
        }
        for line in lines.dropFirst(startIndex + 1) {
            if matchesHeading(line, headings: ends) || isSNSBoundaryLine(line) {
                break
            }
            section.append(line)
        }
        return section
    }

    private nonisolated static func ingredients(fromSection section: [String]) -> [String] {
        var result: [String] = []
        var pendingName: String?
        var reachedInstructionBlock = false

        var index = 0
        while index < section.count {
            let line = section[index]
            let cleaned = stripIngredientMarker(line)
            let stepBody = stripStepMarker(cleaned)
            if startsWithStepMarker(cleaned), containsInstructionVerb(stepBody) {
                reachedInstructionBlock = true
            }
            if reachedInstructionBlock {
                index += 1
                continue
            }
            let isInstructionOnly = looksLikeInstruction(cleaned)
                && !hasQuantityExpression(cleaned)
                && !looksLikeIngredientNameOnly(cleaned)
            guard !cleaned.isEmpty,
                  !isNoiseLine(cleaned),
                  !isIngredientGroupMarker(cleaned),
                  !isInstructionOnly,
                  !isSupplementalLine(cleaned) else {
                index += 1
                continue
            }

            if let pending = pendingName, looksLikeQuantityOnly(cleaned) {
                result.append("\(pending) \(cleaned)")
                pendingName = nil
                index += 1
                continue
            }
            if looksLikeIngredient(cleaned) {
                result.append(cleaned)
                pendingName = nil
            } else if looksLikeIngredientNameOnly(cleaned) {
                let next = section.indices.contains(index + 1) ? stripIngredientMarker(section[index + 1]) : ""
                if looksLikeQuantityOnly(next) {
                    result.append("\(cleaned) \(next)")
                    pendingName = nil
                    index += 2
                    continue
                } else {
                    result.append(cleaned)
                    pendingName = nil
                }
            }
            index += 1
        }

        return result
    }

    private nonisolated static func instructions(fromSection section: [String]) -> [String] {
        let hasExplicitSteps = section.contains { startsWithStepMarker(stripBullet($0)) || isStandaloneStepNumber(stripBullet($0)) }
        var result: [String] = []
        var pendingNumber = false

        for line in section {
            let bulletStripped = stripBullet(line)
            guard !isNoiseLine(bulletStripped), !isSupplementalLine(bulletStripped), !isSNSBoundaryLine(bulletStripped) else {
                continue
            }
            if isStandaloneStepNumber(bulletStripped) {
                pendingNumber = true
                continue
            }

            let hadStepMarker = startsWithStepMarker(bulletStripped)
            let hadBullet = bulletStripped != line.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleaned = bulletStripped
            let markedStepBody = pendingNumber ? cleaned : stripStepMarker(cleaned)
            let markedStepLooksInstruction = (pendingNumber || hadStepMarker) && containsInstructionVerb(markedStepBody)
            guard cleaned.count >= 2,
                  cleaned.count <= 260,
                  (markedStepLooksInstruction || !looksLikeIngredient(cleaned)) else {
                continue
            }

            if pendingNumber || hadStepMarker || hadBullet || !hasExplicitSteps {
                result.append(cleaned)
            } else if !result.isEmpty {
                result[result.count - 1] += " " + cleaned
            }
            pendingNumber = false
        }

        return result
    }

    private nonisolated static func scoredIngredients(from lines: [String]) -> [String] {
        lines.compactMap { line in
            let cleaned = stripIngredientMarker(line)
            let markedStepLooksInstruction = startsWithStepMarker(cleaned)
                && containsInstructionVerb(stripStepMarker(cleaned))
            let isInstructionOnly = looksLikeInstruction(cleaned)
                && !hasQuantityExpression(cleaned)
                && !looksLikeIngredientNameOnly(cleaned)
            guard !isNoiseLine(cleaned),
                  !isSupplementalLine(cleaned),
                  !isIngredientGroupMarker(cleaned),
                  !matchesHeading(cleaned, headings: ingredientHeadings + instructionHeadings),
                  looksLikeIngredient(cleaned),
                  !markedStepLooksInstruction,
                  !isInstructionOnly else {
                return nil
            }
            return cleaned
        }
    }

    private nonisolated static func scoredInstructions(from lines: [String]) -> [String] {
        var result: [String] = []
        var pendingNumber = false
        for line in lines {
            let stripped = stripBullet(line)
            guard !isNoiseLine(stripped),
                  !isSupplementalLine(stripped),
                  !matchesHeading(stripped, headings: ingredientHeadings + instructionHeadings) else {
                continue
            }
            if isStandaloneStepNumber(stripped) {
                pendingNumber = true
                continue
            }
            if pendingNumber || startsWithStepMarker(stripped) || looksLikeInstruction(stripped) {
                let cleaned = stripped
                let markedStep = pendingNumber || startsWithStepMarker(stripped)
                let markedStepBody = pendingNumber ? cleaned : stripStepMarker(cleaned)
                let markedStepLooksInstruction = markedStep && containsInstructionVerb(markedStepBody)
                if cleaned.count >= 2, markedStepLooksInstruction || !looksLikeIngredient(cleaned) {
                    result.append(cleaned)
                    pendingNumber = false
                }
            }
        }
        return result
    }

    private nonisolated static func title(from lines: [String]) -> String? {
        lines.prefix(8)
            .first { line in
                let stripped = stripBullet(line)
                return stripped.count >= 3
                    && stripped.count <= 36
                    && !matchesHeading(stripped, headings: ingredientHeadings + instructionHeadings)
                    && !isNoiseLine(stripped)
                    && !looksLikeIngredient(stripped)
                    && !startsWithStepMarker(stripped)
            }
            .flatMap(RecipeTextExtractor.cleanedTitle)
    }

    private nonisolated static func summary(from lines: [String], title: String?) -> String? {
        lines.first { line in
            line != title
                && line.count >= 18
                && line.count <= 160
                && !matchesHeading(line, headings: ingredientHeadings + instructionHeadings)
                && !isNoiseLine(line)
                && !looksLikeIngredient(line)
                && !looksLikeInstruction(line)
        }
    }

    private nonisolated static func matchesHeading(_ line: String, headings: [String]) -> Bool {
        let normalized = normalizedHeadingLine(line)
        return headings.contains { heading in
            matchesHeadingPrefix(normalized, heading: heading.lowercased())
        }
    }

    private nonisolated static func matchesHeadingPrefix(_ normalized: String, heading: String) -> Bool {
        guard normalized.hasPrefix(heading) else { return false }
        let suffix = String(normalized.dropFirst(heading.count))
        if suffix.isEmpty { return true }
        if suffix.hasPrefix("はこちら") || suffix.hasPrefix("はこれ") {
            return heading != "レシピ"
        }
        guard let first = suffix.first else { return true }
        return first.isWhitespace || [":", "：", "・", "/", "／", "と", "(", "（", "👇", "↓"].contains(first)
    }

    private nonisolated static func normalizedHeadingLine(_ line: String) -> String {
        stripBullet(line)
            .replacingOccurrences(of: #"^[\p{So}\p{Sk}\p{P}\s]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^[【《〈<\[]|[】》〉>\]]$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^[■#]+\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .lowercased()
    }

    private nonisolated static func headingRemainder(in line: String, headings: [String]) -> String? {
        let stripped = stripBullet(line)
            .replacingOccurrences(of: #"^[\p{So}\p{Sk}\p{P}\s]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^[【《〈<\[]|[】》〉>\]]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^[■#]+\s*"#, with: "", options: .regularExpression)
        for heading in headings.sorted(by: { $0.count > $1.count }) {
            let pattern = #"(?i)^\Q"# + NSRegularExpression.escapedPattern(for: heading) + #"\E(?:[】》\]\s:：👇]*|[（\(][^）\)]*[）\)]\s*)*"#
            if let range = stripped.range(of: pattern, options: .regularExpression) {
                return String(stripped[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private nonisolated static func stripIngredientMarker(_ line: String) -> String {
        stripBullet(line)
            .replacingOccurrences(of: #"^[・\-*●○◯]+\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func stripBullet(_ line: String) -> String {
        line.replacingOccurrences(of: #"^[\s・\-*●○◯■□◆◇▶︎▷]+\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func stripStepMarker(_ line: String) -> String {
        stripBullet(line)
            .replacingOccurrences(of: stepMarkerPattern + #"\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func looksLikeIngredient(_ line: String) -> Bool {
        let stripped = stripIngredientMarker(line)
        guard stripped.count >= 2, stripped.count <= 90 else { return false }
        return hasQuantityExpression(stripped)
    }

    private nonisolated static func hasQuantityExpression(_ line: String) -> Bool {
        line.range(
            of: #"([0-9０-９]+(?:[./／][0-9０-９]+)?\s*(?:g|ｇ|グラム|kg|ｋｇ|キロ|ml|ｍｌ|cc|ｃｃ|cm|ｃｍ|l|L|Ｌ|個|こ|本|枚|杯|大さじ|小さじ|パック|缶|袋|束|株|柵|切れ|かけ|片|粒|合)|(?:大さじ|小さじ|大|小)\s*[0-9０-９]+(?:[./／][0-9０-９]+)?|少々|適量|好きな量|ひとつまみ|ひとかけ)"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private nonisolated static func looksLikeIngredientNameOnly(_ line: String) -> Bool {
        let stripped = stripIngredientMarker(line)
        let valueForCheck = startsWithStepMarker(stripped) ? stripStepMarker(stripped) : stripped
        return valueForCheck.count >= 2
            && valueForCheck.count <= 36
            && !hasQuantityExpression(valueForCheck)
            && !looksLikeQuantityOnly(valueForCheck)
            && !looksLikeInstruction(valueForCheck)
            && !isNoiseLine(valueForCheck)
            && !isIngredientGroupMarker(valueForCheck)
    }

    private nonisolated static func looksLikeQuantityOnly(_ line: String) -> Bool {
        stripIngredientMarker(line).range(
            of: #"^(約)?[0-9０-９]+(?:[./／][0-9０-９]+)?\s*(?:g|ｇ|グラム|kg|ｋｇ|キロ|ml|ｍｌ|cc|ｃｃ|cm|ｃｍ|l|L|Ｌ|個|こ|本|枚|杯|大さじ|小さじ|パック|缶|袋|束|株|柵|切れ|かけ|片|粒|合)$|^(少々|適量|好きな量|ひとつまみ|ひとかけ)$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private nonisolated static func looksLikeInstruction(_ line: String) -> Bool {
        if startsWithStepMarker(stripBullet(line)) { return true }
        let stripped = stripBullet(line)
        guard stripped.count >= 7, stripped.count <= 240, !hasQuantityExpression(stripped) else { return false }
        return containsInstructionVerb(stripped)
    }

    private nonisolated static func containsInstructionVerb(_ line: String) -> Bool {
        let stripped = stripBullet(line)
        let verbs = ["切る", "切り", "焼く", "炒め", "煮", "混ぜ", "加え", "入れ", "置く", "取り出", "茹で", "ゆで", "温め", "冷ま", "冷や", "盛り", "かけ", "和え", "揚げ", "蒸し", "流す", "整え", "溶かす", "作る", "する", "泡立て", "重ね", "ふる", "こし", "仕上げ", "つけ", "加熱", "のせ", "からめ", "完成"]
        return verbs.contains { stripped.contains($0) }
    }

    private nonisolated static func isStandaloneStepNumber(_ line: String) -> Bool {
        stripBullet(line).range(of: #"^(?:\(?[0-9０-９]+\)?|（[0-9０-９]+）|[①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳❶❷❸❹❺❻❼❽❾❿]|\d\ufe0f?\u20e3)[\.)）．。]?$"#, options: .regularExpression) != nil
    }

    private nonisolated static func startsWithStepMarker(_ line: String) -> Bool {
        stripBullet(line).range(of: stepMarkerPattern, options: .regularExpression) != nil
    }

    private nonisolated static var stepMarkerPattern: String {
        #"^(?:\([0-9０-９]+\)|（[0-9０-９]+）|[0-9０-９]+[\.)）．。]|[①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳❶❷❸❹❺❻❼❽❾❿]|\d\ufe0f?\u20e3)\s*"#
    }

    private nonisolated static func isNoiseLine(_ line: String) -> Bool {
        let stripped = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = stripped.lowercased()
        if lower.range(of: #"https?://|www\.|youtu\.be"#, options: .regularExpression) != nil { return true }
        if stripped.range(of: #"^([#＃][^\s#＃]+[\s　]*)+$"#, options: .regularExpression) != nil { return true }
        if stripped.range(of: #"^(@[A-Za-z0-9_.]+[\s　]*)+$"#, options: .regularExpression) != nil { return true }
        let noiseTokens = [
            "保存してね", "保存して", "作ってみてね", "フォロー", "チャンネル登録", "高評価",
            "コメント", "詳しくは動画", "詳しくはプロフィール", "プロフィールリンク", "概要欄",
            "pr", "提供", "広告", "タイアップ", "recipe by", "instagram", "youtube"
        ]
        return noiseTokens.contains { lower.contains($0) }
    }

    private nonisolated static func isSupplementalLine(_ line: String) -> Bool {
        let stripped = stripBullet(line)
        return stripped.range(of: #"^(Point|ポイント|コツ|保存|メモ|Memo)(?:$|[\s:：])"#, options: [.regularExpression, .caseInsensitive]) != nil
            || stripped.hasPrefix("#")
            || stripped.hasPrefix("＃")
    }

    private nonisolated static func isIngredientGroupMarker(_ line: String) -> Bool {
        stripIngredientMarker(line).range(
            of: #"^(?:[A-Za-zＡ-Ｚａ-ｚ]|[A-Za-zＡ-Ｚａ-ｚ][\.)）．。]|[【\[\(（]?[A-Za-zＡ-Ｚａ-ｚ][】\]\)）]?)$"#,
            options: .regularExpression
        ) != nil
    }

    private nonisolated static func isSNSBoundaryLine(_ line: String) -> Bool {
        let stripped = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.hasPrefix("#")
            || stripped.hasPrefix("＃")
            || stripped.hasPrefix("@")
            || stripped.lowercased().contains("チャンネル登録")
            || stripped.lowercased().contains("保存して")
            || stripped.lowercased().contains("詳しくは動画")
    }

    private nonisolated static func looksLikeServingOnly(_ line: String) -> Bool {
        let stripped = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.range(of: #"^[\(（]?[0-9０-９]+人分[\)）]?$|^分量$"#, options: .regularExpression) != nil
    }

    private nonisolated static func isURLOnly(_ lines: [String]) -> Bool {
        guard lines.count == 1, let line = lines.first else { return false }
        return URL(string: line)?.scheme?.hasPrefix("http") == true
    }

    private nonisolated static func unique(_ lines: [String]) -> [String] {
        var seen: Set<String> = []
        return lines.filter { line in
            let key = line.lowercased()
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private nonisolated static func htmlDecoded(_ text: String) -> String {
        var result = text
        let named = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'"
        ]
        for (source, destination) in named {
            result = result.replacingOccurrences(of: source, with: destination)
        }
        result = result.replacingOccurrences(of: #"&#(\d+);"#, with: { match in
            guard let value = UInt32(match), let scalar = UnicodeScalar(value) else { return "" }
            return String(scalar)
        })
        result = result.replacingOccurrences(of: #"&#x([0-9a-fA-F]+);"#, with: { match in
            guard let value = UInt32(match, radix: 16), let scalar = UnicodeScalar(value) else { return "" }
            return String(scalar)
        })
        return result
    }

    private nonisolated static let ingredientHeadings = [
        "材料・作り方", "材料/作り方", "材料と作り方", "材料はこちら", "材料", "具材", "使うもの", "用意するもの", "レシピ", "ingredients", "ingredient"
    ]

    private nonisolated static let instructionHeadings = [
        "作り方", "作りかた", "つくり方", "手順", "レシピ", "instructions", "instruction", "how to", "directions", "method"
    ]

    private nonisolated static let sectionEndHeadings = [
        "ポイント", "point", "コツ", "保存", "memo", "notes", "note"
    ]
}

private extension String {
    nonisolated func replacingOccurrences(
        of pattern: String,
        with transform: (String) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return self
        }
        let nsRange = NSRange(startIndex..<endIndex, in: self)
        var result = self
        for match in regex.matches(in: self, range: nsRange).reversed() {
            guard match.numberOfRanges > 1,
                  let fullRange = Range(match.range(at: 0), in: result),
                  let captureRange = Range(match.range(at: 1), in: self) else {
                continue
            }
            result.replaceSubrange(fullRange, with: transform(String(self[captureRange])))
        }
        return result
    }
}
