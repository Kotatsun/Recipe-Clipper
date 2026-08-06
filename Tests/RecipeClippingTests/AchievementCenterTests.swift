import XCTest
@testable import RecipeClipping

@MainActor
final class AchievementCenterTests: XCTestCase {
    func testAchievementsAreDerivedFromExistingRecipeData() throws {
        let first = Recipe(
            title: "A",
            sourceURLString: "https://instagram.com/a",
            localImageFileName: "a.jpg",
            notes: "次回は少し薄味にする",
            tagsText: "和食, 時短, 肉, 定番",
            ingredientLinesText: "肉 200g",
            instructionLinesText: "焼く",
            sourceKindRaw: "instagram"
        )
        first.isFavorite = true
        first.rating = 5
        first.wantsRemake = true
        first.cookLogs = (0..<3).map { index in
            CookLog(
                memo: index < 2 ? "おいしくできた" : "",
                localImageFileName: index == 0 ? "cook.jpg" : nil,
                recipe: first
            )
        }

        let second = Recipe(
            title: "B",
            sourceURLString: "https://cookpad.com/b",
            localImageFileName: "b.jpg",
            tagsText: "洋食, 野菜, 煮込み",
            sourceKindRaw: "cookpad"
        )
        second.rating = 4

        let third = Recipe(
            title: "C",
            sourceURLString: "https://youtube.com/c",
            tagsText: "おやつ, 冷たい, 夏",
            sourceKindRaw: "youtube"
        )

        let snapshot = AchievementSnapshot(recipes: [first, second, third])
        XCTAssertEqual(snapshot.recipeCount, 3)
        XCTAssertEqual(snapshot.cookCount, 3)
        XCTAssertEqual(snapshot.cookedRecipeCount, 1)
        XCTAssertEqual(snapshot.cookingDayCount, 1)
        XCTAssertEqual(snapshot.longestCookingWeekStreak, 1)
        XCTAssertEqual(snapshot.photoCount, 2)
        XCTAssertEqual(snapshot.cookLogPhotoCount, 1)
        XCTAssertEqual(snapshot.completeRecipeCount, 1)
        XCTAssertEqual(snapshot.recipeNoteCount, 1)
        XCTAssertEqual(snapshot.cookLogMemoCount, 2)
        XCTAssertEqual(snapshot.highlyRatedCount, 2)
        XCTAssertEqual(snapshot.uniqueTagCount, 10)
        XCTAssertEqual(snapshot.sourceKindCount, 3)
        XCTAssertEqual(snapshot.mostCookedRecipeCount, 3)

        let achievements = AchievementCenter.achievements(for: [first, second, third])
        XCTAssertEqual(achievements.count, 38)
        XCTAssertEqual(achievements.filter { $0.category == .collection }.count, 9)
        XCTAssertEqual(achievements.filter { $0.category == .cooking }.count, 14)
        XCTAssertEqual(achievements.filter { $0.category == .discovery }.count, 8)
        XCTAssertEqual(achievements.filter { $0.category == .journal }.count, 7)
        XCTAssertTrue(try XCTUnwrap(achievements.first { $0.id == "first-clip" }).isUnlocked)
        XCTAssertTrue(try XCTUnwrap(achievements.first { $0.id == "signature" }).isUnlocked)
        XCTAssertTrue(try XCTUnwrap(achievements.first { $0.id == "sources" }).isUnlocked)
        XCTAssertTrue(try XCTUnwrap(achievements.first { $0.id == "tags" }).isUnlocked)
        XCTAssertFalse(try XCTUnwrap(achievements.first { $0.id == "recipe-shelf" }).isUnlocked)
    }

    func testWeeklyCookingStreakUsesConsecutiveCalendarWeeks() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let firstDate = calendar.date(from: DateComponents(year: 2026, month: 1, day: 7, hour: 12))!
        let recipe = Recipe(title: "A", sourceURLString: "https://example.com/a")
        recipe.cookLogs = (0..<4).map { offset in
            CookLog(
                cookedAt: calendar.date(byAdding: .weekOfYear, value: offset, to: firstDate)!,
                recipe: recipe
            )
        }

        let snapshot = AchievementSnapshot(recipes: [recipe])

        XCTAssertEqual(snapshot.longestCookingWeekStreak, 4)
        XCTAssertTrue(
            AchievementCenter.achievements(for: [recipe])
                .first { $0.id == "streak-four" }?
                .isUnlocked == true
        )
    }

    func testFourRoutesCountsOnlyClippingSourceKinds() throws {
        let rawValues = ["instagram", "youtube", "cookpad", "web", "original", "other", "legacy-source"]
        let recipes = rawValues.enumerated().map { index, rawValue in
            Recipe(
                title: "Recipe \(index)",
                sourceURLString: "https://example.com/\(index)",
                sourceKindRaw: rawValue
            )
        }

        let snapshot = AchievementSnapshot(recipes: recipes)
        let achievement = try XCTUnwrap(
            AchievementCenter.achievements(for: recipes).first { $0.id == "sources-four" }
        )

        XCTAssertEqual(snapshot.sourceKindCount, 4)
        XCTAssertEqual(achievement.title, "四つの航路")
        XCTAssertEqual(achievement.target, 4)
        XCTAssertTrue(achievement.isUnlocked)
    }

    func testNextAchievementPrefersClosestLockedMilestone() throws {
        let recipes = (0..<8).map { index in
            Recipe(title: "Recipe \(index)", sourceURLString: "https://example.com/\(index)")
        }
        let achievements = AchievementCenter.achievements(for: recipes)
        let next = try XCTUnwrap(AchievementCenter.nextAchievement(in: achievements))

        XCTAssertEqual(next.id, "recipe-shelf")
        XCTAssertEqual(next.progress, 0.8, accuracy: 0.001)
    }

    func testProgressIsCappedAfterUnlocking() throws {
        let recipes = (0..<35).map { index in
            Recipe(title: "Recipe \(index)", sourceURLString: "https://example.com/\(index)")
        }
        let library = try XCTUnwrap(
            AchievementCenter.achievements(for: recipes).first { $0.id == "recipe-library" }
        )

        XCTAssertTrue(library.isUnlocked)
        XCTAssertEqual(library.progress, 1)
        XCTAssertEqual(library.progressText, "30 / 30品")
    }

    func testKitchenTitleReflectsTotalProgressWhenSeriesAreBalanced() {
        let title = AchievementCenter.kitchenTitle(
            totalUnlocked: 12,
            totalAchievements: 38,
            unlockedByCategory: [.collection: 3, .cooking: 4, .discovery: 3, .journal: 2],
            totalsByCategory: [.collection: 9, .cooking: 14, .discovery: 8, .journal: 7]
        )

        XCTAssertEqual(title.id, "home-cook")
        XCTAssertEqual(title.name, "暮らしの料理人")
        XCTAssertEqual(title.symbol, "frying.pan.fill")
    }

    func testKitchenTitleReflectsStrongestSeries() {
        let title = AchievementCenter.kitchenTitle(
            totalUnlocked: 8,
            totalAchievements: 38,
            unlockedByCategory: [.collection: 5, .cooking: 1, .discovery: 1, .journal: 1],
            totalsByCategory: [.collection: 9, .cooking: 14, .discovery: 8, .journal: 7]
        )

        XCTAssertEqual(title.id, "collector")
        XCTAssertEqual(title.name, "レシピ蒐集家")
        XCTAssertEqual(title.symbol, "books.vertical.fill")
    }

    func testKitchenTitleUsesSeriesMasteryAndGrandTitle() {
        let totals: [KitchenAchievement.Category: Int] = [
            .collection: 9, .cooking: 14, .discovery: 8, .journal: 7
        ]
        let cookingMaster = AchievementCenter.kitchenTitle(
            totalUnlocked: 14,
            totalAchievements: 38,
            unlockedByCategory: [.cooking: 14],
            totalsByCategory: totals
        )
        let grandTitle = AchievementCenter.kitchenTitle(
            totalUnlocked: 38,
            totalAchievements: 38,
            unlockedByCategory: totals,
            totalsByCategory: totals
        )

        XCTAssertEqual(cookingMaster.id, "flame-master")
        XCTAssertEqual(cookingMaster.name, "炎のマエストロ")
        XCTAssertEqual(grandTitle.id, "legend")
        XCTAssertEqual(grandTitle.name, "台所の伝説")
    }

    func testTitleMilestonesExposeAllUnlockConditions() throws {
        let achievements = AchievementCenter.achievements(for: [])
        let milestones = AchievementCenter.titleMilestones(in: achievements)

        XCTAssertEqual(milestones.count, 18)
        XCTAssertEqual(milestones.filter { $0.group == .journey }.count, 10)
        XCTAssertEqual(milestones.filter { $0.group == .specialist }.count, 4)
        XCTAssertEqual(milestones.filter { $0.group == .mastery }.count, 4)

        let beginner = try XCTUnwrap(milestones.first { $0.id == "beginner" })
        XCTAssertEqual(beginner.target, 1)
        XCTAssertFalse(beginner.isUnlocked)

        let collector = try XCTUnwrap(milestones.first { $0.id == "collector" })
        XCTAssertEqual(collector.target, 5)
        XCTAssertEqual(collector.condition, "「レシピ蒐集」の勲章を5個解除する")

        let archiveMaster = try XCTUnwrap(milestones.first { $0.id == "archive-master" })
        XCTAssertEqual(archiveMaster.target, 9)
        XCTAssertEqual(archiveMaster.progressText, "0 / 9")
    }

    func testSpecialistTitleUsesTheSameVisibleThresholdAsTitleGallery() {
        let beforeUnlock = AchievementCenter.kitchenTitle(
            totalUnlocked: 7,
            totalAchievements: 38,
            unlockedByCategory: [.cooking: 5, .collection: 1, .journal: 1],
            totalsByCategory: [.collection: 9, .cooking: 14, .discovery: 8, .journal: 7]
        )
        let atUnlock = AchievementCenter.kitchenTitle(
            totalUnlocked: 8,
            totalAchievements: 38,
            unlockedByCategory: [.cooking: 6, .collection: 1, .journal: 1],
            totalsByCategory: [.collection: 9, .cooking: 14, .discovery: 8, .journal: 7]
        )

        XCTAssertEqual(beforeUnlock.id, "explorer")
        XCTAssertEqual(atUnlock.id, "daily-cook")
    }

    func testUnlockedTitleCanBeEquippedAndLockedTitleFallsBackToRecommendation() {
        let recipes = (0..<10).map { index in
            Recipe(title: "Recipe \(index)", sourceURLString: "https://example.com/\(index)")
        }
        let achievements = AchievementCenter.achievements(for: recipes)

        let equipped = AchievementCenter.equippedTitle(
            in: achievements,
            selectedTitleID: "beginner"
        )
        let lockedSelection = AchievementCenter.equippedTitle(
            in: achievements,
            selectedTitleID: "legend"
        )

        XCTAssertEqual(equipped.id, "beginner")
        XCTAssertEqual(lockedSelection.id, AchievementCenter.kitchenTitle(in: achievements).id)
    }
}
