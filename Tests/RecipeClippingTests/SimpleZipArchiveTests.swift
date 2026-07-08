import XCTest
@testable import RecipeClipping

@MainActor
final class SimpleZipArchiveTests: XCTestCase {
    private var tempRoot: URL!

    override func setUp() async throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimpleZipArchiveTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRoot)
        tempRoot = nil
    }

    func testRoundTripPreservesFilesAndDirectories() throws {
        let sourceURL = tempRoot.appendingPathComponent("source", isDirectory: true)
        let imagesURL = sourceURL.appendingPathComponent("RecipeImages", isDirectory: true)
        try FileManager.default.createDirectory(at: imagesURL, withIntermediateDirectories: true)

        let jsonData = Data("{\"recipes\": []}".utf8)
        let imageData = Data((0..<4096).map { UInt8($0 % 251) })
        try jsonData.write(to: sourceURL.appendingPathComponent("backup.json"))
        // 日本語ファイル名(UTF-8フラグ)も往復できること
        try imageData.write(to: imagesURL.appendingPathComponent("写真-1.jpg"))

        let archiveData = try SimpleZipArchive.archiveData(from: sourceURL)

        let destinationURL = tempRoot.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        try SimpleZipArchive.extract(archiveData, to: destinationURL)

        XCTAssertEqual(
            try Data(contentsOf: destinationURL.appendingPathComponent("backup.json")),
            jsonData
        )
        XCTAssertEqual(
            try Data(contentsOf: destinationURL.appendingPathComponent("RecipeImages/写真-1.jpg")),
            imageData
        )
    }

    func testExtractRejectsCorruptData() throws {
        let destinationURL = tempRoot.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        XCTAssertThrowsError(
            try SimpleZipArchive.extract(Data("this is not a zip archive".utf8), to: destinationURL)
        )
    }

    func testExtractRejectsPathTraversalEntries() throws {
        let sourceURL = tempRoot.appendingPathComponent("source", isDirectory: true)
        let nestedURL = sourceURL.appendingPathComponent("aa", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedURL, withIntermediateDirectories: true)
        try Data("evil".utf8).write(to: nestedURL.appendingPathComponent("evil.txt"))

        // 正常なアーカイブのエントリ名を「../evil.txt」に書き換えた悪意あるZIPを模す
        let archiveData = try SimpleZipArchive.archiveData(from: sourceURL)
        let malicious = replacingOccurrences(
            of: Data("aa/evil.txt".utf8),
            with: Data("../evil.txt".utf8),
            in: archiveData
        )
        XCTAssertNotEqual(malicious, archiveData, "エントリ名の書き換えに失敗している")

        let destinationURL = tempRoot.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        XCTAssertThrowsError(try SimpleZipArchive.extract(malicious, to: destinationURL))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: tempRoot.appendingPathComponent("evil.txt").path)
        )
    }

    private func replacingOccurrences(of target: Data, with replacement: Data, in data: Data) -> Data {
        precondition(target.count == replacement.count, "同じ長さの置換のみ対応")
        var result = data
        var searchRange = result.startIndex..<result.endIndex
        while let range = result.range(of: target, in: searchRange) {
            result.replaceSubrange(range, with: replacement)
            searchRange = range.upperBound..<result.endIndex
        }
        return result
    }
}
