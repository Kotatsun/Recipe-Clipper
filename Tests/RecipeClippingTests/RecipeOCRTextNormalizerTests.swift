import XCTest
import CoreGraphics
@testable import RecipeClipping

final class RecipeOCRTextNormalizerTests: XCTestCase {
    private let parser = PlainRecipeTextParser()

    func testReconstructsFragmentsOnTheSameVisualRowBeforeParsing() {
        let fragments = [
            fragment("肉じゃが", x: 0.08, y: 0.90, width: 0.25),
            fragment("材", x: 0.08, y: 0.80, width: 0.06),
            fragment("料", x: 0.145, y: 0.80, width: 0.06),
            fragment("玉ねぎ", x: 0.08, y: 0.70, width: 0.20),
            fragment("1個", x: 0.68, y: 0.695, width: 0.12),
            fragment("豚肉", x: 0.08, y: 0.62, width: 0.16),
            fragment("200g", x: 0.66, y: 0.618, width: 0.15),
            fragment("作り方", x: 0.08, y: 0.50, width: 0.24),
            fragment("1.", x: 0.08, y: 0.40, width: 0.06),
            fragment("玉ねぎを切る", x: 0.17, y: 0.396, width: 0.45),
            fragment("2.", x: 0.08, y: 0.30, width: 0.06),
            fragment("豚肉と炒める", x: 0.17, y: 0.298, width: 0.45)
        ]

        let text = RecipeOCRTextNormalizer.reconstructedText(from: fragments)
        let result = parser.parse(text)

        XCTAssertTrue(text.contains("材料"), text)
        XCTAssertTrue(text.contains("玉ねぎ 1個"), text)
        XCTAssertTrue(text.contains("豚肉 200g"), text)
        XCTAssertEqual(result.ingredients, ["玉ねぎ 1個", "豚肉 200g"])
        XCTAssertEqual(result.instructions.count, 2)
        XCTAssertTrue(result.instructions[0].contains("玉ねぎを切る"))
        XCTAssertTrue(result.instructions[1].contains("豚肉と炒める"))
    }

    func testNormalizesSpacedHeadingsAndStandaloneInstructionNumbers() {
        let rawText = """
        肉じゃが
        材 料
        玉ねぎ 1個
        豚肉 200g
        作 り 方
        1
        玉ねぎを切る
        2
        豚肉と炒める
        """

        let text = RecipeOCRTextNormalizer.normalizedText(rawText)
        let result = parser.parse(text)

        XCTAssertTrue(text.contains("材料\n"), text)
        XCTAssertTrue(text.contains("作り方\n1. 玉ねぎを切る"), text)
        XCTAssertEqual(result.ingredients, ["玉ねぎ 1個", "豚肉 200g"])
        XCTAssertEqual(result.instructions.count, 2)
    }

    func testKeepsStandaloneNumbersInIngredientSectionSeparate() {
        let rawText = """
        材料
        1
        玉ねぎ 1個
        作り方
        1
        玉ねぎを切る
        """

        let text = RecipeOCRTextNormalizer.normalizedText(rawText)

        XCTAssertTrue(text.contains("材料\n1\n玉ねぎ 1個"), text)
        XCTAssertTrue(text.contains("作り方\n1. 玉ねぎを切る"), text)
    }

    private func fragment(
        _ text: String,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat = 0.05
    ) -> RecipeOCRTextFragment {
        RecipeOCRTextFragment(
            text: text,
            boundingBox: CGRect(x: x, y: y, width: width, height: height)
        )
    }
}
