import Foundation

struct ExtractedRecipeText {
    var title: String?
    var summary: String?
    var ingredients: [String]
    var instructions: [String]
    var warnings: [String]
    var confidence: Double
    var rawText: String
    var ingredientSource: String
    var instructionSource: String
}

struct RecipeMetadata {
    var title: String?
    var description: String?
    var ogTitle: String?
    var ogDescription: String?
    var twitterTitle: String?
    var twitterDescription: String?

    init(
        title: String? = nil,
        description: String? = nil,
        ogTitle: String? = nil,
        ogDescription: String? = nil,
        twitterTitle: String? = nil,
        twitterDescription: String? = nil
    ) {
        self.title = title
        self.description = description
        self.ogTitle = ogTitle
        self.ogDescription = ogDescription
        self.twitterTitle = twitterTitle
        self.twitterDescription = twitterDescription
    }
}

struct JSONLDRecipe {
    var title: String?
    var description: String?
    var imageURL: URL?
    var ingredients: [String]
    var instructions: [String]
}

struct RecipeTextExtractorInput {
    var html: String
    var visibleText: String
    var metadata: RecipeMetadata
    var jsonLDRecipes: [JSONLDRecipe]

    init(
        html: String = "",
        visibleText: String = "",
        metadata: RecipeMetadata = RecipeMetadata(),
        jsonLDRecipes: [JSONLDRecipe] = []
    ) {
        self.html = html
        self.visibleText = visibleText
        self.metadata = metadata
        self.jsonLDRecipes = jsonLDRecipes
    }
}

final class RecipeTextExtractor {
    nonisolated func extract(from input: RecipeTextExtractorInput) -> ExtractedRecipeText {
        let recipe = Self.bestJSONLDRecipe(from: input.jsonLDRecipes)
        let metadataTitle = Self.firstNonEmpty([
            recipe?.title,
            input.metadata.ogTitle,
            input.metadata.twitterTitle,
            input.metadata.title,
            Self.h1(fromHTML: input.html)
        ])
        let text = Self.extractorInputText(for: input)
        var extracted = extract(from: text, metadataTitle: metadataTitle)

        if let title = Self.cleanedTitle(metadataTitle) {
            extracted.title = title
        }
        if let summary = Self.firstNonEmpty([
            recipe?.description,
            input.metadata.ogDescription,
            input.metadata.twitterDescription,
            input.metadata.description,
            extracted.summary
        ]) {
            extracted.summary = summary
        }

        if let recipe, !recipe.ingredients.isEmpty {
            extracted.ingredients = Self.cleanedJSONLDLines(recipe.ingredients)
            extracted.ingredientSource = "jsonld"
        }
        if let recipe, !recipe.instructions.isEmpty {
            extracted.instructions = Self.cleanedJSONLDLines(recipe.instructions)
            extracted.instructionSource = "jsonld"
        }

        extracted.warnings.removeAll()
        if Self.isVerificationPage(Self.cleanedLines(from: text)) {
            extracted.ingredients = []
            extracted.instructions = []
            extracted.ingredientSource = "none"
            extracted.instructionSource = "none"
            extracted.confidence = min(extracted.confidence, 0.1)
            extracted.warnings.append("bot verificationまたはaccess deniedページのためレシピ本文を抽出できませんでした。")
        } else {
            if extracted.ingredients.isEmpty {
                extracted.warnings.append("材料を自動抽出できませんでした。")
            }
            if extracted.instructions.isEmpty {
                extracted.warnings.append("作り方を自動抽出できませんでした。")
            } else if extracted.instructions.count <= 1 {
                extracted.warnings.append("作り方の本文が少ないため、保存前に確認してください。")
            }
            if input.html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               input.visibleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                extracted.warnings.append("ページ本文を取得できませんでした。必要に応じて手動で入力してください。")
            }
            if extracted.ingredientSource == "jsonld" { extracted.confidence += 0.2 }
            if extracted.instructionSource == "jsonld" { extracted.confidence += 0.2 }
            extracted.confidence = min(extracted.confidence, 1.0)
        }

        return extracted
    }

    nonisolated static func extractorInputText(for input: RecipeTextExtractorInput) -> String {
        input.visibleText.isEmpty ? input.html : input.visibleText
    }

    nonisolated func extract(from rawText: String, metadataTitle: String? = nil) -> ExtractedRecipeText {
        let cleanedText = Self.cleanedText(rawText)
        let extractionText = Self.preprocessedTextForExtraction(cleanedText)
        let lines = Self.cleanedLines(from: extractionText)
        if Self.isURLOnly(lines) {
            return ExtractedRecipeText(
                title: nil,
                summary: nil,
                ingredients: [],
                instructions: [],
                warnings: ["caption本文を抽出できませんでした。材料・作り方は手動で入力してください。"],
                confidence: 0.1,
                rawText: extractionText,
                ingredientSource: "none",
                instructionSource: "none"
            )
        }
        if Self.isVerificationPage(lines) {
            return ExtractedRecipeText(
                title: Self.cleanedTitle(metadataTitle),
                summary: nil,
                ingredients: [],
                instructions: [],
                warnings: ["bot verificationページのためレシピ本文を抽出できませんでした。"],
                confidence: 0.1,
                rawText: extractionText,
                ingredientSource: "none",
                instructionSource: "none"
            )
        }

        let title = Self.cleanedTitle(metadataTitle) ?? Self.titleFromLeadingLine(lines)

        var warnings: [String] = []
        let ingredientResult = extractIngredients(from: lines)
        let instructionResult = extractInstructions(from: lines)

        if ingredientResult.lines.isEmpty {
            warnings.append("材料を自動抽出できませんでした。")
        }
        if instructionResult.lines.isEmpty {
            if instructionResult.foundHeading {
                warnings.append("作り方の見出しは見つかりましたが、HTML本文中に手順テキストが見つかりませんでした。画像内に手順が含まれている可能性があります。")
            } else {
                warnings.append("作り方を自動抽出できませんでした。")
            }
        } else if instructionResult.lines.count <= 1 {
            warnings.append("作り方の本文が少ないため、保存前に確認してください。")
        }

        let summary = Self.summary(from: lines, title: title)
        var confidence = 0.05
        if title != nil { confidence += 0.15 }
        if !ingredientResult.lines.isEmpty { confidence += ingredientResult.source == "section" ? 0.25 : 0.15 }
        if !instructionResult.lines.isEmpty { confidence += instructionResult.source == "section" ? 0.25 : 0.15 }

        return ExtractedRecipeText(
            title: title,
            summary: summary,
            ingredients: ingredientResult.lines,
            instructions: instructionResult.lines,
            warnings: warnings,
            confidence: min(confidence, 1.0),
            rawText: extractionText,
            ingredientSource: ingredientResult.lines.isEmpty ? "none" : "text",
            instructionSource: instructionResult.lines.isEmpty ? "none" : "text"
        )
    }

    nonisolated static func cleanedTitle(_ rawTitle: String?) -> String? {
        guard var title = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            return nil
        }

        for separator in ["｜", "|", " - ", " – ", " — "] {
            if let first = title.components(separatedBy: separator).first, first.count >= 2 {
                title = first
            }
        }

        let removals = ["Instagram", "Cookpad", "レシピ", "作り方"]
        for removal in removals {
            title = title.replacingOccurrences(of: removal, with: "", options: [.caseInsensitive])
        }
        title = title.replacingOccurrences(of: "クックパッド", with: "", options: [.caseInsensitive])
        title = title.replacingOccurrences(of: "YouTube", with: "", options: [.caseInsensitive])
        title = title.replacingOccurrences(of: "大公開", with: "")
        title = title.replacingOccurrences(of: "いかが？", with: "")
        title = title.replacingOccurrences(of: "\\bby\\s+.+$", with: "", options: [.regularExpression, .caseInsensitive])
        if let quoted = title.firstCapture(pattern: "[「\"]([^」\"]{3,24})[」\"]") {
            title = quoted
        }
        title = title.replacingOccurrences(of: "(の)?\\s*$", with: "", options: .regularExpression)
        title = title.replacingOccurrences(of: "[🍅🍳🥘🍰🍮🍞✨🔥]+", with: "", options: .regularExpression)
        title = title.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        return title.isEmpty ? nil : title
    }

    private nonisolated func extractIngredients(from lines: [String]) -> (lines: [String], source: String) {
        if let section = sectionLines(in: lines, starts: Self.ingredientHeadings, ends: Self.ingredientEndHeadings) {
            let cleaned = Self.unique(Self.normalizedIngredientLines(from: section))
            if !cleaned.isEmpty {
                return (cleaned, "section")
            }
        }

        return ([], "none")
    }

    private nonisolated func extractInstructions(from lines: [String]) -> (lines: [String], source: String, foundHeading: Bool) {
        if let section = sectionLines(in: lines, starts: Self.instructionHeadings, ends: Self.instructionEndHeadings) {
            let cleaned = Self.instructionsFromSection(section)
            if !cleaned.isEmpty {
                return (cleaned, "section", true)
            }
            return ([], "section", true)
        }

        return ([], "none", false)
    }

    private nonisolated func sectionLines(in lines: [String], starts: [String], ends: [String]) -> [String]? {
        guard let startIndex = lines.firstIndex(where: { Self.matchesHeading($0, headings: starts) }) else {
            return nil
        }

        var section: [String] = []
        if let remainder = Self.headingRemainder(in: lines[startIndex], headings: starts),
           !remainder.isEmpty,
           !Self.isNoiseLine(remainder) {
            section.append(remainder)
        }
        for line in lines.dropFirst(startIndex + 1) {
            if Self.matchesHeading(line, headings: ends) {
                break
            }
            section.append(line)
        }
        return section
    }

    private nonisolated static func cleanedText(_ text: String) -> String {
        var cleaned = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "　", with: " ")
            .replacingOccurrences(of: "\\\\n", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\\\t", with: " ")
            .replacingOccurrences(of: "\\t", with: " ")
        cleaned = cleaned.replacingOccurrences(of: "(?s)<!--.*?-->", with: "\n", options: .regularExpression)
        if cleaned.range(of: "<html|<body|<p\\b|<div\\b|<h\\d\\b", options: [.regularExpression, .caseInsensitive]) != nil {
            cleaned = Self.visibleText(fromHTML: cleaned)
        }
        return cleaned
    }

    private nonisolated static func preprocessedTextForExtraction(_ text: String) -> String {
        var cleaned = text
        let removablePatterns = [
            #"!\[[^\]]*\]\([^\)]*\)"#,
            #"(?i)\balt\s*=\s*["'][^"']*["']"#,
            #"(?i)\b(?:image|画像)\b[:：]?\s*"#,
            #"https?://\S+"#,
            #"www\.\S+"#,
            #"(?i)\b(?:share|follow|subscribe)\b\s*[:：]?"#
        ]
        for pattern in removablePatterns {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        cleaned = cleaned.replacingOccurrences(
            of: #"(?<!^)(?<!\n)(?=\s*(?:材料|具材|ingredients)(?:[\s:：\(（]|$))"#,
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"(?<!^)(?<!\n)(?<!の)(?=\s*(?:作り方|作りかた|つくり方|手順|instructions|directions|method)(?:[\s:：\(（]|$))"#,
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"(?<!^)(?<!\n)(?=\s*(?:\([0-9０-９]+\)|（[0-9０-９]+）|[①②③④⑤⑥⑦⑧⑨⑩])\s*(?![にをでへと]))"#,
            with: "\n",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"(?<!^)(?<!\n)(?<![\(（])(?=\s*[0-9０-９]+[\.)）．。]\s*(?![にをでへと]))"#,
            with: "\n",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func visibleText(fromHTML html: String) -> String {
        visibleText(fromHTMLContent: html)
    }

    private nonisolated static func cleanedLines(from text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .flatMap { splitDenseLine($0) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { $0.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression) }
            .filter { !$0.isEmpty }
            .filter { !isNoiseLine($0) }
    }

    private nonisolated static func visibleText(fromHTMLContent html: String) -> String {
        var text = html
        let removablePatterns = [
            "<script\\b[^>]*>.*?</script>",
            "<style\\b[^>]*>.*?</style>",
            "<noscript\\b[^>]*>.*?</noscript>",
            "<svg\\b[^>]*>.*?</svg>",
            "<nav\\b[^>]*>.*?</nav>",
            "<footer\\b[^>]*>.*?</footer>"
        ]
        for pattern in removablePatterns {
            text = text.replacingOccurrences(of: pattern, with: "\n", options: [.regularExpression, .caseInsensitive])
        }
        text = text.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "</(p|div|li|h1|h2|h3|h4|section|article|tr|dt|dd)>", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        text = Self.htmlDecoded(text)
        text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func h1(fromHTML html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "<h1\\b[^>]*>(.*?)</h1>", options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              match.numberOfRanges > 1,
              let swiftRange = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return htmlDecoded(String(html[swiftRange]).replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression))
    }

    private nonisolated static func bestJSONLDRecipe(from recipes: [JSONLDRecipe]) -> JSONLDRecipe? {
        recipes.max { lhs, rhs in
            score(lhs) < score(rhs)
        }
    }

    private nonisolated static func score(_ recipe: JSONLDRecipe) -> Int {
        var score = 0
        if recipe.title?.isEmpty == false { score += 2 }
        if recipe.description?.isEmpty == false { score += 1 }
        score += min(recipe.ingredients.count, 20) * 3
        score += min(recipe.instructions.count, 20) * 3
        return score
    }

    private nonisolated static func cleanedJSONLDLines(_ lines: [String]) -> [String] {
        unique(lines
            .flatMap { $0.components(separatedBy: .newlines) }
            .map { htmlDecoded($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !isNoiseLine($0) })
    }

    private nonisolated static func firstNonEmpty(_ values: [String?]) -> String? {
        values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private nonisolated static func splitDenseLine(_ line: String) -> [String] {
        let withStepBreaks = line
            .replacingOccurrences(of: "(?=\\s(?:\\d+[\\.)）．。]\\s*(?![にをでへと])|STEP\\s*\\d+|Step\\s*\\d+|[①②③④⑤⑥⑦⑧⑨⑩]))", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "(?=(?:^|\\s)(?:\\([0-9０-９]+\\)|（[0-9０-９]+）)\\s*(?![にをでへと]))", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "([。.!?])\\s+", with: "$1\n", options: .regularExpression)
        return withStepBreaks.components(separatedBy: .newlines)
    }

    private nonisolated static func titleFromLeadingLine(_ lines: [String]) -> String? {
        lines.prefix(8)
            .first { line in
                let count = line.count
                return count >= 3
                    && count <= 36
                    && URL(string: line)?.scheme == nil
                    && !matchesHeading(line, headings: ingredientHeadings + instructionHeadings)
            }
            .flatMap(cleanedTitle)
    }

    private nonisolated static func summary(from lines: [String], title: String?) -> String? {
        lines.first { line in
            line != title
                && line.count >= 18
                && line.count <= 160
                && !looksLikeIngredient(line)
                && !looksLikeInstruction(line)
                && !matchesHeading(line, headings: ingredientHeadings + instructionHeadings)
        }
    }

    private nonisolated static func cleanedIngredientLine(_ line: String) -> String? {
        let cleaned = stripLeadingMarker(line)
        guard cleaned.count >= 2, cleaned.count <= 80, !isNoiseLine(cleaned) else { return nil }
        guard looksLikeIngredient(cleaned) || !looksLikeInstruction(cleaned) else { return nil }
        return cleaned
    }

    private nonisolated static func normalizedIngredientLines(from lines: [String]) -> [String] {
        let cleaned = lines.compactMap { line -> String? in
            let value = stripLeadingMarker(line)
            guard value.count >= 2,
                  value.count <= 80,
                  !isNoiseLine(value),
                  (!looksLikeInstruction(value) || hasQuantityExpression(value)) else {
                return nil
            }
            return value
        }

        var result: [String] = []
        var index = 0
        while index < cleaned.count {
            let line = cleaned[index]
            if index + 1 < cleaned.count,
               looksLikeIngredientNameOnly(line),
               looksLikeQuantityOnly(cleaned[index + 1]) {
                result.append("\(line) \(cleaned[index + 1])")
                index += 2
            } else if looksLikeIngredient(line) {
                result.append(line)
                index += 1
            } else {
                index += 1
            }
        }
        return result
    }

    private nonisolated static func cleanedInstructionLine(_ line: String) -> String? {
        if isSupplementalInstructionLine(line) {
            return nil
        }
        var cleaned = stripLeadingMarker(line)
        let hadExplicitMarker = startsWithStepMarker(cleaned)
        if isSupplementalInstructionLine(cleaned) {
            return nil
        }
        if isStandaloneStepNumber(cleaned) {
            return nil
        }
        cleaned = cleaned.replacingOccurrences(
            of: "^(STEP|Step|step)\\s*\\d+\\s*[:：\\.)-]?\\s*",
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: "^(\\([0-9０-９]+\\)|（[0-9０-９]+）|[0-9０-９]+[\\.)）、．。]?|[①②③④⑤⑥⑦⑧⑨⑩])[\\.)）、．。\\s]*",
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        let minimumCount = hadExplicitMarker ? 2 : 5
        guard cleaned.count >= minimumCount, cleaned.count <= 260, !isNoiseLine(cleaned) else { return nil }
        return cleaned
    }

    private nonisolated static func headingRemainder(in line: String, headings: [String]) -> String? {
        let stripped = stripLeadingMarker(line)
        let sortedHeadings = headings.sorted { $0.count > $1.count }
        for heading in sortedHeadings {
            let pattern = #"^\Q"# + NSRegularExpression.escapedPattern(for: heading) + #"\E(?:[【】\[\]「」:：\s]*|[（\(][^）\)]*[）\)]\s*)*"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(stripped.startIndex..<stripped.endIndex, in: stripped)
            guard let match = regex.firstMatch(in: stripped, range: range),
                  match.range.location == 0,
                  let swiftRange = Range(match.range, in: stripped) else {
                continue
            }
            return String(stripped[swiftRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private nonisolated static func stripLeadingMarker(_ line: String) -> String {
        line.replacingOccurrences(of: "^[\\s・\\-\\*●○◯■□◆◇▶︎▷]+", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func isSupplementalInstructionLine(_ line: String) -> Bool {
        let stripped = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if stripped.hasPrefix("▶︎") || stripped.hasPrefix("▷") {
            return true
        }
        let markerStripped = stripLeadingMarker(stripped)
        return markerStripped.range(of: "^(Point|ポイント)($|[\\s:：])", options: [.regularExpression, .caseInsensitive]) != nil
    }

    private nonisolated static func looksLikeIngredient(_ line: String) -> Bool {
        let stripped = stripLeadingMarker(line)
        if line.range(of: "^[\\s・\\-\\*●○◯]", options: .regularExpression) != nil && stripped.count <= 80 {
            return true
        }
        if hasQuantityExpression(stripped), stripped.count <= 80 {
            return true
        }
        return false
    }

    private nonisolated static func hasQuantityExpression(_ line: String) -> Bool {
        line.range(
            of: "([0-9０-９./]+\\s*(g|kg|ml|cc|l|L|大さじ|小さじ|カップ|個|本|枚|束|株|缶|袋|杯|片|粒|切れ|かけ|合|分|度|W)|大さじ\\s*[0-9０-９./]+|小さじ\\s*[0-9０-９./]+|少々|適量)",
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private nonisolated static func looksLikeIngredientNameOnly(_ line: String) -> Bool {
        let stripped = stripLeadingMarker(line)
        guard stripped.count >= 2, stripped.count <= 40 else { return false }
        return stripped.range(of: "\\d", options: .regularExpression) == nil
            && !looksLikeQuantityOnly(stripped)
            && !looksLikeInstruction(stripped)
            && !matchesHeading(stripped, headings: ingredientHeadings + instructionHeadings)
    }

    private nonisolated static func looksLikeQuantityOnly(_ line: String) -> Bool {
        let stripped = stripLeadingMarker(line)
        guard stripped.count <= 24 else { return false }
        return stripped.range(
            of: "^(約)?[0-9０-９./]+\\s*(g|kg|ml|cc|l|L|大さじ|小さじ|カップ|個|本|枚|束|少々|適量|切れ|片|粒|缶|袋|杯|かけ|合|分)|^(少々|適量)$",
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private nonisolated static func looksLikeInstruction(_ line: String) -> Bool {
        if startsWithStepMarker(line) {
            return true
        }
        let verbs = ["切る", "焼く", "炒め", "煮", "混ぜ", "加え", "入れ", "置く", "取り出", "茹で", "ゆで", "温め", "冷ま", "冷や", "盛り", "かけ", "和え", "揚げ", "蒸し", "流す", "整え", "溶かす", "作る", "泡立て", "染み込ませ", "重ね", "ふる", "こし", "仕上げ", "つけ", "完成"]
        return line.count >= 8 && line.count <= 220 && verbs.contains { line.contains($0) }
    }

    private nonisolated static func matchesHeading(_ line: String, headings: [String]) -> Bool {
        let normalized = stripLeadingMarker(line)
            .replacingOccurrences(of: "[【】\\[\\]「」:：]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return headings.contains { heading in
            normalized == heading.lowercased()
                || normalized.hasPrefix(heading.lowercased() + " ")
                || normalized.hasPrefix(heading.lowercased() + "（")
                || normalized.hasPrefix(heading.lowercased() + "(")
        }
    }

    private nonisolated static func isNoiseLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        let noise = [
            "広告", "pr", "コメント", "いいね", "フォロー", "保存してね", "保存して作って",
            "詳細はこちら", "プロフィールリンク", "関連記事", "おすすめ", "cookie", "ログイン",
            "会員登録", "シェア", "共有", "ツイート", "lineで送る", "snsでシェア", "レシピ一覧",
            "バックナンバー", "著者", "料理家", "アプリでひらく", "レシピを保存",
            "mail magazine", "topics", "お問い合わせ", "似たレシピ", "つくれぽ", "チャンネル登録",
            "記事一覧", "人気記事", "ランキング", "author", "profile", "follow us", "subscribe",
            "facebook", "twitter", "instagram", "利用規約", "プライバシーポリシー"
        ]
        if noise.contains(where: { lower.contains($0) }) { return true }
        if lower.range(of: #"https?://|www\.|^image\b|^画像\b"#, options: .regularExpression) != nil { return true }
        if line.range(of: "^([@#][^\\s]+\\s*)+$", options: .regularExpression) != nil { return true }
        if line.range(of: "^[\\p{So}\\p{Sk}\\s]+$", options: .regularExpression) != nil { return true }
        return false
    }

    private nonisolated static func isURLOnly(_ lines: [String]) -> Bool {
        guard lines.count == 1, let line = lines.first else { return false }
        return URL(string: line)?.scheme?.hasPrefix("http") == true
    }

    private nonisolated static func isVerificationPage(_ lines: [String]) -> Bool {
        let text = lines.joined(separator: " ").lowercased()
        return text.contains("bot verification")
            || text.contains("verify you are human")
            || text.contains("checking your browser")
            || text.contains("access denied")
            || text.contains("cloudflare")
    }

    private nonisolated static func htmlDecoded(_ text: String) -> String {
        var result = text
        let replacements = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'"
        ]
        for (source, destination) in replacements {
            result = result.replacingOccurrences(of: source, with: destination)
        }
        return result
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

    private nonisolated static let ingredientHeadings = [
        "材料", "具材", "用意するもの", "使うもの", "分量", "2人分", "3人分", "4人分",
        "ingredients", "ingredient", "what you need"
    ]

    private nonisolated static let ingredientEndHeadings = [
        "作り方", "作りかた", "手順", "調理", "レシピ", "つくり方", "調理方法",
        "directions", "instructions", "method", "how to make", "ポイント", "コツ", "point", "notes"
    ]

    private nonisolated static let instructionHeadings = [
        "作り方", "作りかた", "手順", "調理手順", "レシピ", "調理方法", "つくり方", "作成手順",
        "instructions", "directions", "method", "how to make", "steps"
    ]

    private nonisolated static let instructionEndHeadings = [
        "材料", "具材", "用意するもの", "使うもの", "notes", "保存方法", "栄養", "コメント", "関連", "pr", "広告",
        "つくれぽ", "似たレシピ", "記事一覧", "メールマガジン", "バックナンバー", "著者", "料理家",
        "instagram", "mail magazine", "topics", "お問い合わせ"
    ]
}

private extension RecipeTextExtractor {
    nonisolated static func instructionsFromSection(_ section: [String]) -> [String] {
        let numbered = numberedInstructions(from: section)
        if !numbered.isEmpty {
            return unique(numbered)
        }

        var result: [String] = []
        var pendingNumber = false
        let hasNumberedSteps = section.contains { line in
            let stripped = stripLeadingMarker(line)
            return isStandaloneStepNumber(stripped) || startsWithStepMarker(stripped)
        }

        for line in section {
            let stripped = stripLeadingMarker(line)
            if isSupplementalInstructionLine(line) || isSupplementalInstructionLine(stripped) {
                continue
            }
            if isStandaloneStepNumber(stripped) {
                pendingNumber = true
                continue
            }
            guard let cleaned = cleanedInstructionLine(stripped) else {
                continue
            }

            let startsNewStep = pendingNumber || startsWithStepMarker(stripped) || !hasNumberedSteps
            if startsNewStep || result.isEmpty {
                result.append(cleaned)
            } else {
                result[result.count - 1] += " " + cleaned
            }
            pendingNumber = false
        }

        return unique(result)
    }

    nonisolated static func numberedInstructions(from section: [String]) -> [String] {
        let text = preprocessedTextForExtraction(section.joined(separator: "\n"))
        let fragments = text
            .components(separatedBy: .newlines)
            .flatMap { splitDenseLine($0) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var result: [String] = []
        var currentParts: [String] = []
        var suppressSupplementUntilNextStep = false

        func flushCurrentStep() {
            if !currentParts.isEmpty {
                result.append(currentParts.joined(separator: " "))
                currentParts.removeAll()
            }
        }

        for fragment in fragments {
            let stripped = stripLeadingMarker(fragment)
            let startsStep = startsWithStepMarker(stripped) || startsWithStepMarker(fragment)
            if startsStep {
                flushCurrentStep()
                suppressSupplementUntilNextStep = false
                if let cleaned = cleanedInstructionLine(stripped) {
                    currentParts = [cleaned]
                }
                continue
            }

            if isSupplementalInstructionLine(fragment) || isSupplementalInstructionLine(stripped) {
                suppressSupplementUntilNextStep = true
                continue
            }
            guard !suppressSupplementUntilNextStep, !currentParts.isEmpty else {
                continue
            }
            if let cleaned = cleanedInstructionLine(stripped) {
                currentParts.append(cleaned)
            }
        }
        flushCurrentStep()

        return unique(result)
    }

    nonisolated static func isStandaloneStepNumber(_ line: String) -> Bool {
        line.range(of: "^(\\(?[0-9０-９]+\\)?|（[0-9０-９]+）)[\\.)．。]?$", options: .regularExpression) != nil
    }

    nonisolated static func startsWithStepMarker(_ line: String) -> Bool {
        line.range(
            of: "^(\\([0-9０-９]+\\)|（[0-9０-９]+）|[0-9０-９]+[\\.)）．。\\s]+|[①②③④⑤⑥⑦⑧⑨⑩]|STEP\\s*\\d+|Step\\s*\\d+)\\s*(?![にをでへと])",
            options: .regularExpression
        ) != nil
    }
}

private extension String {
    nonisolated func firstCapture(pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(startIndex..<endIndex, in: self)
        guard let match = regex.firstMatch(in: self, range: range),
              match.numberOfRanges > 1,
              let swiftRange = Range(match.range(at: 1), in: self) else {
            return nil
        }
        return String(self[swiftRange])
    }
}
