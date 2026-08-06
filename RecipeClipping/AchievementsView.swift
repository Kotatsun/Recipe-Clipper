import SwiftUI

struct AchievementSnapshot {
    let recipeCount: Int
    let cookCount: Int
    let cookedRecipeCount: Int
    let cookingDayCount: Int
    let longestCookingWeekStreak: Int
    let favoriteCount: Int
    let photoCount: Int
    let cookLogPhotoCount: Int
    let completeRecipeCount: Int
    let recipeNoteCount: Int
    let cookLogMemoCount: Int
    let highlyRatedCount: Int
    let remakeCount: Int
    let uniqueTagCount: Int
    let sourceKindCount: Int
    let mostCookedRecipeCount: Int

    init(recipes: [Recipe]) {
        let cookLogs = recipes.flatMap(\.cookLogs)
        let calendar = Calendar.current
        recipeCount = recipes.count
        cookCount = cookLogs.count
        cookedRecipeCount = recipes.filter { !$0.cookLogs.isEmpty }.count
        cookingDayCount = Set(cookLogs.map { calendar.startOfDay(for: $0.cookedAt) }).count
        longestCookingWeekStreak = Self.longestWeekStreak(
            dates: cookLogs.map(\.cookedAt),
            calendar: calendar
        )
        favoriteCount = recipes.filter(\.isFavorite).count
        photoCount = recipes.filter { $0.localImageFileName?.isEmpty == false }.count
        cookLogPhotoCount = cookLogs.filter { $0.localImageFileName?.isEmpty == false }.count
        completeRecipeCount = recipes.filter {
            !$0.ingredientLines.isEmpty && !$0.instructionLines.isEmpty
        }.count
        recipeNoteCount = recipes.filter {
            !$0.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
        cookLogMemoCount = cookLogs.filter { log in
            [log.memo, log.improvementMemo, log.arrangementMemo].contains {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }.count
        highlyRatedCount = recipes.filter { $0.rating >= 4 }.count
        remakeCount = recipes.filter(\.wantsRemake).count
        uniqueTagCount = Set(recipes.flatMap(\.tags).map { $0.lowercased() }).count
        let clippingSourceKinds = Set([
            RecipeSourceKind.instagram.rawValue,
            RecipeSourceKind.youtube.rawValue,
            RecipeSourceKind.cookpad.rawValue,
            RecipeSourceKind.web.rawValue
        ])
        sourceKindCount = Set(recipes.map(\.sourceKindRaw).filter(clippingSourceKinds.contains)).count
        mostCookedRecipeCount = recipes.map { $0.cookLogs.count }.max() ?? 0
    }

    private static func longestWeekStreak(dates: [Date], calendar: Calendar) -> Int {
        let weekStarts = Set(dates.compactMap { calendar.dateInterval(of: .weekOfYear, for: $0)?.start })
            .sorted()
        guard !weekStarts.isEmpty else { return 0 }

        var longest = 1
        var current = 1
        for index in weekStarts.indices.dropFirst() {
            let previous = weekStarts[weekStarts.index(before: index)]
            let expected = calendar.date(byAdding: .weekOfYear, value: 1, to: previous)
            if expected == weekStarts[index] {
                current += 1
                longest = max(longest, current)
            } else {
                current = 1
            }
        }
        return longest
    }
}

struct KitchenAchievement: Identifiable {
    enum Category: String, CaseIterable, Identifiable {
        case collection
        case cooking
        case discovery
        case journal

        var id: String { rawValue }

        var title: String {
            switch self {
            case .collection: "レシピ蒐集"
            case .cooking: "料理の腕前"
            case .discovery: "味の探究"
            case .journal: "台所の記録"
            }
        }

        var subtitle: String {
            switch self {
            case .collection: "COLLECTION"
            case .cooking: "COOKING"
            case .discovery: "DISCOVERY"
            case .journal: "JOURNAL"
            }
        }

        var symbol: String {
            switch self {
            case .collection: "books.vertical.fill"
            case .cooking: "flame.fill"
            case .discovery: "safari.fill"
            case .journal: "pencil.and.scribble"
            }
        }
    }

    enum Tone {
        case copper
        case gold
        case basil
        case berry

        var colors: [Color] {
            switch self {
            case .copper: [Color(red: 0.98, green: 0.61, blue: 0.30), RecipePalette.tomato]
            case .gold: [Color(red: 1.00, green: 0.84, blue: 0.38), Color(red: 0.91, green: 0.50, blue: 0.12)]
            case .basil: [RecipePalette.leafLight, RecipePalette.basil]
            case .berry: [Color(red: 0.86, green: 0.40, blue: 0.50), Color(red: 0.55, green: 0.17, blue: 0.30)]
            }
        }
    }

    let id: String
    let category: Category
    let eyebrow: String
    let title: String
    let detail: String
    let symbol: String
    let current: Int
    let target: Int
    let unit: String
    let tone: Tone

    var isUnlocked: Bool { current >= target }
    var progress: Double { min(Double(current) / Double(target), 1) }
    var progressText: String { "\(min(current, target)) / \(target)\(unit)" }
}

struct KitchenTitle {
    let id: String
    let name: String
    let symbol: String
    let tone: KitchenAchievement.Tone
}

struct KitchenTitleMilestone: Identifiable {
    enum Group: String, CaseIterable, Identifiable {
        case journey
        case specialist
        case mastery

        var id: String { rawValue }

        var title: String {
            switch self {
            case .journey: "料理人の歩み"
            case .specialist: "シリーズ特化"
            case .mastery: "シリーズ制覇"
            }
        }

        var subtitle: String {
            switch self {
            case .journey: "勲章の総獲得数で解禁"
            case .specialist: "ひとつの分野を深く究めて解禁"
            case .mastery: "シリーズの勲章をすべて集めて解禁"
            }
        }
    }

    let title: KitchenTitle
    let group: Group
    let condition: String
    let current: Int
    let target: Int

    var id: String { title.id }
    var isUnlocked: Bool { target == 0 || current >= target }
    var progress: Double {
        guard target > 0 else { return 1 }
        return min(Double(current) / Double(target), 1)
    }
    var progressText: String {
        guard target > 0 else { return "最初から解禁" }
        return "\(min(current, target)) / \(target)"
    }
}

enum KitchenTitlePreference {
    static let selectedTitleIDKey = "SelectedKitchenTitleID"
}

enum AchievementCenter {
    private struct CategoryStanding {
        let category: KitchenAchievement.Category
        let unlocked: Int
        let ratio: Double
    }

    static func achievements(for recipes: [Recipe]) -> [KitchenAchievement] {
        let snapshot = AchievementSnapshot(recipes: recipes)
        return achievements(for: snapshot)
    }

    static func achievements(for value: AchievementSnapshot) -> [KitchenAchievement] {
        [
            KitchenAchievement(
                id: "first-clip", category: .collection, eyebrow: "FIRST CLIP", title: "はじめの一皿",
                detail: "最初のレシピをクリップ", symbol: "bookmark.fill",
                current: value.recipeCount, target: 1, unit: "品", tone: .copper
            ),
            KitchenAchievement(
                id: "recipe-shelf", category: .collection, eyebrow: "COLLECTION I", title: "小さなレシピ棚",
                detail: "レシピを10品集める", symbol: "books.vertical.fill",
                current: value.recipeCount, target: 10, unit: "品", tone: .basil
            ),
            KitchenAchievement(
                id: "recipe-library", category: .collection, eyebrow: "COLLECTION II", title: "わたしの料理書庫",
                detail: "レシピを30品集める", symbol: "building.columns.fill",
                current: value.recipeCount, target: 30, unit: "品", tone: .gold
            ),
            KitchenAchievement(
                id: "recipe-archive", category: .collection, eyebrow: "COLLECTION III", title: "六十皿の景色",
                detail: "レシピを60品集める", symbol: "archivebox.fill",
                current: value.recipeCount, target: 60, unit: "品", tone: .berry
            ),
            KitchenAchievement(
                id: "recipe-century", category: .collection, eyebrow: "GRAND ARCHIVE", title: "百皿料理帖",
                detail: "レシピを100品集める", symbol: "crown.fill",
                current: value.recipeCount, target: 100, unit: "品", tone: .gold
            ),
            KitchenAchievement(
                id: "favorites", category: .collection, eyebrow: "CURATOR I", title: "選りすぐり",
                detail: "お気に入りを5品選ぶ", symbol: "heart.fill",
                current: value.favoriteCount, target: 5, unit: "品", tone: .berry
            ),
            KitchenAchievement(
                id: "favorites-master", category: .collection, eyebrow: "CURATOR II", title: "私撰・名菜二十選",
                detail: "お気に入りを20品選ぶ", symbol: "heart.circle.fill",
                current: value.favoriteCount, target: 20, unit: "品", tone: .gold
            ),
            KitchenAchievement(
                id: "photos", category: .collection, eyebrow: "FOOD MEMORY", title: "おいしい記憶",
                detail: "写真つきレシピを10品残す", symbol: "camera.fill",
                current: value.photoCount, target: 10, unit: "品", tone: .gold
            ),
            KitchenAchievement(
                id: "photo-collection", category: .collection, eyebrow: "VISUAL ARCHIVE", title: "写真でめくる料理帖",
                detail: "写真つきレシピを25品残す", symbol: "photo.stack.fill",
                current: value.photoCount, target: 25, unit: "品", tone: .basil
            ),

            KitchenAchievement(
                id: "first-cook", category: .cooking, eyebrow: "FIRST COOK", title: "キッチン点火",
                detail: "初めてのCook Logを残す", symbol: "flame.fill",
                current: value.cookCount, target: 1, unit: "回", tone: .copper
            ),
            KitchenAchievement(
                id: "regular-cook", category: .cooking, eyebrow: "ROUTINE I", title: "台所の常連",
                detail: "料理した記録を10回残す", symbol: "frying.pan.fill",
                current: value.cookCount, target: 10, unit: "回", tone: .gold
            ),
            KitchenAchievement(
                id: "cook-thirty", category: .cooking, eyebrow: "ROUTINE II", title: "日々の料理人",
                detail: "料理した記録を30回残す", symbol: "fork.knife",
                current: value.cookCount, target: 30, unit: "回", tone: .basil
            ),
            KitchenAchievement(
                id: "cook-seventy-five", category: .cooking, eyebrow: "ROUTINE III", title: "七十五回の食卓",
                detail: "料理した記録を75回残す", symbol: "table.furniture.fill",
                current: value.cookCount, target: 75, unit: "回", tone: .berry
            ),
            KitchenAchievement(
                id: "cook-one-fifty", category: .cooking, eyebrow: "MASTER COOK", title: "百五十皿の手仕事",
                detail: "料理した記録を150回残す", symbol: "medal.fill",
                current: value.cookCount, target: 150, unit: "回", tone: .gold
            ),
            KitchenAchievement(
                id: "cooked-variety-ten", category: .cooking, eyebrow: "REPERTOIRE I", title: "十皿のレパートリー",
                detail: "異なるレシピを10品作る", symbol: "square.grid.2x2.fill",
                current: value.cookedRecipeCount, target: 10, unit: "品", tone: .basil
            ),
            KitchenAchievement(
                id: "cooked-variety-thirty", category: .cooking, eyebrow: "REPERTOIRE II", title: "献立の万華鏡",
                detail: "異なるレシピを30品作る", symbol: "circle.grid.3x3.fill",
                current: value.cookedRecipeCount, target: 30, unit: "品", tone: .gold
            ),
            KitchenAchievement(
                id: "signature", category: .cooking, eyebrow: "SIGNATURE I", title: "十八番の一皿",
                detail: "同じレシピを3回作る", symbol: "repeat.circle.fill",
                current: value.mostCookedRecipeCount, target: 3, unit: "回", tone: .berry
            ),
            KitchenAchievement(
                id: "signature-five", category: .cooking, eyebrow: "SIGNATURE II", title: "手になじむレシピ",
                detail: "同じレシピを5回作る", symbol: "hand.thumbsup.fill",
                current: value.mostCookedRecipeCount, target: 5, unit: "回", tone: .basil
            ),
            KitchenAchievement(
                id: "signature-ten", category: .cooking, eyebrow: "SIGNATURE III", title: "我が家の定番",
                detail: "同じレシピを10回作る", symbol: "house.and.flag.fill",
                current: value.mostCookedRecipeCount, target: 10, unit: "回", tone: .gold
            ),
            KitchenAchievement(
                id: "streak-four", category: .cooking, eyebrow: "MOMENTUM I", title: "四週つづく台所",
                detail: "4週連続で料理を記録", symbol: "calendar.badge.checkmark",
                current: value.longestCookingWeekStreak, target: 4, unit: "週", tone: .copper
            ),
            KitchenAchievement(
                id: "streak-twelve", category: .cooking, eyebrow: "MOMENTUM II", title: "季節をつなぐ台所",
                detail: "12週連続で料理を記録", symbol: "calendar.circle.fill",
                current: value.longestCookingWeekStreak, target: 12, unit: "週", tone: .gold
            ),
            KitchenAchievement(
                id: "cooking-days-thirty", category: .cooking, eyebrow: "KITCHEN DAYS I", title: "三十日の手仕事",
                detail: "30日分の料理を記録", symbol: "sun.max.fill",
                current: value.cookingDayCount, target: 30, unit: "日", tone: .basil
            ),
            KitchenAchievement(
                id: "cooking-days-hundred", category: .cooking, eyebrow: "KITCHEN DAYS II", title: "百日の台所",
                detail: "100日分の料理を記録", symbol: "sparkles",
                current: value.cookingDayCount, target: 100, unit: "日", tone: .gold
            ),

            KitchenAchievement(
                id: "sources", category: .discovery, eyebrow: "EXPLORER I", title: "レシピ旅人",
                detail: "3種類の入手元から集める", symbol: "safari.fill",
                current: value.sourceKindCount, target: 3, unit: "種", tone: .basil
            ),
            KitchenAchievement(
                id: "sources-four", category: .discovery, eyebrow: "EXPLORER II", title: "四つの航路",
                detail: "4種類の入手元から集める", symbol: "map.fill",
                current: value.sourceKindCount, target: 4, unit: "種", tone: .gold
            ),
            KitchenAchievement(
                id: "tags", category: .discovery, eyebrow: "TAXONOMY I", title: "味の標本箱",
                detail: "10種類のタグで整理する", symbol: "tag.fill",
                current: value.uniqueTagCount, target: 10, unit: "種", tone: .basil
            ),
            KitchenAchievement(
                id: "tags-thirty", category: .discovery, eyebrow: "TAXONOMY II", title: "味覚の地図",
                detail: "30種類のタグで整理する", symbol: "tag.circle.fill",
                current: value.uniqueTagCount, target: 30, unit: "種", tone: .berry
            ),
            KitchenAchievement(
                id: "rating", category: .discovery, eyebrow: "TASTEMAKER I", title: "確かな舌",
                detail: "星4以上を5品見つける", symbol: "star.fill",
                current: value.highlyRatedCount, target: 5, unit: "品", tone: .gold
            ),
            KitchenAchievement(
                id: "rating-twenty", category: .discovery, eyebrow: "TASTEMAKER II", title: "二十皿の審美眼",
                detail: "星4以上を20品見つける", symbol: "stars",
                current: value.highlyRatedCount, target: 20, unit: "品", tone: .gold
            ),
            KitchenAchievement(
                id: "remake", category: .discovery, eyebrow: "ENCORE", title: "もう一度、の予感",
                detail: "また作りたいを5品選ぶ", symbol: "bookmark.fill",
                current: value.remakeCount, target: 5, unit: "品", tone: .berry
            ),
            KitchenAchievement(
                id: "remake-fifteen", category: .discovery, eyebrow: "ENCORE II", title: "再演を待つ食卓",
                detail: "また作りたいを15品選ぶ", symbol: "bookmark.fill",
                current: value.remakeCount, target: 15, unit: "品", tone: .berry
            ),

            KitchenAchievement(
                id: "complete-ten", category: .journal, eyebrow: "RECIPE CRAFT I", title: "整った十皿",
                detail: "材料と作り方を10品に残す", symbol: "checklist",
                current: value.completeRecipeCount, target: 10, unit: "品", tone: .basil
            ),
            KitchenAchievement(
                id: "complete-forty", category: .journal, eyebrow: "RECIPE CRAFT II", title: "頼れる料理帖",
                detail: "材料と作り方を40品に残す", symbol: "text.book.closed.fill",
                current: value.completeRecipeCount, target: 40, unit: "品", tone: .gold
            ),
            KitchenAchievement(
                id: "recipe-notes", category: .journal, eyebrow: "MARGINALIA", title: "余白のひとこと",
                detail: "レシピメモを10品に残す", symbol: "note.text",
                current: value.recipeNoteCount, target: 10, unit: "品", tone: .copper
            ),
            KitchenAchievement(
                id: "cook-memos", category: .journal, eyebrow: "COOK JOURNAL I", title: "気づきの記録",
                detail: "Cook Logメモを10回残す", symbol: "pencil.line",
                current: value.cookLogMemoCount, target: 10, unit: "回", tone: .basil
            ),
            KitchenAchievement(
                id: "cook-memos-forty", category: .journal, eyebrow: "COOK JOURNAL II", title: "育てるレシピ",
                detail: "Cook Logメモを40回残す", symbol: "book.closed.fill",
                current: value.cookLogMemoCount, target: 40, unit: "回", tone: .gold
            ),
            KitchenAchievement(
                id: "cook-photos", category: .journal, eyebrow: "FOOD MEMORY I", title: "おいしい記憶",
                detail: "Cook Log写真を10枚残す", symbol: "camera.fill",
                current: value.cookLogPhotoCount, target: 10, unit: "枚", tone: .berry
            ),
            KitchenAchievement(
                id: "cook-photos-forty", category: .journal, eyebrow: "FOOD MEMORY II", title: "食卓の写真集",
                detail: "Cook Log写真を40枚残す", symbol: "photo.on.rectangle.angled",
                current: value.cookLogPhotoCount, target: 40, unit: "枚", tone: .gold
            )
        ]
    }

    static func nextAchievement(in achievements: [KitchenAchievement]) -> KitchenAchievement? {
        achievements
            .filter { !$0.isUnlocked }
            .max { lhs, rhs in
                if lhs.progress == rhs.progress { return lhs.target > rhs.target }
                return lhs.progress < rhs.progress
            }
    }

    static func kitchenTitle(in achievements: [KitchenAchievement]) -> KitchenTitle {
        let unlocked = achievements.filter(\.isUnlocked)
        let unlockedByCategory = Dictionary(
            grouping: unlocked,
            by: \.category
        ).mapValues(\.count)
        let totalsByCategory = Dictionary(
            grouping: achievements,
            by: \.category
        ).mapValues(\.count)

        return kitchenTitle(
            totalUnlocked: unlocked.count,
            totalAchievements: achievements.count,
            unlockedByCategory: unlockedByCategory,
            totalsByCategory: totalsByCategory
        )
    }

    static func equippedTitle(
        in achievements: [KitchenAchievement],
        selectedTitleID: String
    ) -> KitchenTitle {
        if !selectedTitleID.isEmpty,
           let selected = titleMilestones(in: achievements).first(where: {
               $0.id == selectedTitleID && $0.isUnlocked
           }) {
            return selected.title
        }

        return kitchenTitle(in: achievements)
    }

    static func kitchenTitle(
        totalUnlocked: Int,
        totalAchievements: Int,
        unlockedByCategory: [KitchenAchievement.Category: Int],
        totalsByCategory: [KitchenAchievement.Category: Int]
    ) -> KitchenTitle {
        if totalAchievements > 0, totalUnlocked == totalAchievements {
            return KitchenTitle(id: "legend", name: "台所の伝説", symbol: "crown.fill", tone: .gold)
        }

        let completedCategories = KitchenAchievement.Category.allCases.filter { category in
            let total = totalsByCategory[category, default: 0]
            return total > 0 && unlockedByCategory[category, default: 0] == total
        }
        if let completed = completedCategories.max(by: {
            totalsByCategory[$0, default: 0] < totalsByCategory[$1, default: 0]
        }) {
            return masteryTitle(for: completed)
        }

        var rankedCategories: [CategoryStanding] = []
        for category in KitchenAchievement.Category.allCases {
            let unlocked = unlockedByCategory[category, default: 0]
            let total = totalsByCategory[category, default: 0]
            let ratio: Double
            if total == 0 {
                ratio = 0
            } else {
                ratio = Double(unlocked) / Double(total)
            }
            rankedCategories.append(
                CategoryStanding(category: category, unlocked: unlocked, ratio: ratio)
            )
        }
        rankedCategories.sort { lhs, rhs in
            if lhs.ratio == rhs.ratio {
                return lhs.unlocked > rhs.unlocked
            }
            return lhs.ratio > rhs.ratio
        }

        if let specialist = rankedCategories.first(where: {
            $0.unlocked >= specialistTarget(for: $0.category)
        }) {
            return specialistTitle(for: specialist.category)
        }

        switch totalUnlocked {
        case 0:
            return KitchenTitle(id: "prelude", name: "台所の旅支度", symbol: "fork.knife", tone: .copper)
        case 1...4:
            return KitchenTitle(id: "beginner", name: "はじまりの料理人", symbol: "sparkles", tone: .copper)
        case 5...9:
            return KitchenTitle(id: "explorer", name: "献立の探検家", symbol: "map.fill", tone: .basil)
        case 10...14:
            return KitchenTitle(id: "home-cook", name: "暮らしの料理人", symbol: "frying.pan.fill", tone: .basil)
        case 15...19:
            return KitchenTitle(id: "cultivator", name: "味を育てる人", symbol: "leaf.fill", tone: .berry)
        case 20...24:
            return KitchenTitle(id: "curator", name: "食卓のキュレーター", symbol: "star.circle.fill", tone: .berry)
        case 25...29:
            return KitchenTitle(id: "artisan", name: "百味の料理家", symbol: "medal.fill", tone: .gold)
        case 30...34:
            return KitchenTitle(id: "maestro", name: "台所のマエストロ", symbol: "trophy.fill", tone: .gold)
        default:
            return KitchenTitle(id: "golden-cook", name: "黄金の料理人", symbol: "crown.fill", tone: .gold)
        }
    }

    static func titleMilestones(in achievements: [KitchenAchievement]) -> [KitchenTitleMilestone] {
        let unlocked = achievements.filter(\.isUnlocked)
        let unlockedByCategory = Dictionary(grouping: unlocked, by: \.category).mapValues(\.count)
        let totalsByCategory = Dictionary(grouping: achievements, by: \.category).mapValues(\.count)
        let total = unlocked.count

        let journey: [(KitchenTitle, Int)] = [
            (KitchenTitle(id: "prelude", name: "台所の旅支度", symbol: "fork.knife", tone: .copper), 0),
            (KitchenTitle(id: "beginner", name: "はじまりの料理人", symbol: "sparkles", tone: .copper), 1),
            (KitchenTitle(id: "explorer", name: "献立の探検家", symbol: "map.fill", tone: .basil), 5),
            (KitchenTitle(id: "home-cook", name: "暮らしの料理人", symbol: "frying.pan.fill", tone: .basil), 10),
            (KitchenTitle(id: "cultivator", name: "味を育てる人", symbol: "leaf.fill", tone: .berry), 15),
            (KitchenTitle(id: "curator", name: "食卓のキュレーター", symbol: "star.circle.fill", tone: .berry), 20),
            (KitchenTitle(id: "artisan", name: "百味の料理家", symbol: "medal.fill", tone: .gold), 25),
            (KitchenTitle(id: "maestro", name: "台所のマエストロ", symbol: "trophy.fill", tone: .gold), 30),
            (KitchenTitle(id: "golden-cook", name: "黄金の料理人", symbol: "crown.fill", tone: .gold), 35),
            (KitchenTitle(id: "legend", name: "台所の伝説", symbol: "crown.fill", tone: .gold), achievements.count)
        ]

        var milestones = journey.map { title, target in
            KitchenTitleMilestone(
                title: title,
                group: .journey,
                condition: target == 0 ? "料理の記録を始める" : "勲章を\(target)個解除する",
                current: total,
                target: target
            )
        }

        for category in KitchenAchievement.Category.allCases {
            let categoryUnlocked = unlockedByCategory[category, default: 0]
            let target = specialistTarget(for: category)
            milestones.append(
                KitchenTitleMilestone(
                    title: specialistTitle(for: category),
                    group: .specialist,
                    condition: "「\(category.title)」の勲章を\(target)個解除する",
                    current: categoryUnlocked,
                    target: target
                )
            )
        }

        for category in KitchenAchievement.Category.allCases {
            let categoryUnlocked = unlockedByCategory[category, default: 0]
            let categoryTotal = totalsByCategory[category, default: 0]
            milestones.append(
                KitchenTitleMilestone(
                    title: masteryTitle(for: category),
                    group: .mastery,
                    condition: "「\(category.title)」をすべて制覇する",
                    current: categoryUnlocked,
                    target: categoryTotal
                )
            )
        }

        return milestones
    }

    private static func specialistTarget(for category: KitchenAchievement.Category) -> Int {
        switch category {
        case .collection: 5
        case .cooking: 6
        case .discovery: 4
        case .journal: 4
        }
    }

    private static func specialistTitle(for category: KitchenAchievement.Category) -> KitchenTitle {
        switch category {
        case .collection:
            KitchenTitle(id: "collector", name: "レシピ蒐集家", symbol: "books.vertical.fill", tone: .basil)
        case .cooking:
            KitchenTitle(id: "daily-cook", name: "日々の料理人", symbol: "flame.fill", tone: .copper)
        case .discovery:
            KitchenTitle(id: "taste-explorer", name: "味覚の探究家", symbol: "safari.fill", tone: .berry)
        case .journal:
            KitchenTitle(id: "kitchen-writer", name: "台所の記録家", symbol: "pencil.and.scribble", tone: .basil)
        }
    }

    private static func masteryTitle(for category: KitchenAchievement.Category) -> KitchenTitle {
        switch category {
        case .collection:
            KitchenTitle(id: "archive-master", name: "料理書庫の館主", symbol: "building.columns.fill", tone: .gold)
        case .cooking:
            KitchenTitle(id: "flame-master", name: "炎のマエストロ", symbol: "flame.circle.fill", tone: .gold)
        case .discovery:
            KitchenTitle(id: "taste-navigator", name: "味覚の航海士", symbol: "safari.fill", tone: .gold)
        case .journal:
            KitchenTitle(id: "chronicle-master", name: "食卓の年代記作家", symbol: "text.book.closed.fill", tone: .gold)
        }
    }
}

struct AchievementsView: View {
    let recipes: [Recipe]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(KitchenTitlePreference.selectedTitleIDKey) private var selectedTitleID = ""
    @State private var hasAppeared = false

    private var achievements: [KitchenAchievement] {
        AchievementCenter.achievements(for: recipes)
    }

    private var unlockedCount: Int {
        achievements.filter(\.isUnlocked).count
    }

    private var completion: Double {
        guard !achievements.isEmpty else { return 0 }
        return Double(unlockedCount) / Double(achievements.count)
    }

    private var kitchenTitle: KitchenTitle {
        AchievementCenter.equippedTitle(
            in: achievements,
            selectedTitleID: selectedTitleID
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                cabinetHeader

                if let next = AchievementCenter.nextAchievement(in: achievements) {
                    NextAchievementCard(achievement: next)
                } else {
                    AllUnlockedCard()
                }

                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("トロフィーコレクション")
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                        Spacer()
                        Text("\(unlockedCount) / \(achievements.count)")
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.white.opacity(0.52))
                    }

                    ForEach(KitchenAchievement.Category.allCases) { category in
                        AchievementSeriesSection(
                            category: category,
                            achievements: achievements.filter { $0.category == category },
                            hasAppeared: hasAppeared,
                            reduceMotion: reduceMotion
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 36)
        }
        .background(CabinetBackground())
        .navigationTitle("キッチンの軌跡")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { hasAppeared = true }
    }

    private var cabinetHeader: some View {
        NavigationLink {
            KitchenTitlesView(achievements: achievements)
        } label: {
            HStack(spacing: 18) {
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.08), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: completion)
                        .stroke(
                            AngularGradient(
                                colors: kitchenTitle.tone.colors + [kitchenTitle.tone.colors[0]],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    Image(systemName: kitchenTitle.symbol)
                        .font(.system(size: 31, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(colors: kitchenTitle.tone.colors, startPoint: .top, endPoint: .bottom)
                        )
                        .shadow(color: kitchenTitle.tone.colors[0].opacity(0.45), radius: 10)
                }
                .frame(width: 96, height: 96)

                VStack(alignment: .leading, spacing: 6) {
                    Text("MY KITCHEN")
                        .font(.caption2.weight(.heavy))
                        .tracking(2.4)
                        .foregroundStyle(RecipePalette.ember)
                    Text(kitchenTitle.name)
                        .font(.system(size: 30, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                        .contentTransition(.numericText())
                    HStack(spacing: 6) {
                        Text("勲章 \(unlockedCount) / \(achievements.count)")
                        Spacer(minLength: 4)
                        Text("称号図鑑")
                        Image(systemName: "chevron.right")
                            .font(.caption2.bold())
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.62))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .background(
                LinearGradient(
                    colors: [.white.opacity(0.09), .white.opacity(0.035)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 26)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 26)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 26))
        }
        .buttonStyle(CardPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("称号の解禁条件を開きます")
    }
}

struct KitchenTitlesView: View {
    let achievements: [KitchenAchievement]

    @AppStorage(KitchenTitlePreference.selectedTitleIDKey) private var selectedTitleID = ""

    private var currentTitle: KitchenTitle {
        AchievementCenter.equippedTitle(
            in: achievements,
            selectedTitleID: selectedTitleID
        )
    }

    private var milestones: [KitchenTitleMilestone] {
        AchievementCenter.titleMilestones(in: achievements)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                currentTitleCard

                ForEach(KitchenTitleMilestone.Group.allCases) { group in
                    titleSection(for: group)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 38)
        }
        .background(CabinetBackground())
        .navigationTitle("称号図鑑")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear(perform: discardUnavailableSelection)
    }

    private var currentTitleCard: some View {
        HStack(spacing: 18) {
            TitleMedallion(title: currentTitle, isUnlocked: true, size: 82)

            VStack(alignment: .leading, spacing: 5) {
                Text("CURRENT TITLE")
                    .font(.caption2.weight(.heavy))
                    .tracking(2)
                    .foregroundStyle(currentTitle.tone.colors[0])
                Text(currentTitle.name)
                    .font(.system(size: 27, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if selectedTitleID.isEmpty {
                    Label("おすすめから自動選択中", systemImage: "wand.and.stars")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.56))
                } else {
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            selectedTitleID = ""
                        }
                    } label: {
                        Label("おすすめに戻す", systemImage: "arrow.counterclockwise")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(currentTitle.tone.colors[0])
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("進捗に応じた称号を自動で選びます")
                }
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .background {
            ZStack {
                LinearGradient(
                    colors: [currentTitle.tone.colors[1].opacity(0.34), .white.opacity(0.055)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(currentTitle.tone.colors[0].opacity(0.16))
                    .frame(width: 130)
                    .blur(radius: 30)
                    .offset(x: 135, y: -35)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .overlay {
            RoundedRectangle(cornerRadius: 26)
                .strokeBorder(currentTitle.tone.colors[0].opacity(0.24), lineWidth: 1)
        }
    }

    private func titleSection(for group: KitchenTitleMilestone.Group) -> some View {
        let groupMilestones = milestones.filter { $0.group == group }
        let unlockedCount = groupMilestones.filter(\.isUnlocked).count

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(group.title)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                    Text(group.subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.48))
                }

                Spacer()

                Text("\(unlockedCount) / \(groupMilestones.count)")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(.white.opacity(0.58))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.07), in: Capsule())
            }

            VStack(spacing: 10) {
                ForEach(groupMilestones) { milestone in
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            selectedTitleID = milestone.id
                        }
                    } label: {
                        KitchenTitleRow(
                            milestone: milestone,
                            isCurrent: milestone.id == currentTitle.id
                        )
                    }
                    .buttonStyle(CardPressStyle())
                    .disabled(!milestone.isUnlocked || milestone.id == currentTitle.id)
                    .accessibilityHint(
                        milestone.isUnlocked ? "この称号を装備します" : "解禁すると装備できます"
                    )
                }
            }
        }
    }

    private func discardUnavailableSelection() {
        guard !selectedTitleID.isEmpty else { return }
        let isAvailable = milestones.contains {
            $0.id == selectedTitleID && $0.isUnlocked
        }
        if !isAvailable {
            selectedTitleID = ""
        }
    }
}

private struct KitchenTitleRow: View {
    let milestone: KitchenTitleMilestone
    let isCurrent: Bool

    private var statusText: String {
        if isCurrent { return "CURRENT" }
        return milestone.isUnlocked ? "EQUIP" : "LOCKED"
    }

    var body: some View {
        HStack(spacing: 14) {
            TitleMedallion(
                title: milestone.title,
                isUnlocked: milestone.isUnlocked,
                size: 58
            )

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(milestone.title.name)
                        .font(.headline)
                        .foregroundStyle(milestone.isUnlocked ? .white : .white.opacity(0.52))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Spacer(minLength: 4)

                    Text(statusText)
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(
                            isCurrent ? milestone.title.tone.colors[0] : .white.opacity(milestone.isUnlocked ? 0.70 : 0.32)
                        )
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(
                            isCurrent ? milestone.title.tone.colors[0].opacity(0.14) : .white.opacity(0.055),
                            in: Capsule()
                        )
                }

                Text(milestone.condition)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(milestone.isUnlocked ? 0.60 : 0.42))

                HStack(spacing: 9) {
                    ProgressView(value: milestone.progress)
                        .tint(milestone.isUnlocked ? milestone.title.tone.colors[0] : .white.opacity(0.26))
                    Text(milestone.progressText)
                        .font(.caption2.monospacedDigit().weight(.bold))
                        .foregroundStyle(.white.opacity(milestone.isUnlocked ? 0.66 : 0.38))
                        .fixedSize()
                }
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [
                    .white.opacity(isCurrent ? 0.105 : milestone.isUnlocked ? 0.075 : 0.04),
                    .white.opacity(0.025)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 21)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 21)
                .strokeBorder(
                    isCurrent ? milestone.title.tone.colors[0].opacity(0.34) : .white.opacity(milestone.isUnlocked ? 0.10 : 0.055),
                    lineWidth: 1
                )
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(isCurrent ? "現在の称号" : milestone.isUnlocked ? "解除済み" : milestone.progressText)
    }
}

private struct TitleMedallion: View {
    let title: KitchenTitle
    let isUnlocked: Bool
    let size: CGFloat

    var body: some View {
        ZStack {
            if isUnlocked {
                Circle()
                    .fill(title.tone.colors[0].opacity(0.18))
                    .blur(radius: 8)
                    .scaleEffect(1.13)
            }

            Circle()
                .fill(
                    LinearGradient(
                        colors: isUnlocked ? title.tone.colors : [.gray.opacity(0.34), .black.opacity(0.52)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .strokeBorder(.white.opacity(isUnlocked ? 0.35 : 0.09), lineWidth: 1.5)
                .padding(4)
            Image(systemName: isUnlocked ? title.symbol : "lock.fill")
                .font(.system(size: size * 0.31, weight: .bold))
                .foregroundStyle(.white.opacity(isUnlocked ? 0.94 : 0.28))
        }
        .frame(width: size, height: size)
        .saturation(isUnlocked ? 1 : 0.1)
    }
}

struct AchievementSpotlight: View {
    let recipes: [Recipe]

    private var achievements: [KitchenAchievement] {
        AchievementCenter.achievements(for: recipes)
    }

    private var unlockedCount: Int {
        achievements.filter(\.isUnlocked).count
    }

    private var featured: KitchenAchievement? {
        AchievementCenter.nextAchievement(in: achievements) ?? achievements.last
    }

    var body: some View {
        NavigationLink {
            AchievementsView(recipes: recipes)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.14))
                    Circle()
                        .strokeBorder(.white.opacity(0.28), lineWidth: 1)
                    Image(systemName: featured?.isUnlocked == true ? "crown.fill" : "trophy.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(.yellow)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text(featured?.isUnlocked == true ? "すべての勲章を獲得" : "次のトロフィー")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.66))
                    Text(featured?.title ?? "料理の軌跡")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let featured, !featured.isUnlocked {
                        ProgressView(value: featured.progress)
                            .tint(.yellow)
                            .scaleEffect(y: 0.75)
                    }
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 5) {
                    Text("\(unlockedCount)/\(achievements.count)")
                        .font(.subheadline.monospacedDigit().bold())
                        .foregroundStyle(.white)
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.white.opacity(0.58))
                }
            }
            .padding(14)
            .background {
                ZStack {
                    LinearGradient(
                        colors: [Color(red: 0.20, green: 0.12, blue: 0.10), Color(red: 0.38, green: 0.16, blue: 0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Circle()
                        .fill(RecipePalette.ember.opacity(0.30))
                        .frame(width: 150)
                        .blur(radius: 35)
                        .offset(x: 130, y: -50)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 1)
            }
            .shadow(color: RecipePalette.tomato.opacity(0.18), radius: 12, y: 6)
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(CardPressStyle())
        .accessibilityHint("トロフィー棚を開きます")
    }
}

private struct NextAchievementCard: View {
    let achievement: KitchenAchievement

    var body: some View {
        HStack(spacing: 16) {
            AchievementMedallion(achievement: achievement, size: 72)

            VStack(alignment: .leading, spacing: 5) {
                Text("NEXT MILESTONE")
                    .font(.caption2.weight(.heavy))
                    .tracking(1.8)
                    .foregroundStyle(achievement.tone.colors[0])
                Text(achievement.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(achievement.detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.60))

                HStack(spacing: 10) {
                    ProgressView(value: achievement.progress)
                        .tint(achievement.tone.colors[0])
                    Text(achievement.progressText)
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(.white.opacity(0.78))
                }
            }
        }
        .padding(17)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
        }
    }
}

private struct AllUnlockedCard: View {
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "crown.fill")
                .font(.system(size: 34))
                .foregroundStyle(.yellow)
                .shadow(color: .orange.opacity(0.55), radius: 10)
            VStack(alignment: .leading, spacing: 4) {
                Text("THE KITCHEN IS YOURS")
                    .font(.caption2.weight(.heavy))
                    .tracking(1.6)
                    .foregroundStyle(.yellow)
                Text("すべての勲章を獲得しました")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 24))
    }
}

private struct AchievementSeriesSection: View {
    let category: KitchenAchievement.Category
    let achievements: [KitchenAchievement]
    let hasAppeared: Bool
    let reduceMotion: Bool

    private var unlockedCount: Int {
        achievements.filter(\.isUnlocked).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                Image(systemName: category.symbol)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(RecipePalette.ember)
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.08), in: Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(category.subtitle)
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.7)
                        .foregroundStyle(RecipePalette.ember.opacity(0.86))
                    Text(category.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                }

                Spacer()

                Text("\(unlockedCount) / \(achievements.count)")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(.white.opacity(0.48))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.06), in: Capsule())
            }

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                ForEach(Array(achievements.enumerated()), id: \.element.id) { index, achievement in
                    AchievementCard(achievement: achievement)
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared ? 0 : 14)
                        .animation(
                            reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.84)
                                .delay(Double(index) * 0.03),
                            value: hasAppeared
                        )
                }
            }
        }
    }
}

private struct AchievementCard: View {
    let achievement: KitchenAchievement

    var body: some View {
        VStack(spacing: 11) {
            AchievementMedallion(achievement: achievement, size: 78)

            VStack(spacing: 3) {
                Text(achievement.eyebrow)
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.3)
                    .foregroundStyle(achievement.isUnlocked ? achievement.tone.colors[0] : .white.opacity(0.32))
                Text(achievement.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(achievement.isUnlocked ? .white : .white.opacity(0.48))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text(achievement.detail)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.48))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(minHeight: 28)
            }

            HStack(spacing: 7) {
                ProgressView(value: achievement.progress)
                    .tint(achievement.isUnlocked ? achievement.tone.colors[0] : .white.opacity(0.30))
                Image(systemName: achievement.isUnlocked ? "checkmark.seal.fill" : "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(achievement.isUnlocked ? achievement.tone.colors[0] : .white.opacity(0.28))
            }

            Text(achievement.isUnlocked ? "UNLOCKED" : achievement.progressText)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(achievement.isUnlocked ? 0.72 : 0.38))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [.white.opacity(achievement.isUnlocked ? 0.10 : 0.045), .white.opacity(0.035)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(.white.opacity(achievement.isUnlocked ? 0.12 : 0.06), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(achievement.isUnlocked ? "解除済み" : achievement.progressText)
    }
}

private struct AchievementMedallion: View {
    let achievement: KitchenAchievement
    let size: CGFloat

    var body: some View {
        ZStack {
            if achievement.isUnlocked {
                Circle()
                    .fill(achievement.tone.colors[0].opacity(0.20))
                    .blur(radius: 9)
                    .scaleEffect(1.14)
            }

            Circle()
                .fill(
                    LinearGradient(
                        colors: achievement.isUnlocked ? achievement.tone.colors : [.gray.opacity(0.40), .black.opacity(0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .strokeBorder(.white.opacity(achievement.isUnlocked ? 0.44 : 0.10), lineWidth: 2)
                .padding(5)
            Circle()
                .strokeBorder(.black.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [2.2, 3]))
                .padding(10)
            Image(systemName: achievement.isUnlocked ? achievement.symbol : "lock.fill")
                .font(.system(size: size * 0.31, weight: .bold))
                .foregroundStyle(.white.opacity(achievement.isUnlocked ? 0.96 : 0.30))
                .shadow(color: .black.opacity(0.24), radius: 2, y: 1)
        }
        .frame(width: size, height: size)
        .saturation(achievement.isUnlocked ? 1 : 0.15)
    }
}

private struct CabinetBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.075, green: 0.065, blue: 0.06)
            LinearGradient(
                colors: [RecipePalette.tomato.opacity(0.22), .clear, RecipePalette.basil.opacity(0.16)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(RecipePalette.ember.opacity(0.12))
                .frame(width: 310)
                .blur(radius: 70)
                .offset(x: 150, y: -330)
        }
        .ignoresSafeArea()
    }
}
