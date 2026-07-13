import XCTest
import SwiftData
@testable import RecipeClipping

@MainActor
final class BackupServiceTests: XCTestCase {
    private var tempRoot: URL!

    override func setUp() async throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRoot)
        tempRoot = nil
    }

    func testArchiveAndRestoreRoundTrip() throws {
        let sourceImagesURL = try makeImagesDirectory(named: "source-images")
        let imageData = Data("recipe-image-bytes".utf8)
        try imageData.write(to: sourceImagesURL.appendingPathComponent("hero.jpg"))

        let sourceContext = try makeContainer().mainContext
        let recipe = makeSampleRecipe()
        sourceContext.insert(recipe)
        let log = CookLog(
            cookedAt: Date(timeIntervalSince1970: 1_700_000_000),
            memo: "おいしくできた",
            localImageFileName: nil,
            rating: 5,
            improvementMemo: "次は塩少なめ",
            arrangementMemo: "豚肉を追加",
            recipe: recipe
        )
        sourceContext.insert(log)
        try sourceContext.save()

        let archiveData = try BackupService.makeArchiveData(from: [recipe], imagesDirectoryURL: sourceImagesURL)
        let archiveURL = tempRoot.appendingPathComponent("backup.zip")
        try archiveData.write(to: archiveURL)

        let destImagesURL = tempRoot.appendingPathComponent("dest-images", isDirectory: true)
        let destContext = try makeContainer().mainContext
        let restoredCount = try BackupService.restore(
            from: archiveURL,
            modelContext: destContext,
            imagesDirectoryURL: destImagesURL
        )

        XCTAssertEqual(restoredCount, 1)
        let restored = try XCTUnwrap(destContext.fetch(FetchDescriptor<Recipe>()).first)
        XCTAssertEqual(restored.id, recipe.id)
        XCTAssertEqual(restored.title, "テスト煮物")
        XCTAssertEqual(restored.summary, "概要テキスト")
        XCTAssertEqual(restored.sourceURLString, "https://example.com/recipe/1")
        XCTAssertEqual(restored.sourceHost, "example.com")
        XCTAssertEqual(restored.localImageFileName, "hero.jpg")
        XCTAssertEqual(restored.notes, "自分メモ")
        XCTAssertEqual(restored.tags, ["和食", "煮物"])
        XCTAssertEqual(restored.ingredientLines, ["にんじん 1本", "だいこん 1/2本"])
        XCTAssertEqual(restored.instructionLines, ["切る", "煮る"])
        XCTAssertEqual(restored.checkedIngredientLines, ["にんじん 1本"])
        XCTAssertEqual(restored.sourceKindRaw, "web")
        XCTAssertTrue(restored.isFavorite)
        XCTAssertTrue(restored.wantsRemake)
        XCTAssertEqual(restored.rating, 4)
        XCTAssertEqual(restored.extractionConfidence, 0.75)

        XCTAssertEqual(restored.cookLogs.count, 1)
        let restoredLog = try XCTUnwrap(restored.cookLogs.first)
        XCTAssertEqual(restoredLog.id, log.id)
        XCTAssertEqual(restoredLog.memo, "おいしくできた")
        XCTAssertEqual(restoredLog.rating, 5)
        XCTAssertEqual(restoredLog.improvementMemo, "次は塩少なめ")
        XCTAssertEqual(restoredLog.arrangementMemo, "豚肉を追加")
        XCTAssertEqual(restoredLog.cookedAt, Date(timeIntervalSince1970: 1_700_000_000))

        XCTAssertEqual(
            try Data(contentsOf: destImagesURL.appendingPathComponent("hero.jpg")),
            imageData
        )
    }

    func testRestoreReplacesExistingRecipesAndImages() throws {
        let sourceImagesURL = try makeImagesDirectory(named: "source-images")
        try Data("new-image".utf8).write(to: sourceImagesURL.appendingPathComponent("new.jpg"))

        let sourceContext = try makeContainer().mainContext
        let recipe = makeSampleRecipe()
        sourceContext.insert(recipe)
        try sourceContext.save()
        let archiveURL = tempRoot.appendingPathComponent("backup.zip")
        try BackupService.makeArchiveData(from: [recipe], imagesDirectoryURL: sourceImagesURL)
            .write(to: archiveURL)

        // 復元先には既存レシピと既存画像がある
        let destImagesURL = try makeImagesDirectory(named: "dest-images")
        try Data("old-image".utf8).write(to: destImagesURL.appendingPathComponent("old.jpg"))
        let destContext = try makeContainer().mainContext
        let oldRecipe = Recipe(title: "古いレシピ", sourceURLString: "https://old.example.com/1")
        destContext.insert(oldRecipe)
        try destContext.save()

        _ = try BackupService.restore(
            from: archiveURL,
            modelContext: destContext,
            imagesDirectoryURL: destImagesURL
        )

        let titles = try destContext.fetch(FetchDescriptor<Recipe>()).map(\.title)
        XCTAssertEqual(titles, ["テスト煮物"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: destImagesURL.appendingPathComponent("old.jpg").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destImagesURL.appendingPathComponent("new.jpg").path))
    }

    func testRestoreFromCorruptArchiveKeepsExistingData() throws {
        let destImagesURL = try makeImagesDirectory(named: "dest-images")
        let keepImageURL = destImagesURL.appendingPathComponent("keep.jpg")
        try Data("keep-me".utf8).write(to: keepImageURL)

        let destContext = try makeContainer().mainContext
        let existing = makeSampleRecipe()
        destContext.insert(existing)
        try destContext.save()

        let corruptURL = tempRoot.appendingPathComponent("corrupt.zip")
        try Data("this is not a zip archive".utf8).write(to: corruptURL)

        XCTAssertThrowsError(
            try BackupService.restore(
                from: corruptURL,
                modelContext: destContext,
                imagesDirectoryURL: destImagesURL
            )
        )

        // 既存レシピと画像は無傷のまま
        XCTAssertEqual(try destContext.fetch(FetchDescriptor<Recipe>()).count, 1)
        XCTAssertEqual(try Data(contentsOf: keepImageURL), Data("keep-me".utf8))
    }

    func testRestoreFromArchiveWithoutBackupJSONKeepsExistingData() throws {
        // backup.jsonを含まない(=このアプリの形式でない)ZIPは既存データに触れず失敗する
        let bogusDirectory = tempRoot.appendingPathComponent("bogus", isDirectory: true)
        try FileManager.default.createDirectory(at: bogusDirectory, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: bogusDirectory.appendingPathComponent("readme.txt"))
        let archiveURL = tempRoot.appendingPathComponent("bogus.zip")
        try SimpleZipArchive.archiveData(from: bogusDirectory).write(to: archiveURL)

        let destImagesURL = try makeImagesDirectory(named: "dest-images")
        let keepImageURL = destImagesURL.appendingPathComponent("keep.jpg")
        try Data("keep-me".utf8).write(to: keepImageURL)
        let destContext = try makeContainer().mainContext
        destContext.insert(makeSampleRecipe())
        try destContext.save()

        XCTAssertThrowsError(
            try BackupService.restore(
                from: archiveURL,
                modelContext: destContext,
                imagesDirectoryURL: destImagesURL
            )
        )

        XCTAssertEqual(try destContext.fetch(FetchDescriptor<Recipe>()).count, 1)
        XCTAssertEqual(try Data(contentsOf: keepImageURL), Data("keep-me".utf8))
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Recipe.self, CookLog.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeImagesDirectory(named name: String) throws -> URL {
        let url = tempRoot.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeSampleRecipe() -> Recipe {
        let recipe = Recipe(
            title: "テスト煮物",
            summary: "概要テキスト",
            sourceURLString: "https://example.com/recipe/1",
            sourceHost: "example.com",
            sourceImageURLString: "https://example.com/hero.jpg",
            localImageFileName: "hero.jpg",
            notes: "自分メモ",
            tagsText: "和食, 煮物",
            ingredientLinesText: "にんじん 1本\nだいこん 1/2本",
            instructionLinesText: "切る\n煮る",
            sourceKindRaw: "web",
            extractionConfidence: 0.75
        )
        recipe.isFavorite = true
        recipe.wantsRemake = true
        recipe.rating = 4
        recipe.checkedIngredientLines = ["にんじん 1本"]
        return recipe
    }
}
