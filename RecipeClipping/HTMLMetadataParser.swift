import Foundation
import UIKit

struct HTMLMetadata {
    var title: String?
    var description: String?
    var imageURL: URL?
    var ingredientLines: [String]
    var instructionLines: [String]
    var rawText: String
    var extractionConfidence: Double
    var extractionWarnings: [String]
    var ingredientSource: String
    var instructionSource: String
}

enum HTMLMetadataParser {
    static func parse(html: String, baseURL: URL) -> HTMLMetadata {
        let metas = parseMetaTags(html: html)
        let jsonLD = parseJSONLDRecipe(html: html, baseURL: baseURL)
        let visibleText = parseVisibleText(html: html)
        let textExtraction = RecipeTextExtractor().extract(from: visibleText, metadataTitle: jsonLD.title)

        let title = firstNonEmpty([
            RecipeTextExtractor.cleanedTitle(jsonLD.title),
            RecipeTextExtractor.cleanedTitle(parseH1(html: html)),
            metas["og:title"],
            metas["twitter:title"],
            parseTitle(html: html),
            textExtraction.title
        ])

        let description = firstNonEmpty([
            jsonLD.description,
            metas["og:description"],
            metas["twitter:description"],
            metas["description"]
        ])

        let imageCandidates = [
            jsonLD.imageURL,
            absoluteURL(from: metas["og:image"], baseURL: baseURL),
            absoluteURL(from: metas["og:image:secure_url"], baseURL: baseURL),
            absoluteURL(from: metas["twitter:image"], baseURL: baseURL),
            parseBestImageTagURL(html: html, baseURL: baseURL)
        ]

        let structuredIngredients = jsonLD.ingredientLines.isEmpty ? parseStructuredList(html: html, itemprop: "recipeIngredient") : jsonLD.ingredientLines
        let structuredInstructions = jsonLD.instructionLines.isEmpty ? parseStructuredList(html: html, itemprop: "recipeInstructions") : jsonLD.instructionLines
        let ingredients = structuredIngredients.isEmpty ? textExtraction.ingredients : structuredIngredients
        let instructions = structuredInstructions.isEmpty ? textExtraction.instructions : structuredInstructions

        return HTMLMetadata(
            title: RecipeTextExtractor.cleanedTitle(title?.htmlDecoded),
            description: description?.htmlDecoded.trimmingCharacters(in: .whitespacesAndNewlines) ?? textExtraction.summary,
            imageURL: imageCandidates.compactMap { $0 }.first,
            ingredientLines: ingredients,
            instructionLines: instructions,
            rawText: visibleText,
            extractionConfidence: textExtraction.confidence,
            extractionWarnings: textExtraction.warnings,
            ingredientSource: !jsonLD.ingredientLines.isEmpty ? "jsonld" : (!structuredIngredients.isEmpty ? "html" : textExtraction.ingredientSource),
            instructionSource: !jsonLD.instructionLines.isEmpty ? "jsonld" : (!structuredInstructions.isEmpty ? "html" : textExtraction.instructionSource)
        )
    }

    private static func parseMetaTags(html: String) -> [String: String] {
        var result: [String: String] = [:]
        let tags = matches(pattern: "<meta\\b[^>]*>", in: html)
        for tag in tags {
            let key = attribute("property", in: tag) ?? attribute("name", in: tag) ?? attribute("itemprop", in: tag)
            let content = attribute("content", in: tag)
            if let key = key?.lowercased(), let content, !content.isEmpty, result[key] == nil {
                result[key] = content.htmlDecoded
            }
        }
        return result
    }

    private static func parseTitle(html: String) -> String? {
        firstCapture(pattern: "<title[^>]*>(.*?)</title>", in: html)?.htmlDecoded
    }

    private static func parseH1(html: String) -> String? {
        firstCapture(pattern: "<h1\\b[^>]*>(.*?)</h1>", in: html).map { stripTags($0).htmlDecoded }
    }

    private static func parseVisibleText(html: String) -> String {
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
        text = text.replacingOccurrences(of: "</(p|div|li|h1|h2|h3|h4|section|article|tr)>", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = stripTags(text).htmlDecoded
        text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseJSONLDRecipe(html: String, baseURL: URL) -> (title: String?, description: String?, imageURL: URL?, ingredientLines: [String], instructionLines: [String]) {
        let scripts = matches(pattern: "<script(?=[^>]*application/ld\\+json)[^>]*>(.*?)</script>", in: html, captureGroup: 1)

        for script in scripts {
            let cleaned = script
                .htmlDecoded
                .replacingOccurrences(of: "\u{FEFF}", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = cleaned.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else {
                continue
            }
            if let recipe = findRecipeObject(in: json) {
                let title = recipe["name"] as? String
                let description = recipe["description"] as? String
                let imageString = extractImageString(from: recipe["image"] ?? recipe["thumbnailUrl"])
                let imageURL = absoluteURL(from: imageString, baseURL: baseURL)
                let ingredients = extractStringArray(from: recipe["recipeIngredient"] ?? recipe["ingredients"])
                let instructions = extractInstructionLines(from: recipe["recipeInstructions"] ?? recipe["instructions"])
                return (title, description, imageURL, cleanedLines(ingredients), cleanedLines(instructions))
            }
        }
        return (nil, nil, nil, [], [])
    }

    private static func findRecipeObject(in object: Any) -> [String: Any]? {
        if let dict = object as? [String: Any] {
            if typeIsRecipe(dict["@type"]) {
                return dict
            }
            if let graph = dict["@graph"], let found = findRecipeObject(in: graph) {
                return found
            }
            for value in dict.values {
                if let found = findRecipeObject(in: value) {
                    return found
                }
            }
        } else if let array = object as? [Any] {
            for item in array {
                if let found = findRecipeObject(in: item) {
                    return found
                }
            }
        }
        return nil
    }

    private static func typeIsRecipe(_ typeValue: Any?) -> Bool {
        if let type = typeValue as? String {
            return type.lowercased().contains("recipe")
        }
        if let types = typeValue as? [String] {
            return types.contains { $0.lowercased().contains("recipe") }
        }
        return false
    }

    private static func extractImageString(from value: Any?) -> String? {
        if let string = value as? String { return string }
        if let array = value as? [Any] {
            for item in array {
                if let image = extractImageString(from: item) { return image }
            }
        }
        if let dict = value as? [String: Any] {
            return extractImageString(from: dict["url"] ?? dict["contentUrl"])
        }
        return nil
    }

    private static func extractStringArray(from value: Any?) -> [String] {
        if let string = value as? String { return [string] }
        if let array = value as? [Any] {
            return array.flatMap { extractStringArray(from: $0) }
        }
        if let dict = value as? [String: Any] {
            if let text = dict["text"] as? String { return [text] }
            if let name = dict["name"] as? String { return [name] }
        }
        return []
    }

    private static func extractInstructionLines(from value: Any?) -> [String] {
        if let string = value as? String { return [string] }
        if let array = value as? [Any] {
            return array.flatMap { extractInstructionLines(from: $0) }
        }
        guard let dict = value as? [String: Any] else { return [] }

        let typeText = "\(dict["@type"] ?? "")".lowercased()
        if typeText.contains("howtosection") {
            let sectionName = (dict["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let nested = extractInstructionLines(from: dict["itemListElement"] ?? dict["steps"])
            guard let sectionName, !sectionName.isEmpty else { return nested }
            return nested.map { "\(sectionName): \($0)" }
        }

        if let text = dict["text"] as? String, !text.isEmpty {
            return [text]
        }
        if let name = dict["name"] as? String, !name.isEmpty {
            return [name]
        }
        if let nested = dict["itemListElement"] ?? dict["steps"] {
            return extractInstructionLines(from: nested)
        }
        return []
    }

    private static func parseStructuredList(html: String, itemprop: String) -> [String] {
        let escaped = NSRegularExpression.escapedPattern(for: itemprop)
        let tags = matches(pattern: "<[^>]+\\bitemprop\\s*=\\s*['\"]\(escaped)['\"][^>]*>(.*?)</[^>]+>", in: html, captureGroup: 1)
        return cleanedLines(tags.map { stripTags($0).htmlDecoded })
    }

    private static func cleanedLines(_ lines: [String]) -> [String] {
        var seen: Set<String> = []
        return lines
            .flatMap { $0.components(separatedBy: .newlines) }
            .map { stripTags($0).htmlDecoded.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { line in
                guard !seen.contains(line) else { return false }
                seen.insert(line)
                return true
            }
    }

    private static func stripTags(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
    }

    private static func parseBestImageTagURL(html: String, baseURL: URL) -> URL? {
        let imageTags = matches(pattern: "<img\\b[^>]*>", in: html)
        var best: (score: Int, url: URL)?

        for tag in imageTags.prefix(80) {
            let raw = attribute("data-src", in: tag)
                ?? attribute("data-original", in: tag)
                ?? firstURLFromSrcset(attribute("srcset", in: tag))
                ?? attribute("src", in: tag)
            guard let url = absoluteURL(from: raw, baseURL: baseURL) else { continue }
            let combined = (tag + " " + url.absoluteString).lowercased()
            var score = 0
            if combined.contains("recipe") || combined.contains("cook") || combined.contains("food") || combined.contains("dish") { score += 8 }
            if combined.contains("main") || combined.contains("hero") || combined.contains("eyecatch") || combined.contains("thumbnail") { score += 5 }
            if combined.contains(".jpg") || combined.contains(".jpeg") || combined.contains(".png") || combined.contains(".webp") { score += 3 }
            if combined.contains("logo") || combined.contains("icon") || combined.contains("avatar") || combined.contains("sprite") { score -= 10 }

            if best == nil || score > best!.score {
                best = (score, url)
            }
        }
        return best?.url
    }

    private static func firstURLFromSrcset(_ srcset: String?) -> String? {
        guard let srcset else { return nil }
        return srcset
            .split(separator: ",")
            .first?
            .split(separator: " ")
            .first
            .map(String.init)
    }

    private static func absoluteURL(from raw: String?, baseURL: URL) -> URL? {
        guard var raw = raw?.htmlDecoded.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.hasPrefix("//") {
            raw = "https:" + raw
        }
        if let url = URL(string: raw), url.scheme != nil {
            return url
        }
        return URL(string: raw, relativeTo: baseURL)?.absoluteURL
    }

    private static func firstNonEmpty(_ values: [String?]) -> String? {
        values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        return firstCapture(pattern: "\\b\(escaped)\\s*=\\s*['\"]([^'\"]*)['\"]", in: tag)
    }

    private static func firstCapture(pattern: String, in text: String) -> String? {
        matches(pattern: pattern, in: text, captureGroup: 1).first
    }

    private static func matches(pattern: String, in text: String, captureGroup: Int = 0) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard match.numberOfRanges > captureGroup,
                  let range = Range(match.range(at: captureGroup), in: text) else {
                return nil
            }
            return String(text[range])
        }
    }
}

private extension String {
    var htmlDecoded: String {
        guard let data = data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ) else {
            return self
        }
        return attributed.string
    }
}
