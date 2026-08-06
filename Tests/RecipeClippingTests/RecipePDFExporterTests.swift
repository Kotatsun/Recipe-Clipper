import CoreGraphics
import PDFKit
import UIKit
import XCTest
@testable import RecipeClipping

@MainActor
final class RecipePDFExporterTests: XCTestCase {
    func testTypicalRecipeFitsOnOneDesignedPage() throws {
        let imageFileName = try ImageStore.save(uiImage: makeSampleFoodImage())
        defer { ImageStore.delete(fileName: imageFileName) }

        let recipe = Recipe(
            title: "季節の野菜とハーブのキッシュ",
            summary: "香ばしいパイ生地に、旬の野菜とチーズをたっぷり詰めた軽やかなキッシュ。",
            sourceURLString: "https://example.com/seasonal-quiche",
            sourceHost: "example.com",
            localImageFileName: imageFileName,
            notes: "焼き上がりは10分休ませると、断面がきれいに仕上がる。",
            tagsText: "おもてなし, 野菜, オーブン",
            servingsText: "直径18cm 1台分",
            ingredientLinesText: "冷凍パイシート 1枚\n卵 3個\n生クリーム 150ml\n玉ねぎ 1/2個\nほうれん草 1/2束\nミニトマト 6個\nグリュイエールチーズ 80g\n塩・黒こしょう 各少々",
            instructionLinesText: "パイシートを型に敷き、フォークで底に穴をあける。\n玉ねぎとほうれん草をしんなりするまで炒め、粗熱を取る。\n卵、生クリーム、塩、黒こしょうをボウルで混ぜる。\n型に野菜とチーズを広げ、卵液を静かに流し入れる。\n180℃に予熱したオーブンで35〜40分、香ばしく焼く。"
        )
        recipe.rating = 5
        recipe.isFavorite = true
        recipe.wantsRemake = true

        let outputURL = try RecipePDFExporter().exportSingle(recipe: recipe)
        let document = try XCTUnwrap(CGPDFDocument(outputURL as CFURL))

        XCTAssertEqual(document.numberOfPages, 1)
        XCTAssertGreaterThan(try Data(contentsOf: outputURL).count, 10_000)
        let attachment = XCTAttachment(contentsOfFile: outputURL)
        attachment.name = "RecipePDFPreview.pdf"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testLongRecipeUsesContinuationPages() throws {
        let ingredients = (1...48).map { "材料\($0) 適量（下ごしらえのポイントを含む長めの説明）" }.joined(separator: "\n")
        let instructions = (1...32).map { "工程\($0)を丁寧に行い、香りと焼き色を確認しながら仕上げる。" }.joined(separator: "\n")
        let recipe = Recipe(
            title: "情報量の多い保存用レシピ",
            summary: String(repeating: "季節の素材を生かした詳しいレシピです。", count: 12),
            sourceURLString: "https://example.com/long-recipe",
            notes: String(repeating: "温度と時間は素材の状態に合わせて微調整する。", count: 24),
            tagsText: "作り置き, おもてなし, オーブン, 季節料理, 保存版",
            servingsText: "8人分",
            ingredientLinesText: ingredients,
            instructionLinesText: instructions
        )

        let outputURL = try RecipePDFExporter().exportSingle(recipe: recipe)
        let document = try XCTUnwrap(CGPDFDocument(outputURL as CFURL))
        let searchableDocument = try XCTUnwrap(PDFKit.PDFDocument(url: outputURL))
        let firstPageText = try XCTUnwrap(searchableDocument.page(at: 0)?.string)
        let continuationText = (1..<searchableDocument.pageCount)
            .compactMap { searchableDocument.page(at: $0)?.string }
            .joined(separator: "\n")

        XCTAssertGreaterThan(document.numberOfPages, 1)
        XCTAssertLessThan(document.numberOfPages, 20)
        XCTAssertTrue(firstPageText.contains("材料48"))
        XCTAssertFalse(continuationText.contains("材料（つづき）"))
    }

    func testModeratelyCrowdedIngredientsShrinkBeforeExpanding() throws {
        let ingredients = (1...9).map {
            "材料番号\($0) 100g（薄切りにして水気を切る）"
        }.joined(separator: "\n")
        let recipe = Recipe(
            title: "香味野菜の軽いマリネ",
            summary: "材料欄を読みやすく一ページにまとめるレシピ。",
            sourceURLString: "",
            servingsText: "4人分",
            ingredientLinesText: ingredients,
            instructionLinesText: "材料を切ってボウルに入れる。\n調味料を加え、全体をやさしく和える。"
        )

        let outputURL = try RecipePDFExporter().exportSingle(recipe: recipe)
        let document = try XCTUnwrap(CGPDFDocument(outputURL as CFURL))
        let searchableDocument = try XCTUnwrap(PDFKit.PDFDocument(url: outputURL))
        let firstPageText = try XCTUnwrap(searchableDocument.page(at: 0)?.string)

        XCTAssertEqual(document.numberOfPages, 1)
        XCTAssertTrue(firstPageText.contains("材料番号9"))
        XCTAssertTrue(firstPageText.contains("作り方"))
    }

    func testIngredientHeavyRecipeUsesRemainingSpaceForInstructions() throws {
        let ingredients = (1...16).map {
            "季節の材料\($0) 120g（角切り）"
        }.joined(separator: "\n")
        let recipe = Recipe(
            title: "十六種の野菜を使ったごちそう煮込み",
            summary: "材料を一度に確認できることを優先した、品数の多いレシピ。",
            sourceURLString: "",
            notes: "材料をすべて計量してから調理を始める。",
            tagsText: "煮込み, 野菜",
            servingsText: "6人分",
            ingredientLinesText: ingredients,
            instructionLinesText: "厚手の鍋を温め、香味野菜を弱火で炒める。\n残りの材料を順番に加え、全体へ油をなじませる。\n蓋をして弱火で30分煮込み、塩で味を整える。\n火を止めて10分休ませ、器に盛り付ける。\n仕上げのオイルを回しかけ、香りを整える。\n刻んだ香草を散らし、温かいうちにいただく。"
        )

        let outputURL = try RecipePDFExporter().exportSingle(recipe: recipe)
        let document = try XCTUnwrap(CGPDFDocument(outputURL as CFURL))
        let searchableDocument = try XCTUnwrap(PDFKit.PDFDocument(url: outputURL))
        let firstPageText = try XCTUnwrap(searchableDocument.page(at: 0)?.string)

        XCTAssertEqual(document.numberOfPages, 1)
        XCTAssertTrue(firstPageText.contains("季節の材料16"))
        XCTAssertTrue(firstPageText.contains("作り方"))
        XCTAssertTrue(firstPageText.contains("刻んだ香草"))

        let attachment = XCTAttachment(contentsOfFile: outputURL)
        attachment.name = "IngredientHeavyRecipePreview.pdf"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testInstructionContinuationKeepsCardPresentation() throws {
        let instructions = (1...14).map {
            "工程\($0)では火加減と香りを確認し、全体をやさしく混ぜながら丁寧に仕上げる。"
        }.joined(separator: "\n")
        let recipe = Recipe(
            title: "手順を丁寧に残す煮込み料理",
            summary: "工程数が多い場合の継続ページを確認するレシピ。",
            sourceURLString: "",
            servingsText: "4人分",
            ingredientLinesText: "玉ねぎ 1個\nにんじん 1本\nトマト 2個\n豆 200g\n香草 適量",
            instructionLinesText: instructions
        )

        let outputURL = try RecipePDFExporter().exportSingle(recipe: recipe)
        let document = try XCTUnwrap(CGPDFDocument(outputURL as CFURL))
        let searchableDocument = try XCTUnwrap(PDFKit.PDFDocument(url: outputURL))
        let firstPageText = try XCTUnwrap(searchableDocument.page(at: 0)?.string)
        let secondPageText = try XCTUnwrap(searchableDocument.page(at: 1)?.string)

        XCTAssertGreaterThan(document.numberOfPages, 1)
        XCTAssertTrue(firstPageText.contains("工程1"))
        XCTAssertTrue(secondPageText.contains("作り方（つづき）"))

        let attachment = XCTAttachment(contentsOfFile: outputURL)
        attachment.name = "InstructionContinuationPreview.pdf"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCollectionExportIncludesDesignedCover() throws {
        let recipe = Recipe(
            title: "檸檬とハーブのローストチキン",
            summary: "週末の食卓に似合う、香りのよいオーブン料理。",
            sourceURLString: "https://example.com/roast-chicken",
            sourceHost: "example.com",
            notes: "焼く30分前に冷蔵庫から出しておく。",
            tagsText: "おもてなし, オーブン",
            servingsText: "4人分",
            ingredientLinesText: "鶏もも肉 2枚\nレモン 1個\nローズマリー 2枝\nにんにく 1片\n塩 小さじ1",
            instructionLinesText: "鶏肉に塩をなじませる。\nレモンとハーブを添える。\n200℃のオーブンで香ばしく焼く。"
        )

        let outputURL = try RecipePDFExporter().exportAll(recipes: [recipe])
        let document = try XCTUnwrap(CGPDFDocument(outputURL as CFURL))

        XCTAssertEqual(document.numberOfPages, 2)
        let attachment = XCTAttachment(contentsOfFile: outputURL)
        attachment.name = "RecipePDFCollectionPreview.pdf"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func makeSampleFoodImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 960, height: 720)).image { renderer in
            let context = renderer.cgContext
            let colors = [
                UIColor(red: 0.95, green: 0.77, blue: 0.40, alpha: 1).cgColor,
                UIColor(red: 0.58, green: 0.25, blue: 0.12, alpha: 1).cgColor
            ] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 960, y: 720), options: [])

            UIColor(red: 0.97, green: 0.91, blue: 0.74, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: 180, y: 92, width: 600, height: 540)).fill()
            UIColor(red: 0.78, green: 0.52, blue: 0.18, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: 224, y: 132, width: 512, height: 456)).fill()

            for (origin, color) in [
                (CGPoint(x: 332, y: 244), UIColor(red: 0.20, green: 0.48, blue: 0.24, alpha: 1)),
                (CGPoint(x: 476, y: 190), UIColor(red: 0.87, green: 0.21, blue: 0.15, alpha: 1)),
                (CGPoint(x: 548, y: 352), UIColor(red: 0.93, green: 0.76, blue: 0.22, alpha: 1)),
                (CGPoint(x: 386, y: 416), UIColor(red: 0.34, green: 0.56, blue: 0.26, alpha: 1))
            ] {
                color.setFill()
                UIBezierPath(ovalIn: CGRect(origin: origin, size: CGSize(width: 84, height: 72))).fill()
            }
        }
    }
}
