import Foundation
import SwiftData
import UniformTypeIdentifiers
import SwiftUI

struct RecipeBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zip] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum BackupService {
    private static let backupFileName = "backup.json"
    private static let imagesDirectoryName = "RecipeImages"

    @MainActor
    static func makeArchiveData(
        from recipes: [Recipe],
        imagesDirectoryURL: URL = ImageStore.directoryURL
    ) throws -> Data {
        let fileManager = FileManager.default
        let workingDirectory = try temporaryDirectory(named: "RecipeClipperBackup")
        defer { try? fileManager.removeItem(at: workingDirectory) }

        let payload = RecipeClipperBackupPayload(recipes: recipes)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(payload)
        try jsonData.write(to: workingDirectory.appendingPathComponent(backupFileName), options: [.atomic])

        if fileManager.fileExists(atPath: imagesDirectoryURL.path) {
            try fileManager.copyItem(
                at: imagesDirectoryURL,
                to: workingDirectory.appendingPathComponent(imagesDirectoryName, isDirectory: true)
            )
        }

        return try SimpleZipArchive.archiveData(from: workingDirectory)
    }

    /// 復元は「展開・デコードの完全な検証 → 現行画像の退避 → 入れ替え」の順で行い、
    /// 途中で失敗した場合は退避した画像とModelContextを元に戻す。
    /// 既存データの削除は、バックアップ内容が使えると確定した後にのみ実行される。
    @MainActor
    static func restore(
        from archiveURL: URL,
        modelContext: ModelContext,
        imagesDirectoryURL: URL = ImageStore.directoryURL
    ) throws -> Int {
        let fileManager = FileManager.default
        let workingDirectory = try temporaryDirectory(named: "RecipeClipperRestore")
        defer { try? fileManager.removeItem(at: workingDirectory) }

        let didAccess = archiveURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                archiveURL.stopAccessingSecurityScopedResource()
            }
        }
        let archiveData = try Data(contentsOf: archiveURL)

        // ここまでで失敗しても既存データには一切触れていない
        let expandedURL = workingDirectory.appendingPathComponent("expanded", isDirectory: true)
        try fileManager.createDirectory(at: expandedURL, withIntermediateDirectories: true)
        try SimpleZipArchive.extract(archiveData, to: expandedURL)

        let jsonURL = expandedURL.appendingPathComponent(backupFileName)
        let jsonData = try Data(contentsOf: jsonURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(RecipeClipperBackupPayload.self, from: jsonData)

        // 現行画像は削除せず退避し、復元完了まで巻き戻せる状態を保つ。
        // 退避先はtmpではなく画像ディレクトリの隣に置く: 復元途中でクラッシュしても
        // 旧画像がシステムのtmp掃除やworkingDirectory削除で消えず、手動復旧できる
        let backupImagesURL = expandedURL.appendingPathComponent(imagesDirectoryName, isDirectory: true)
        let retiredImagesURL = imagesDirectoryURL
            .deletingLastPathComponent()
            .appendingPathComponent("RecipeImages-retired-\(UUID().uuidString)", isDirectory: true)
        var movedCurrentImagesAside = false
        if fileManager.fileExists(atPath: imagesDirectoryURL.path) {
            try fileManager.moveItem(at: imagesDirectoryURL, to: retiredImagesURL)
            movedCurrentImagesAside = true
        }

        func rollbackImages() {
            try? fileManager.removeItem(at: imagesDirectoryURL)
            if movedCurrentImagesAside {
                // 巻き戻しの移動に失敗しても、旧画像はretiredディレクトリに残り失われない
                try? fileManager.moveItem(at: retiredImagesURL, to: imagesDirectoryURL)
            }
        }

        do {
            if fileManager.fileExists(atPath: backupImagesURL.path) {
                try fileManager.moveItem(at: backupImagesURL, to: imagesDirectoryURL)
            } else {
                try fileManager.createDirectory(at: imagesDirectoryURL, withIntermediateDirectories: true)
            }
        } catch {
            rollbackImages()
            throw error
        }

        do {
            let existingRecipes = try modelContext.fetch(FetchDescriptor<Recipe>())
            for recipe in existingRecipes {
                modelContext.delete(recipe)
            }
            for recipeBackup in payload.recipes {
                let recipe = recipeBackup.makeRecipe()
                modelContext.insert(recipe)
                for cookLogBackup in recipeBackup.cookLogs {
                    modelContext.insert(cookLogBackup.makeCookLog(recipe: recipe))
                }
            }
            // 削除と挿入を1回のsaveにまとめ、失敗時はrollbackで削除ごと巻き戻す
            try modelContext.save()
        } catch {
            modelContext.rollback()
            rollbackImages()
            throw error
        }

        // 全工程が成功したので退避していた旧画像を破棄する
        if movedCurrentImagesAside {
            try? fileManager.removeItem(at: retiredImagesURL)
        }
        return payload.recipes.count
    }

    private static func temporaryDirectory(named prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private struct RecipeClipperBackupPayload: Codable {
    var formatVersion: Int
    var exportedAt: Date
    var recipes: [RecipeBackup]

    enum CodingKeys: String, CodingKey {
        case formatVersion
        case exportedAt
        case recipes
    }

    @MainActor
    init(recipes: [Recipe]) {
        self.formatVersion = 1
        self.exportedAt = Date()
        self.recipes = recipes
            .sorted { $0.createdAt < $1.createdAt }
            .map(RecipeBackup.init(recipe:))
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
        exportedAt = try container.decodeIfPresent(Date.self, forKey: .exportedAt) ?? .distantPast
        recipes = try container.decodeIfPresent([RecipeBackup].self, forKey: .recipes) ?? []
    }
}

private struct RecipeBackup: Codable {
    var id: UUID
    var title: String
    var summary: String
    var sourceURL: String
    var sourceHost: String
    var sourceImageURL: String?
    var imagePath: String?
    var notes: String
    var tags: [String]
    var ingredients: [String]
    var instructions: [String]
    var checkedIngredients: [String]
    var normalizedSourceURL: String
    var sourceKind: String
    var isFavorite: Bool
    var rating: Int
    var wantsRemake: Bool
    var extractedRawText: String
    var rawImportedText: String
    var rawImportedHTML: String
    var importedTextSource: String
    var extractionConfidence: Double
    var extractionWarnings: [String]
    var ingredientSource: String
    var instructionSource: String
    var createdAt: Date
    var updatedAt: Date
    var cookLogs: [CookLogBackup]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case summary
        case sourceURL
        case sourceHost
        case sourceImageURL
        case imagePath
        case notes
        case tags
        case ingredients
        case instructions
        case checkedIngredients
        case normalizedSourceURL
        case sourceKind
        case isFavorite
        case rating
        case wantsRemake
        case extractedRawText
        case rawImportedText
        case rawImportedHTML
        case importedTextSource
        case extractionConfidence
        case extractionWarnings
        case ingredientSource
        case instructionSource
        case createdAt
        case updatedAt
        case cookLogs
    }

    @MainActor
    init(recipe: Recipe) {
        id = recipe.id
        title = recipe.title
        summary = recipe.summary
        sourceURL = recipe.sourceURLString
        sourceHost = recipe.sourceHost
        sourceImageURL = recipe.sourceImageURLString
        imagePath = recipe.localImageFileName
        notes = recipe.notes
        tags = recipe.tags
        ingredients = recipe.ingredientLines
        instructions = recipe.instructionLines
        checkedIngredients = recipe.checkedIngredientLines
        normalizedSourceURL = recipe.normalizedSourceURLString
        sourceKind = recipe.sourceKindRaw
        isFavorite = recipe.isFavorite
        rating = recipe.rating
        wantsRemake = recipe.wantsRemake
        extractedRawText = recipe.extractedRawText
        rawImportedText = recipe.rawImportedText
        rawImportedHTML = recipe.rawImportedHTML
        importedTextSource = recipe.importedTextSource
        extractionConfidence = recipe.extractionConfidence
        extractionWarnings = recipe.extractionWarnings
        ingredientSource = recipe.ingredientSource
        instructionSource = recipe.instructionSource
        createdAt = recipe.createdAt
        updatedAt = recipe.updatedAt
        cookLogs = recipe.cookLogs
            .sorted { $0.cookedAt < $1.cookedAt }
            .map(CookLogBackup.init(cookLog:))
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let now = Date()
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "無題のレシピ"
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL) ?? ""
        sourceHost = try container.decodeIfPresent(String.self, forKey: .sourceHost) ?? ""
        sourceImageURL = try container.decodeIfPresent(String.self, forKey: .sourceImageURL)
        imagePath = try container.decodeIfPresent(String.self, forKey: .imagePath)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        ingredients = try container.decodeIfPresent([String].self, forKey: .ingredients) ?? []
        instructions = try container.decodeIfPresent([String].self, forKey: .instructions) ?? []
        checkedIngredients = try container.decodeIfPresent([String].self, forKey: .checkedIngredients) ?? []
        normalizedSourceURL = try container.decodeIfPresent(String.self, forKey: .normalizedSourceURL)
            ?? URLNormalizer.normalizedString(for: sourceURL)
        sourceKind = try container.decodeIfPresent(String.self, forKey: .sourceKind)
            ?? RecipeSourceKind.detect(urlString: sourceURL, host: sourceHost).rawValue
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        rating = try container.decodeIfPresent(Int.self, forKey: .rating) ?? 0
        wantsRemake = try container.decodeIfPresent(Bool.self, forKey: .wantsRemake) ?? false
        extractedRawText = try container.decodeIfPresent(String.self, forKey: .extractedRawText) ?? ""
        rawImportedText = try container.decodeIfPresent(String.self, forKey: .rawImportedText) ?? extractedRawText
        rawImportedHTML = try container.decodeIfPresent(String.self, forKey: .rawImportedHTML) ?? ""
        importedTextSource = try container.decodeIfPresent(String.self, forKey: .importedTextSource) ?? "none"
        extractionConfidence = try container.decodeIfPresent(Double.self, forKey: .extractionConfidence) ?? 0.0
        extractionWarnings = try container.decodeIfPresent([String].self, forKey: .extractionWarnings) ?? []
        ingredientSource = try container.decodeIfPresent(String.self, forKey: .ingredientSource) ?? "none"
        instructionSource = try container.decodeIfPresent(String.self, forKey: .instructionSource) ?? "none"
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? now
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        cookLogs = try container.decodeIfPresent([CookLogBackup].self, forKey: .cookLogs) ?? []
    }

    func makeRecipe() -> Recipe {
        let recipe = Recipe(
            title: title,
            summary: summary,
            sourceURLString: sourceURL,
            sourceHost: sourceHost,
            sourceImageURLString: sourceImageURL,
            localImageFileName: imagePath,
            notes: notes,
            tagsText: tags.joined(separator: ", "),
            ingredientLinesText: Recipe.text(from: ingredients),
            instructionLinesText: Recipe.text(from: instructions),
            normalizedSourceURLString: normalizedSourceURL,
            sourceKindRaw: sourceKind,
            extractedRawText: extractedRawText,
            rawImportedText: rawImportedText,
            rawImportedHTML: rawImportedHTML,
            importedTextSource: importedTextSource,
            extractionConfidence: extractionConfidence,
            extractionWarningsText: Recipe.text(from: extractionWarnings),
            ingredientSource: ingredientSource,
            instructionSource: instructionSource
        )
        recipe.id = id
        recipe.isFavorite = isFavorite
        recipe.rating = rating
        recipe.wantsRemake = wantsRemake
        recipe.checkedIngredientLines = checkedIngredients
        recipe.createdAt = createdAt
        recipe.updatedAt = updatedAt
        recipe.refreshDerivedFields()
        return recipe
    }
}

private struct CookLogBackup: Codable {
    var id: UUID
    var cookedAt: Date
    var memo: String
    var imagePath: String?
    var rating: Int
    var improvementMemo: String
    var arrangementMemo: String

    enum CodingKeys: String, CodingKey {
        case id
        case cookedAt
        case memo
        case imagePath
        case rating
        case improvementMemo
        case arrangementMemo
    }

    @MainActor
    init(cookLog: CookLog) {
        id = cookLog.id
        cookedAt = cookLog.cookedAt
        memo = cookLog.memo
        imagePath = cookLog.localImageFileName
        rating = cookLog.rating
        improvementMemo = cookLog.improvementMemo
        arrangementMemo = cookLog.arrangementMemo
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        cookedAt = try container.decodeIfPresent(Date.self, forKey: .cookedAt) ?? Date()
        memo = try container.decodeIfPresent(String.self, forKey: .memo) ?? ""
        imagePath = try container.decodeIfPresent(String.self, forKey: .imagePath)
        rating = try container.decodeIfPresent(Int.self, forKey: .rating) ?? 0
        improvementMemo = try container.decodeIfPresent(String.self, forKey: .improvementMemo) ?? ""
        arrangementMemo = try container.decodeIfPresent(String.self, forKey: .arrangementMemo) ?? ""
    }

    func makeCookLog(recipe: Recipe) -> CookLog {
        let cookLog = CookLog(
            cookedAt: cookedAt,
            memo: memo,
            localImageFileName: imagePath,
            rating: rating,
            improvementMemo: improvementMemo,
            arrangementMemo: arrangementMemo,
            recipe: recipe
        )
        cookLog.id = id
        return cookLog
    }
}
