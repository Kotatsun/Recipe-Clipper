import XCTest
@testable import RecipeClipping

@MainActor
final class RecipeChecklistTests: XCTestCase {
    func testToggleAddsAndRemovesCheckedState() {
        let recipe = Recipe(
            title: "テスト",
            sourceURLString: "https://example.com/r/1",
            ingredientLinesText: "にんじん 1本\n塩 少々"
        )

        XCTAssertFalse(recipe.isIngredientChecked("にんじん 1本"))

        recipe.toggleIngredientChecked("にんじん 1本")
        XCTAssertTrue(recipe.isIngredientChecked("にんじん 1本"))
        XCTAssertEqual(recipe.checkedIngredientLines, ["にんじん 1本"])

        recipe.toggleIngredientChecked("塩 少々")
        XCTAssertEqual(recipe.checkedIngredientLines, ["にんじん 1本", "塩 少々"])

        recipe.toggleIngredientChecked("にんじん 1本")
        XCTAssertFalse(recipe.isIngredientChecked("にんじん 1本"))
        XCTAssertEqual(recipe.checkedIngredientLines, ["塩 少々"])
    }

    func testRefreshDerivedFieldsPrunesChecksForRemovedIngredients() {
        let recipe = Recipe(
            title: "テスト",
            sourceURLString: "https://example.com/r/1",
            ingredientLinesText: "にんじん 1本\n塩 少々"
        )
        recipe.toggleIngredientChecked("にんじん 1本")
        recipe.toggleIngredientChecked("塩 少々")

        // 材料の編集で「塩 少々」が消えたら、そのチェック状態も捨てられる
        recipe.ingredientLinesText = "にんじん 1本\nだいこん 1/2本"
        recipe.refreshDerivedFields()

        XCTAssertEqual(recipe.checkedIngredientLines, ["にんじん 1本"])
    }
}
