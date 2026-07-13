import Foundation
import SwiftData

@Model
final class Recipe {
    var id: UUID
    var title: String
    var summary: String
    var sourceURLString: String
    var sourceHost: String
    var sourceImageURLString: String?
    var localImageFileName: String?
    var notes: String
    var tagsText: String
    var ingredientLinesText: String = ""
    var instructionLinesText: String = ""
    // 買い物用チェックリストの状態。チェック済みの材料行そのものを改行区切りで持つ
    // (行番号ではなく行テキストで持つことで、材料編集後も一致する行のチェックが自然に残る)
    var checkedIngredientLinesText: String = ""
    var normalizedSourceURLString: String = ""
    var sourceKindRaw: String = "web"
    var isFavorite: Bool = false
    var rating: Int = 0
    var wantsRemake: Bool = false
    var extractedRawText: String = ""
    var rawImportedText: String = ""
    var rawImportedHTML: String = ""
    var importedTextSource: String = "none"
    var extractionConfidence: Double = 0.0
    var extractionWarningsText: String = ""
    var ingredientSource: String = "none"
    var instructionSource: String = "none"
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \CookLog.recipe)
    var cookLogs: [CookLog]

    init(
        title: String,
        summary: String = "",
        sourceURLString: String,
        sourceHost: String = "",
        sourceImageURLString: String? = nil,
        localImageFileName: String? = nil,
        notes: String = "",
        tagsText: String = "",
        ingredientLinesText: String = "",
        instructionLinesText: String = "",
        normalizedSourceURLString: String = "",
        sourceKindRaw: String = "web",
        extractedRawText: String = "",
        rawImportedText: String = "",
        rawImportedHTML: String = "",
        importedTextSource: String = "none",
        extractionConfidence: Double = 0.0,
        extractionWarningsText: String = "",
        ingredientSource: String = "none",
        instructionSource: String = "none"
    ) {
        self.id = UUID()
        self.title = title
        self.summary = summary
        self.sourceURLString = sourceURLString
        self.sourceHost = sourceHost
        self.sourceImageURLString = sourceImageURLString
        self.localImageFileName = localImageFileName
        self.notes = notes
        self.tagsText = Self.normalizedTagsText(from: tagsText)
        self.ingredientLinesText = ingredientLinesText
        self.instructionLinesText = instructionLinesText
        self.normalizedSourceURLString = normalizedSourceURLString.isEmpty
            ? URLNormalizer.normalizedString(for: sourceURLString)
            : normalizedSourceURLString
        self.sourceKindRaw = sourceKindRaw
        self.extractedRawText = extractedRawText
        self.rawImportedText = rawImportedText.isEmpty ? extractedRawText : rawImportedText
        // 生HTMLはテストケース採取用の保険。YouTube等ではMB級になり
        // ストアとバックアップを肥大させるため、全生成経路(インポート・復元)で先頭のみ保持する
        self.rawImportedHTML = String(rawImportedHTML.prefix(Self.maxRawImportedHTMLLength))
        self.importedTextSource = importedTextSource
        self.extractionConfidence = extractionConfidence
        self.extractionWarningsText = extractionWarningsText
        self.ingredientSource = ingredientSource
        self.instructionSource = instructionSource
        self.createdAt = Date()
        self.updatedAt = Date()
        self.cookLogs = []
    }

    var sourceURL: URL? { URL(string: sourceURLString) }
    var sourceImageURL: URL? { sourceImageURLString.flatMap(URL.init(string:)) }
    var tags: [String] {
        Self.normalizedTags(from: tagsText)
    }

    var ingredientLines: [String] {
        get { Self.lines(from: ingredientLinesText) }
        set { ingredientLinesText = Self.text(from: newValue) }
    }

    var instructionLines: [String] {
        get { Self.lines(from: instructionLinesText) }
        set { instructionLinesText = Self.text(from: newValue) }
    }

    var checkedIngredientLines: [String] {
        get { Self.lines(from: checkedIngredientLinesText) }
        set { checkedIngredientLinesText = Self.text(from: newValue) }
    }

    func toggleIngredientChecked(_ line: String) {
        var lines = checkedIngredientLines
        if let index = lines.firstIndex(of: line) {
            lines.remove(at: index)
        } else {
            lines.append(line)
        }
        checkedIngredientLines = lines
    }

    func isIngredientChecked(_ line: String) -> Bool {
        checkedIngredientLines.contains(line)
    }

    var extractionWarnings: [String] {
        get { Self.lines(from: extractionWarningsText) }
        set { extractionWarningsText = Self.text(from: newValue) }
    }

    var sourceKind: RecipeSourceKind {
        get { RecipeSourceKind(rawValue: sourceKindRaw) ?? .web }
        set { sourceKindRaw = newValue.rawValue }
    }

    var lastCookedAt: Date? {
        cookLogs.map(\.cookedAt).max()
    }

    // rawImportedTextはページ全文で巨大になりうるため検索対象に含めない
    // (1キーストロークごとに全レシピ分を連結・lowercaseするコストが大きい)
    var searchableText: String {
        [
            title,
            summary,
            notes,
            tagsText,
            ingredientLinesText,
            instructionLinesText,
            sourceHost,
            sourceURLString,
            sourceKind.displayName
        ].joined(separator: "\n").lowercased()
    }

    func refreshDerivedFields() {
        tagsText = Self.normalizedTagsText(from: tagsText)
        normalizedSourceURLString = URLNormalizer.normalizedString(for: sourceURLString)
        // 種別は編集画面でユーザーが変更できるため、未設定のときだけ自動判定する
        if sourceKindRaw.isEmpty {
            sourceKindRaw = RecipeSourceKind.detect(urlString: sourceURLString, host: sourceHost).rawValue
        }
        // 材料の編集で存在しなくなった行のチェック状態は捨てる
        let currentIngredients = Set(ingredientLines)
        checkedIngredientLines = checkedIngredientLines.filter { currentIngredients.contains($0) }
    }

    static let maxRawImportedHTMLLength = 500_000

    static func normalizedTags(from text: String) -> [String] {
        var seen: Set<String> = []
        return text
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { $0.hasPrefix("#") ? String($0.dropFirst()) : $0 }
            .filter { !$0.isEmpty }
            .filter { tag in
                let key = tag.lowercased()
                guard !seen.contains(key) else { return false }
                seen.insert(key)
                return true
            }
    }

    static func normalizedTagsText(from text: String) -> String {
        normalizedTags(from: text).joined(separator: ", ")
    }

    static func lines(from text: String) -> [String] {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func text(from lines: [String]) -> String {
        lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

@Model
final class CookLog {
    var id: UUID
    var cookedAt: Date
    var memo: String
    var localImageFileName: String?
    var rating: Int
    var improvementMemo: String = ""
    var arrangementMemo: String = ""
    var recipe: Recipe?

    init(
        cookedAt: Date = Date(),
        memo: String = "",
        localImageFileName: String? = nil,
        rating: Int = 0,
        improvementMemo: String = "",
        arrangementMemo: String = "",
        recipe: Recipe? = nil
    ) {
        self.id = UUID()
        self.cookedAt = cookedAt
        self.memo = memo
        self.localImageFileName = localImageFileName
        self.rating = rating
        self.improvementMemo = improvementMemo
        self.arrangementMemo = arrangementMemo
        self.recipe = recipe
    }
}

enum RecipeSourceKind: String, CaseIterable, Identifiable {
    case instagram
    case cookpad
    case youtube
    case web
    case original
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .instagram: "Instagram"
        case .cookpad: "Cookpad"
        case .youtube: "YouTube"
        case .web: "Web"
        case .original: "自作"
        case .other: "その他"
        }
    }

    static func detect(urlString: String, host: String) -> RecipeSourceKind {
        let source = "\(host) \(urlString)".lowercased()
        if source.contains("instagram.com") { return .instagram }
        if source.contains("cookpad.com") { return .cookpad }
        if source.contains("youtube.com") || source.contains("youtu.be") { return .youtube }
        if source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .original }
        return .web
    }
}
