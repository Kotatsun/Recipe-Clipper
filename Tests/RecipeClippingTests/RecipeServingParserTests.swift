import XCTest
@testable import RecipeClipping

final class RecipeServingParserTests: XCTestCase {
    func testExtractsServingFromJapaneseIngredientHeading() {
        let text = """
        肉じゃが
        材料（2〜3人分）
        玉ねぎ 1個
        豚肉 200g
        """

        XCTAssertEqual(RecipeServingParser.extract(from: text), "2〜3人分")
        XCTAssertEqual(PlainRecipeTextParser().parse(text).servings, "2〜3人分")
    }

    func testExtractsServingFromRecipeLabelAndEnglishYield() {
        XCTAssertEqual(RecipeServingParser.extract(from: "〈レシピ/2人分〉\n材料"), "2人分")
        XCTAssertEqual(RecipeServingParser.extract(from: "Ingredients\nFlour", explicitYield: "Serves 4"), "4人分")
    }

    func testDoesNotTreatIngredientQuantityAsRecipeServing() {
        let text = """
        材料
        冷凍うどん 2人前
        めんつゆ 大さじ2
        """

        XCTAssertNil(RecipeServingParser.extract(from: text))
    }

    func testJSONLDYieldTakesPriority() {
        let result = RecipeTextExtractor().extract(from: RecipeTextExtractorInput(
            visibleText: "材料\n小麦粉 100g\n作り方\n1. 混ぜる",
            jsonLDRecipes: [JSONLDRecipe(
                title: "パンケーキ",
                description: nil,
                imageURL: nil,
                ingredients: ["小麦粉 100g"],
                instructions: ["混ぜる"],
                servings: "6 servings"
            )]
        ))

        XCTAssertEqual(result.servings, "6人分")
    }

    func testImporterReadsRecipeYieldFromJSONLD() throws {
        let html = """
        <script type="application/ld+json">
        {
          "@type": "Recipe",
          "name": "スープ",
          "recipeYield": "4 servings",
          "recipeIngredient": ["水 400ml", "塩 小さじ1"],
          "recipeInstructions": [{"@type": "HowToStep", "text": "鍋で煮る"}]
        }
        </script>
        """
        let url = try XCTUnwrap(URL(string: "https://example.com/soup"))
        let fetched = RecipeImporter().parseFetchedContent(html: html, inputURL: url)
        let jsonRecipe = try XCTUnwrap(fetched.jsonLDRecipes.first)

        XCTAssertEqual(jsonRecipe.servings, "4 servings")
        let extracted = RecipeTextExtractor().extract(from: RecipeTextExtractorInput(
            visibleText: fetched.extractorInputText,
            jsonLDRecipes: fetched.jsonLDRecipes
        ))
        XCTAssertEqual(extracted.servings, "4人分")
    }

    func testRecipeAllowsEmptyServingAndNormalizesEnteredValue() {
        let legacyStyleRecipe = Recipe(title: "旧レシピ", sourceURLString: "")
        XCTAssertEqual(legacyStyleRecipe.servingsText, "")

        let recipe = Recipe(
            title: "新レシピ",
            sourceURLString: "",
            servingsText: "  2〜3人分\n"
        )
        XCTAssertEqual(recipe.servingsText, "2〜3人分")
    }
}
