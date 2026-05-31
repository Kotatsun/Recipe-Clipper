import XCTest
@testable import RecipeClipping

final class RecipeTextExtractorTests: XCTestCase {
    private let extractor = RecipeTextExtractor()
    private let importer = RecipeImporter()
    private let plainParser = PlainRecipeTextParser()

    private struct ImportFixtureExpectation {
        var sourceURL: String
        var fixtureFileName: String
        var importerType: String
        var expectedTitle: String
        var expectedIngredientsCount: Int
        var expectedInstructionsCount: Int
        var expectedFailureMode: String
    }

    private struct LiveImportSmokeExpectation {
        var sourceURL: String
        var importerType: String
        var minimumIngredientsCount: Int
        var minimumInstructionsCount: Int
        var expectedFailureMode: String
    }

    // URL / fixture correspondence table for the currently failing import targets.
    // The static Instagram and YouTube unavailable fixtures intentionally model the
    // "caption/description unavailable in HTML" case. Available caption/description
    // fixtures cover the successful importer-to-extractor path without network access.
    private static let failingURLFixtureExpectations: [ImportFixtureExpectation] = [
        ImportFixtureExpectation(
            sourceURL: "https://mr-cheesecake.com/blogs/journal/no28",
            fixtureFileName: "mr_cheesecake_italian_pudding.html",
            importerType: "web",
            expectedTitle: "イタリアンプリン",
            expectedIngredientsCount: 8,
            expectedInstructionsCount: 8,
            expectedFailureMode: "手順は(1)から(8)を抽出し、Point / MAIL MAGAZINE / TOPICSを混ぜない"
        ),
        ImportFixtureExpectation(
            sourceURL: "https://www.orangepage.net/food/series-food/akarikihon/181941",
            fixtureFileName: "orangepage_hamburg.html",
            importerType: "web",
            expectedTitle: "ハンバーグ",
            expectedIngredientsCount: 6,
            expectedInstructionsCount: 3,
            expectedFailureMode: "手順は（1）肉だねを作る / （2）成形する / （3）焼くを本文と結合する"
        ),
        ImportFixtureExpectation(
            sourceURL: "https://park.ajinomoto.co.jp/recipe/card/703281/",
            fixtureFileName: "ajinomoto_chicken_ratatouille.html",
            importerType: "web",
            expectedTitle: "チキンラタトゥイユ",
            expectedIngredientsCount: 15,
            expectedInstructionsCount: 4,
            expectedFailureMode: "AJINOMOTO PARKのJSON-LD recipeIngredient / recipeInstructionsを優先し、手順内のbrタグを混ぜない"
        ),
        ImportFixtureExpectation(
            sourceURL: "https://www.instagram.com/reel/DYhGkdGIN8b/",
            fixtureFileName: "instagram_dyh_caption_unavailable.html",
            importerType: "instagram",
            expectedTitle: "Instagram Reel",
            expectedIngredientsCount: 0,
            expectedInstructionsCount: 0,
            expectedFailureMode: "static fixture has no caption; real URL smoke must attempt meta/script/embed caption retrieval without inventing recipe text"
        ),
        ImportFixtureExpectation(
            sourceURL: "https://www.instagram.com/reel/DXrQLJkE4i2/",
            fixtureFileName: "instagram_dxr_caption_unavailable.html",
            importerType: "instagram",
            expectedTitle: "Instagram Reel",
            expectedIngredientsCount: 0,
            expectedInstructionsCount: 0,
            expectedFailureMode: "static fixture has no caption; real URL smoke must attempt meta/script/embed caption retrieval without inventing recipe text"
        ),
        ImportFixtureExpectation(
            sourceURL: "https://youtu.be/CdtVWTm-xU4?si=yganvmfean07Md9t",
            fixtureFileName: "youtube_cdt_description_unavailable.html",
            importerType: "youtube",
            expectedTitle: "YouTube video CdtVWTm-xU4",
            expectedIngredientsCount: 0,
            expectedInstructionsCount: 0,
            expectedFailureMode: "static fixture has no description; real URL smoke must extract videoId and attempt oEmbed/Data API description retrieval"
        )
    ]

    private static let instagramLiveSmokeExpectations: [LiveImportSmokeExpectation] = [
        LiveImportSmokeExpectation(
            sourceURL: "https://www.instagram.com/reel/DXrQLJkE4i2/",
            importerType: "instagram",
            minimumIngredientsCount: 2,
            minimumInstructionsCount: 1,
            expectedFailureMode: "実URLでは材料と手順が混在していても、caption取得後に材料・手順へ分離する"
        ),
        LiveImportSmokeExpectation(
            sourceURL: "https://www.instagram.com/reel/DYKMfMlRE3o/",
            importerType: "instagram",
            minimumIngredientsCount: 4,
            minimumInstructionsCount: 3,
            expectedFailureMode: "実URLではInstagram embed内の二重エスケープcaptionから材料を抽出する"
        ),
        LiveImportSmokeExpectation(
            sourceURL: "https://www.instagram.com/reel/DYhGkdGIN8b/",
            importerType: "instagram",
            minimumIngredientsCount: 4,
            minimumInstructionsCount: 3,
            expectedFailureMode: "実URLではInstagram embed内の二重エスケープcaptionから材料を抽出する"
        ),
        LiveImportSmokeExpectation(
            sourceURL: "https://www.instagram.com/reel/DYuCMkMxSZO/",
            importerType: "instagram",
            minimumIngredientsCount: 4,
            minimumInstructionsCount: 3,
            expectedFailureMode: "実URLではInstagram embed内の二重エスケープcaptionから材料を抽出する"
        )
    ]

    func testFailingURLFixtureCorrespondenceTable() throws {
        for expectation in Self.failingURLFixtureExpectations {
            let name = String(expectation.fixtureFileName.split(separator: ".").first ?? "")
            let ext = String(expectation.fixtureFileName.split(separator: ".").last ?? "html")
            let fixture = try fixtureText(name, ext: ext)
            try assertFixtureSourceURL(in: fixture, matches: expectation.sourceURL)
            XCTAssertFalse(expectation.importerType.isEmpty)
            XCTAssertFalse(expectation.expectedTitle.isEmpty)
            XCTAssertGreaterThanOrEqual(expectation.expectedIngredientsCount, 0)
            XCTAssertGreaterThanOrEqual(expectation.expectedInstructionsCount, 0)
            XCTAssertFalse(expectation.expectedFailureMode.isEmpty)
        }
    }

    func testJSONLDRecipeHowToStep() throws {
        let result = try extractThroughImporter("jsonld_howto_step", ext: "html")

        XCTAssertEqual(result.title, "JSON-LDショートケーキ")
        XCTAssertTrue(result.ingredients.contains { $0.contains("いちご") && $0.contains("8個") }, debug(result))
        XCTAssertTrue(result.ingredients.contains { $0.contains("生クリーム") && $0.contains("200ml") }, debug(result))
        XCTAssertEqual(result.instructions.count, 2)
        XCTAssertTrue(result.instructions.contains { $0.contains("泡立てる") })
        XCTAssertEqual(result.ingredientSource, "jsonld")
        XCTAssertEqual(result.instructionSource, "jsonld")
    }

    func testJSONLDRecipeHowToSection() throws {
        let result = try extractThroughImporter("jsonld_howto_section", ext: "html")

        XCTAssertEqual(result.title, "JSON-LDカレー")
        XCTAssertTrue(result.ingredients.contains { $0.contains("玉ねぎ") && $0.contains("1個") }, debug(result))
        XCTAssertEqual(result.instructions.count, 3)
        XCTAssertTrue(result.instructions.contains { $0.contains("下準備") && $0.contains("薄切り") })
        XCTAssertTrue(result.instructions.contains { $0.contains("加熱") && $0.contains("煮る") })
    }

    func testImporterExtractorDraftIntegration() throws {
        let draft = try makeDraftFromFixture("jsonld_howto_step", ext: "html")

        XCTAssertFalse(draft.title.isEmpty)
        XCTAssertFalse(draft.ingredientLines.joined(separator: "\n").isEmpty)
        XCTAssertFalse(draft.instructionLines.joined(separator: "\n").isEmpty)
        XCTAssertFalse(draft.rawImportedText.isEmpty)
        XCTAssertEqual(draft.importedTextSource, "jsonLD")
        XCTAssertEqual(draft.ingredientLines.joined(separator: "\n"), "いちご 8個\n生クリーム 200ml\n砂糖 20g")
    }

    func testImporterExtractorDraftIntegrationForUnextractableContent() throws {
        let draft = try makeDraftFromFixture("no_recipe_text", ext: "html")

        XCTAssertTrue(draft.ingredientLines.joined(separator: "\n").isEmpty)
        XCTAssertTrue(draft.instructionLines.joined(separator: "\n").isEmpty)
        XCTAssertFalse(draft.rawImportedText.isEmpty)
        XCTAssertFalse(draft.extractionWarnings.isEmpty)
    }

    func testImporterExtractorDraftIntegrationForMrCheesecake() throws {
        let draft = try makeDraftFromFixture("mr_cheesecake_italian_pudding", ext: "html")
        let ingredientsText = draft.ingredientLines.joined(separator: "\n")
        let instructionsText = draft.instructionLines.joined(separator: "\n")

        XCTAssertEqual(draft.sourceURL.absoluteString, "https://mr-cheesecake.com/blogs/journal/no28")
        XCTAssertTrue(draft.rawImportedText.contains("MAIL MAGAZINE"), debug(draft))
        XCTAssertTrue(draft.rawImportedText.contains("TOPICS"), debug(draft))
        let diagnostics = try XCTUnwrap(draft.importDiagnostics)
        XCTAssertEqual(diagnostics.extractionSource, "articleCandidate")
        XCTAssertLessThan(diagnostics.extractorInputTextLength, diagnostics.rawImportedTextLength)
        XCTAssertFalse(diagnostics.extractorInputTextPreview.contains("MAIL MAGAZINE"))
        XCTAssertFalse(diagnostics.extractorInputTextPreview.contains("TOPICS"))
        XCTAssertTrue(draft.rawImportedText.contains("(1)グラニュー糖"), debug(draft))
        XCTAssertTrue(ingredientsText.contains("クリームチーズ 100g"), debug(draft))
        XCTAssertTrue(ingredientsText.contains("全卵 4個"), debug(draft))
        XCTAssertTrue(ingredientsText.contains("牛乳 200g"), debug(draft))
        XCTAssertTrue(instructionsText.contains("グラニュー糖") && instructionsText.contains("カラメル"), debug(draft))
        XCTAssertTrue(draft.instructionLines.count >= 6, debug(draft))
        XCTAssertFalse(instructionsText.contains("Point"))
        XCTAssertFalse(instructionsText.contains("▶︎"))
        XCTAssertFalse(instructionsText.contains("MAIL MAGAZINE"))
        XCTAssertFalse(instructionsText.contains("TOPICS"))
    }

    func testMrCheesecakeVisibleTextWithImageNoiseAndInlineStepMarkers() throws {
        let text = """
        イタリアンプリン
        材料
        グラニュー糖 40g
        クリームチーズ 100g
        生クリーム 100g
        作り方 Image https://example.com/step1.jpg alt="型"
        (1)型に流し込み、表面を整える。 Image https://example.com/step2.jpg (2)クリームチーズにグラニュー糖と練乳を入れて混ぜる。 Image https://example.com/step3.jpg (3)(2)に卵を少しずつ加えて混ぜる。
        Point
        ▶︎焦がし気味がほろ苦いキャラメルになるのでおすすめ。
        MAIL MAGAZINE
        """

        let result = extractor.extract(from: text, metadataTitle: "イタリアンプリン")
        let instructionsText = result.instructions.joined(separator: "\n")

        XCTAssertGreaterThanOrEqual(result.instructions.count, 3, debug(result))
        XCTAssertTrue(instructionsText.contains("クリームチーズにグラニュー糖と練乳を入れて混ぜる"), debug(result))
        XCTAssertTrue(instructionsText.contains("卵を少しずつ加えて混ぜる"), debug(result))
        XCTAssertFalse(instructionsText.contains("Image"))
        XCTAssertFalse(instructionsText.contains("▶︎"))
    }

    func testImporterExtractorDraftIntegrationForCookpadNumberedBody() throws {
        let draft = try makeDraftFromFixture("cookpad_panna_cotta", ext: "html")
        let ingredientsText = draft.ingredientLines.joined(separator: "\n")
        let instructionsText = draft.instructionLines.joined(separator: "\n")

        XCTAssertEqual(draft.importDiagnostics?.extractionSource, "cookpadDOM")
        XCTAssertLessThan(draft.importDiagnostics?.extractorInputTextLength ?? 0, draft.rawImportedText.count)
        XCTAssertTrue(draft.rawImportedText.contains("1. 粉ゼラチン"), debug(draft))
        XCTAssertTrue(ingredientsText.contains("粉ゼラチン 4g"), debug(draft))
        XCTAssertTrue(instructionsText.contains("粉ゼラチン") && instructionsText.contains("ふやかす"), debug(draft))
        XCTAssertTrue(instructionsText.contains("冷やし固める"), debug(draft))
        XCTAssertFalse(draft.instructionLines.contains("1"))
        XCTAssertFalse(draft.instructionLines.contains("2"))
        XCTAssertFalse(instructionsText.contains("レシピを保存"))
    }

    func testImporterExtractorDraftIntegrationForMiaModenaImageCenteredInstructions() throws {
        let draft = try makeDraftFromFixture("miamodena_fennel_pasta_amp", ext: "html")
        let ingredientsText = draft.ingredientLines.joined(separator: "\n")

        XCTAssertTrue(draft.rawImportedText.contains("フェンネルのパスタ"), debug(draft))
        XCTAssertTrue(ingredientsText.contains("パスタ 400g"), debug(draft))
        XCTAssertTrue(ingredientsText.contains("パンチェッタ 80g"), debug(draft))
        XCTAssertTrue(draft.instructionLines.isEmpty || draft.instructionLines.count <= 1, debug(draft))
        XCTAssertTrue(draft.extractionWarnings.contains { $0.contains("見出し") || $0.contains("画像内") || $0.contains("作り方") }, debug(draft))
    }

    func testImporterExtractorDraftIntegrationForOrangePageRealURLFixture() throws {
        let draft = try makeDraftFromFixture("orangepage_hamburg", ext: "html")
        let instructionsText = draft.instructionLines.joined(separator: "\n")

        XCTAssertEqual(draft.sourceURL.absoluteString, "https://www.orangepage.net/food/series-food/akarikihon/181941")
        let diagnostics = try XCTUnwrap(draft.importDiagnostics)
        XCTAssertEqual(diagnostics.extractionSource, "articleCandidate")
        XCTAssertFalse(diagnostics.extractorInputTextPreview.contains("バックナンバー"))
        XCTAssertFalse(diagnostics.extractorInputTextPreview.contains("著者"))
        XCTAssertGreaterThanOrEqual(draft.instructionLines.count, 3, debug(draft))
        XCTAssertTrue(instructionsText.contains("肉だねを作る"), debug(draft))
        XCTAssertTrue(instructionsText.contains("成形する"), debug(draft))
        XCTAssertTrue(instructionsText.contains("焼く"), debug(draft))
        XCTAssertFalse(instructionsText.contains("バックナンバー"))
        XCTAssertFalse(instructionsText.contains("著者"))
    }

    func testImporterExtractorDraftIntegrationForAjinomotoJSONLD() throws {
        let draft = try makeDraftFromFixture("ajinomoto_chicken_ratatouille", ext: "html")
        let ingredientsText = draft.ingredientLines.joined(separator: "\n")
        let instructionsText = draft.instructionLines.joined(separator: "\n")

        XCTAssertEqual(draft.sourceURL.absoluteString, "https://park.ajinomoto.co.jp/recipe/card/703281")
        XCTAssertEqual(draft.importDiagnostics?.extractionSource, "jsonLD")
        XCTAssertEqual(draft.title, "チキンラタトゥイユ")
        XCTAssertEqual(draft.ingredientLines.count, 15, debug(draft))
        XCTAssertTrue(ingredientsText.contains("鶏むね肉 1枚（250g）"), debug(draft))
        XCTAssertTrue(ingredientsText.contains("B「味の素KKコンソメ」固形タイプ 1個"), debug(draft))
        XCTAssertEqual(draft.instructionLines.count, 4, debug(draft))
        XCTAssertTrue(instructionsText.contains("ホールトマト、Ｂを加えて混ぜ"), debug(draft))
        XCTAssertFalse(instructionsText.contains("<br"), debug(draft))
    }

    func testMiaModenaFennelPastaAMP() throws {
        let result = try extract("miamodena_fennel_pasta_amp", ext: "html")

        XCTAssertTrue(result.title?.contains("フェンネルのパスタ") == true)
        XCTAssertTrue(result.ingredients.contains { $0.contains("パスタ") && $0.contains("400g") })
        XCTAssertTrue(result.ingredients.contains { $0.contains("パンチェッタ") && $0.contains("80g") }, debug(result))
        XCTAssertTrue(result.ingredients.contains { $0.contains("フェンネル") }, debug(result))
        XCTAssertTrue(result.ingredients.contains { $0.contains("スープストック") && $0.contains("200ml") })
        XCTAssertTrue(result.ingredients.contains { $0.contains("バルサミコ酢") })
        XCTAssertTrue(result.instructions.isEmpty || result.instructions.count <= 1)
        XCTAssertTrue(result.warnings.contains { $0.contains("見出し") || $0.contains("画像内") || $0.contains("作り方") })
    }

    func testKyoritsuGlassTiramisu() throws {
        let result = try extract("kyoritsu_glass_tiramisu", ext: "html")

        XCTAssertEqual(result.title, "グラスティラミス")
        XCTAssertTrue(result.ingredients.contains { $0.contains("マスカルポーネチーズ") && $0.contains("125g") })
        XCTAssertTrue(result.ingredients.contains { $0.contains("生クリーム") && $0.contains("100ml") })
        XCTAssertTrue(result.ingredients.contains { $0.contains("グラニュー糖") && $0.contains("30g") })
        XCTAssertTrue(result.ingredients.contains { $0.contains("エスプレッソ") || $0.contains("濃いめのコーヒー") })
        XCTAssertTrue(result.ingredients.contains { $0.contains("純ココア") && $0.contains("適量") })
        XCTAssertTrue(result.instructions.count >= 3)
        XCTAssertTrue(result.instructions.contains { $0.contains("マスカルポーネチーズ") })
        XCTAssertTrue(result.instructions.contains { $0.contains("生クリーム") })
        XCTAssertTrue(result.instructions.contains { $0.contains("スポンジケーキ") || $0.contains("カステラ") })
        XCTAssertFalse(result.instructions.contains { $0.contains("SNSでシェア") })
        XCTAssertFalse(result.instructions.contains { $0.contains("レシピ一覧") })
    }

    func testMrCheesecakeItalianPudding() throws {
        let result = try extract("mr_cheesecake_italian_pudding", ext: "html")

        XCTAssertTrue(result.title?.contains("イタリアンプリン") == true)
        XCTAssertTrue(result.ingredients.contains { $0.contains("グラニュー糖") && $0.contains("40g") })
        XCTAssertTrue(result.ingredients.contains { $0.contains("水") && $0.contains("15g") })
        XCTAssertTrue(result.ingredients.contains { $0.contains("お湯") && $0.contains("15g") })
        XCTAssertTrue(result.ingredients.contains { $0.contains("クリームチーズ") && $0.contains("100g") })
        XCTAssertTrue(result.ingredients.contains { $0.contains("全卵") && $0.contains("4個") })
        XCTAssertTrue(result.ingredients.contains { $0.contains("生クリーム") && $0.contains("100g") })
        XCTAssertTrue(result.ingredients.contains { $0.contains("牛乳") && $0.contains("200g") })
        XCTAssertTrue(result.ingredients.contains { $0.contains("練乳") && $0.contains("60g") })
        XCTAssertTrue(result.instructions.count >= 8)
        XCTAssertTrue(result.instructions[0].contains("グラニュー糖") || result.instructions[0].contains("水"))
        XCTAssertTrue(result.instructions.contains { $0.contains("クリームチーズ") })
        XCTAssertTrue(result.instructions.contains { $0.contains("160度") || $0.contains("湯煎焼き") })
        XCTAssertTrue(result.instructions.contains { $0.contains("冷蔵庫") || $0.contains("冷やす") })
        XCTAssertFalse(result.ingredients.contains { $0.contains("このプリンはあくまでも") })
        XCTAssertFalse(result.instructions.contains { $0 == "Point" })
        XCTAssertFalse(result.instructions.contains { $0.contains("MAIL MAGAZINE") || $0.contains("TOPICS") || $0.contains("お問い合わせ") })
    }

    func testFoodieBeefStewPrefersMainRecipe() throws {
        let result = try extract("foodie_beef_stew", ext: "html")

        XCTAssertTrue(result.title?.contains("ビーフシチュー") == true)
        XCTAssertTrue(result.ingredients.contains { $0.contains("牛肉") && $0.contains("1kg") })
        XCTAssertTrue(result.ingredients.contains { $0.contains("玉ねぎ") })
        XCTAssertTrue(result.ingredients.contains { $0.contains("にんじん") })
        XCTAssertTrue(result.ingredients.contains { $0.contains("赤ワイン") && $0.contains("200ml") })
        XCTAssertTrue(result.ingredients.contains { $0.contains("デミグラスソース") })
        XCTAssertTrue(result.instructions.count >= 7)
        XCTAssertFalse(result.title?.contains("キャロットグラッセ") == true)
        XCTAssertFalse(result.ingredients.contains { $0.contains("無塩バター") && $0.contains("大さじ1") })
    }

    func testOrangePageHamburg() throws {
        let result = try extract("orangepage_hamburg", ext: "html")

        XCTAssertTrue(result.title?.contains("ハンバーグ") == true)
        XCTAssertTrue(result.ingredients.contains { $0.contains("合いびき肉") && $0.contains("220g") })
        XCTAssertTrue(result.ingredients.contains { $0.contains("ベーコン") })
        XCTAssertTrue(result.ingredients.contains { $0.contains("牛乳") })
        XCTAssertTrue(result.ingredients.contains { $0.contains("片栗粉") })
        XCTAssertTrue(result.ingredients.contains { $0.contains("ミニトマト") })
        XCTAssertTrue(result.ingredients.contains { $0.contains("料理酒") })
        XCTAssertEqual(result.instructions.count, 3, debug(result))
        XCTAssertTrue(result.instructions[0].contains("肉だねを作る"), debug(result))
        XCTAssertTrue(result.instructions[0].contains("ベーコンはキッチンばさみ"), debug(result))
        XCTAssertTrue(result.instructions[1].contains("成形する"), debug(result))
        XCTAssertTrue(result.instructions[1].contains("ラップを広げて"), debug(result))
        XCTAssertTrue(result.instructions[2].contains("焼く"), debug(result))
        XCTAssertTrue(result.instructions[2].contains("蒸し焼き"), debug(result))
        XCTAssertFalse(result.instructions.contains { $0.contains("バックナンバー") })
        XCTAssertFalse(result.instructions.contains { $0.contains("著者") || $0.contains("著者紹介") || $0.contains("料理家") })
        XCTAssertFalse(result.instructions.contains { $0.lowercased().contains("sns") || $0.lowercased().contains("instagram") })
    }

    func testCookpadPannaCotta() throws {
        let result = try extract("cookpad_panna_cotta", ext: "html")

        XCTAssertEqual(result.title, "ふんわりリッチ♡バニラのパンナコッタ")
        XCTAssertTrue(result.ingredients.contains { $0.contains("生クリーム") && $0.contains("150g") })
        XCTAssertTrue(result.ingredients.contains { $0.contains("牛乳") && $0.contains("100g") })
        XCTAssertTrue(result.ingredients.contains { $0.contains("グラニュー糖") && $0.contains("20g") })
        XCTAssertTrue(result.ingredients.contains { $0.contains("粉ゼラチン") && $0.contains("4g") })
        XCTAssertTrue(result.ingredients.contains { $0.contains("冷水") && $0.contains("16g") }, debug(result))
        XCTAssertTrue(result.instructions.count >= 8, debug(result))
        XCTAssertTrue(result.instructions.contains { $0.contains("ゼラチン") && $0.contains("ふやかす") })
        XCTAssertTrue(result.instructions.contains { $0.contains("生クリーム") })
        XCTAssertTrue(result.instructions.contains { $0.contains("冷やし固める") })
        XCTAssertTrue(result.instructions.contains { $0.contains("カラメルソース") })
        XCTAssertFalse(result.instructions.contains("1"))
        XCTAssertFalse(result.instructions.contains("2"))
        XCTAssertFalse(result.ingredients.contains { $0.contains("アプリでひらく") })
        XCTAssertFalse(result.instructions.contains { $0.contains("レシピを保存") })
        XCTAssertFalse(result.instructions.contains { $0.contains("フォロー") })
    }

    func testChiccaFoodBotVerification() throws {
        let result = try extract("chiccafood_bot_verification", ext: "html")

        XCTAssertTrue(result.ingredients.isEmpty)
        XCTAssertTrue(result.instructions.isEmpty)
        XCTAssertTrue(result.confidence < 0.3)
        XCTAssertTrue(result.warnings.contains { $0.contains("verification") || $0.contains("bot") || $0.contains("レシピ本文") })
    }

    func testInstagramCaptionBasic() throws {
        let result = try extract("instagram_caption_basic", ext: "txt")

        XCTAssertEqual(result.title, "絶品トマトチキン")
        XCTAssertTrue(result.ingredients.contains { $0.contains("鶏もも肉") && $0.contains("300g") })
        XCTAssertTrue(result.ingredients.contains { $0.contains("トマト缶") })
        XCTAssertTrue(result.ingredients.contains { $0.contains("オリーブオイル") }, debug(result))
        XCTAssertEqual(result.instructions.count, 4)
        XCTAssertTrue(result.instructions[0].contains("鶏肉"))
        XCTAssertTrue(result.instructions[2].contains("トマト缶"))
        XCTAssertFalse(result.instructions.contains { $0.contains("保存して") })
        XCTAssertFalse(result.summary?.contains("#簡単レシピ") == true)
    }

    func testPlainParserInstagramCaptionSectionsAndCircledSteps() throws {
        let text = try fixtureText("plain_instagram_caption_sections", ext: "txt")
        let result = plainParser.parse(text, mode: .caption)

        XCTAssertEqual(result.title, "ふわふわ豆腐つくね")
        XCTAssertTrue(result.ingredients.contains { $0.contains("鶏ひき肉") && $0.contains("200g") }, debug(result))
        XCTAssertTrue(result.ingredients.contains { $0.contains("片栗粉") && $0.contains("大さじ2") }, debug(result))
        XCTAssertEqual(result.instructions.count, 4, debug(result))
        XCTAssertTrue(result.instructions[0].contains("豆腐"))
        XCTAssertFalse(result.instructions.contains { $0.contains("保存して") })
        XCTAssertFalse(result.ingredients.contains { $0.contains("#") })
    }

    func testPlainParserInstagramCaptionKeycapStepsAndSNSNoise() throws {
        let text = try fixtureText("plain_instagram_caption_keycap", ext: "txt")
        let result = plainParser.parse(text, mode: .caption)

        XCTAssertEqual(result.title, "ワンパン和風パスタ")
        XCTAssertTrue(result.ingredients.contains { $0.contains("パスタ") && $0.contains("100g") }, debug(result))
        XCTAssertTrue(result.ingredients.contains { $0.contains("しめじ") && $0.contains("1/2パック") }, debug(result))
        XCTAssertEqual(result.instructions.count, 3, debug(result))
        XCTAssertTrue(result.instructions.contains { $0.contains("めんつゆ") && $0.contains("からめる") })
        XCTAssertFalse(result.instructions.contains { $0.contains("詳しくは動画") })
        XCTAssertFalse(result.instructions.contains { $0.contains("http") })
    }

    func testPlainParserInstagramCaptionMixedRealisticHeadingsKeepsIngredientsOutOfSteps() throws {
        let text = try fixtureText("plain_instagram_caption_mixed_realistic", ext: "txt")
        let result = plainParser.parse(text, mode: .caption)

        XCTAssertEqual(result.title, "焼くだけ鮭のねぎ味噌")
        XCTAssertTrue(result.ingredients.contains { $0.contains("鮭") && $0.contains("2切れ") }, debug(result))
        XCTAssertTrue(result.ingredients.contains { $0.contains("みそ") && $0.contains("大1") }, debug(result))
        XCTAssertTrue(result.ingredients.contains { $0.contains("砂糖") && $0.contains("小1") }, debug(result))
        XCTAssertEqual(result.instructions.count, 3, debug(result))
        XCTAssertTrue(result.instructions.contains { $0.contains("トースター") && $0.contains("焼く") })
        XCTAssertFalse(result.instructions.contains { $0.contains("みそ 大1") }, debug(result))
    }

    func testPlainParserCombinedIngredientInstructionHeadingKeepsQuantityStepsOutOfIngredients() throws {
        let text = """
        鶏のレモン焼き

        【材料・作り方】
        ・鶏もも肉 300g
        ・塩 小さじ1/2
        ・レモン 1/2個
        ① 鶏肉に塩小さじ1/2を揉み込み、10分置く
        ② フライパンで焼いて、レモンをしぼる
        """
        let result = plainParser.parse(text, mode: .caption)

        XCTAssertTrue(result.ingredients.contains { $0.contains("鶏もも肉") && $0.contains("300g") }, debug(result))
        XCTAssertTrue(result.ingredients.contains { $0.contains("塩") && $0.contains("小さじ1/2") }, debug(result))
        XCTAssertFalse(result.ingredients.contains { $0.contains("揉み込み") || $0.contains("フライパン") }, debug(result))
        XCTAssertEqual(result.instructions.count, 2, debug(result))
        XCTAssertTrue(result.instructions.contains { $0.contains("塩小さじ1/2") && $0.contains("揉み込み") }, debug(result))
    }

    func testInstagramEscapedServerJSCaptionFeedsImporterExtractorDraftIntegration() throws {
        let caption = """
        ほうれん草とベーコンの濃厚クリームパスタ

        ■材料
        ・パスタ…100g
        ・水…300ml
        ・ほうれん草…1/2束
        ・ベーコン…50g
        ・牛乳…100ml
        ・コンソメ…小さじ1

        ■作り方
        ① ほうれん草はざく切りにして、オリーブオイル大さじ1と一緒にペースト状にする。
        ② フライパンにベーコンを入れてこんがり焼き、玉ねぎとにんにくを加えて炒める。
        ③ 水を加えて沸騰したら、パスタをそのまま入れる。
        ④ 牛乳・コンソメを加えて軽く煮詰める。
        """
        let embeddedCaption = try Self.jsonStringFragment(caption)
            .replacingOccurrences(of: "\\", with: "\\\\")
        let html = """
        <!-- Source URL: https://www.instagram.com/reel/escaped-serverjs/ -->
        <html>
          <head><title>Instagram</title></head>
          <body>
            <script>
            requireLazy(["ServerJS"],function(ServerJS){ServerJS.handle("{\\"edge_media_to_caption\\":{\\"edges\\":[{\\"node\\":{\\"text\\":\\"\(embeddedCaption)\\"}}]}}");});
            </script>
          </body>
        </html>
        """
        let inputURL = URL(string: "https://www.instagram.com/reel/escaped-serverjs/")!
        let initialFetched = importer.parseFetchedContent(html: html, inputURL: inputURL, importerType: "instagram")
        let extractedCaption = try XCTUnwrap(RecipeImporter.extractInstagramCaption(html: html, metadata: initialFetched.metadata))
        let draft = try makeDraft(
            html: html,
            inputURL: inputURL,
            importerType: "instagram",
            rawImportedTextOverride: extractedCaption,
            textSource: "instagramCaption"
        )

        XCTAssertEqual(draft.importedTextSource, "instagramCaption")
        XCTAssertTrue(draft.ingredientLines.contains { $0.contains("パスタ") && $0.contains("100g") }, debug(draft))
        XCTAssertTrue(draft.ingredientLines.contains { $0.contains("牛乳") && $0.contains("100ml") }, debug(draft))
        XCTAssertFalse(draft.ingredientLines.contains { $0.contains("水を加えて") }, debug(draft))
        XCTAssertTrue(draft.instructionLines.contains { $0.contains("水を加えて") && $0.contains("パスタ") }, debug(draft))
    }

    func testInstagramMetaDescriptionStripsEngagementPrefixBeforeParsingCaption() throws {
        let caption = """
        @kei______817 ◀︎他の10分レシピはこちら
        【鰹と豆苗のレモンドレッシング】

        〈レシピ/2人分〉
        鰹…1柵
        豆苗…1パック
        ☆醤油…大さじ1
        ☆オリーブオイル…大さじ1
        ☆粒マスタード…小さじ1
        ☆レモン汁…大さじ1
        レモン…1かけ
        ピンクペッパー…適量

        ①.豆苗は食べやすい長さにカットする。
        ②.小皿に☆を入れて混ぜ、ドレッシングを作る。
        ③.ボウルに豆苗と鰹を入れて②を回しかけてよく混ぜる。
        ④.皿に盛り付けてレモンとピンクペッパーをトッピングして完成。
        """
        let html = """
        <html>
          <head>
            <meta name="description" content="659 likes, 12 comments - kei______817 on May 30, 2026: &quot;\(caption)&quot;. ">
          </head>
        </html>
        """
        let inputURL = URL(string: "https://www.instagram.com/reel/DY9kRqnphct/")!
        let initialFetched = importer.parseFetchedContent(html: html, inputURL: inputURL, importerType: "instagram")
        let extractedCaption = try XCTUnwrap(RecipeImporter.extractInstagramCaption(html: html, metadata: initialFetched.metadata))
        let draft = try makeDraft(
            html: html,
            inputURL: inputURL,
            importerType: "instagram",
            rawImportedTextOverride: extractedCaption,
            textSource: "instagramCaption"
        )

        XCTAssertFalse(draft.rawImportedText.contains("659 likes"), debug(draft))
        XCTAssertFalse(draft.ingredientLines.contains { $0.contains("likes") || $0.contains("comments") }, debug(draft))
        XCTAssertTrue(draft.ingredientLines.contains { $0.contains("鰹") && $0.contains("1柵") }, debug(draft))
        XCTAssertTrue(draft.ingredientLines.contains { $0.contains("ピンクペッパー") && $0.contains("適量") }, debug(draft))
        XCTAssertEqual(draft.instructionLines.count, 4, debug(draft))
        XCTAssertTrue(draft.instructionLines.contains { $0.contains("トッピング") && $0.contains("完成") }, debug(draft))
    }

    func testPlainParserKeepsFinalMultilineInstagramStep() throws {
        let text = """
        ダイエット中なのに
        【えびクリームリゾット】

        🛒材料
        ＜A＞
        ・ごはん 130g
        ・えのき 80g (1/2パック)
        ・玉ねぎ 40g
        ・ツナ 1パック（60g）
        ・ほうれん草 好きな量（今回は冷凍を使用）
        ・冷凍むきえび 4個
        ・コンソメ 小さじ2
        ・にんにくチューブ 2cm
        ・豆乳 100ml

        ・とろけるチーズ 好きな量
        ・乾燥パセリ
        ・粗挽きコショウ
        ・えごま油、オリーブオイルなど 適量

        👩‍🍳作り方
        ①耐熱容器に＜A＞を入れる
        ②ふんわりラップをして
        500Wで4分レンチン
        ③よく混ぜてから、チーズを入れて
        さらに3分ほどレンチン
        ④お好みでオイルと
        乾燥パセリ・コショウをかける

        📌 保存して
        ガッツリ食べたい日に作ってね
        """
        let result = plainParser.parse(text, mode: .caption)
        let instructionsText = result.instructions.joined(separator: "\n")

        XCTAssertEqual(result.instructions.count, 4, debug(result))
        XCTAssertTrue(instructionsText.contains("乾燥パセリ・コショウをかける"), debug(result))
        XCTAssertFalse(instructionsText.contains("保存して"), debug(result))
    }

    func testPlainParserInstagramCaptionKeepsNumberedIngredientsInIngredientSection() throws {
        let text = """
        番号つき材料のテスト

        材料
        ① 鶏もも肉 300g
        ② 玉ねぎ 1/2個
        1. しめじ 1/2パック
        A
        A しょうゆ 大さじ1
        A みりん 大さじ1
        A 砂糖 小1

        作り方
        ① 鶏もも肉を焼く
        ② 玉ねぎとしめじを加えて炒める
        ③ Aを加えてからめる
        """
        let result = plainParser.parse(text, mode: .caption)

        XCTAssertEqual(result.ingredients.count, 6, debug(result))
        XCTAssertTrue(result.ingredients.contains("① 鶏もも肉 300g"), debug(result))
        XCTAssertTrue(result.ingredients.contains("② 玉ねぎ 1/2個"), debug(result))
        XCTAssertTrue(result.ingredients.contains("1. しめじ 1/2パック"), debug(result))
        XCTAssertTrue(result.ingredients.contains("A しょうゆ 大さじ1"), debug(result))
        XCTAssertFalse(result.ingredients.contains("A"), debug(result))
        XCTAssertEqual(result.instructions.count, 3, debug(result))
        XCTAssertTrue(result.instructions.first?.hasPrefix("① ") == true, debug(result))
        XCTAssertFalse(result.instructions.contains { $0.contains("鶏もも肉 300g") }, debug(result))
    }

    func testPlainParserYouTubeDescriptionBulletSections() throws {
        let text = try fixtureText("plain_youtube_description_bullets", ext: "txt")
        let result = plainParser.parse(text, mode: .description)

        XCTAssertEqual(result.title, "焼きなすのみそ汁")
        XCTAssertTrue(result.ingredients.contains { $0.contains("なす") && $0.contains("2本") }, debug(result))
        XCTAssertTrue(result.ingredients.contains { $0.contains("だし汁") && $0.contains("400ml") }, debug(result))
        XCTAssertEqual(result.instructions.count, 4, debug(result))
        XCTAssertTrue(result.instructions.contains { $0.contains("みそ") && $0.contains("溶かす") })
        XCTAssertFalse(result.instructions.contains { $0.contains("チャンネル登録") })
    }

    func testPlainParserManualCopyPasteWithStandaloneNumbers() throws {
        let text = try fixtureText("plain_manual_copy_paste", ext: "txt")
        let result = plainParser.parse(text, mode: .plainText)

        XCTAssertEqual(result.title, "かぼちゃサラダ")
        XCTAssertTrue(result.ingredients.contains { $0.contains("かぼちゃ") && $0.contains("300g") }, debug(result))
        XCTAssertTrue(result.ingredients.contains { $0.contains("塩") && $0.contains("少々") }, debug(result))
        XCTAssertEqual(result.instructions.count, 3, debug(result))
        XCTAssertTrue(result.instructions[0].contains("かぼちゃを一口大"))
        XCTAssertFalse(result.instructions.contains("1)"))
    }

    func testPlainParserJSONEscapedNewlinesEntitiesAndBlackCircledSteps() throws {
        let text = try fixtureText("plain_json_escaped_caption", ext: "txt")
        let result = plainParser.parse(text, mode: .caption)

        XCTAssertEqual(result.title, "チョコバナナパンケーキ")
        XCTAssertTrue(result.ingredients.contains { $0.contains("牛乳") && $0.contains("200ml") }, debug(result))
        XCTAssertTrue(result.ingredients.contains { $0.contains("砂糖") && $0.contains("大さじ2") }, debug(result))
        XCTAssertEqual(result.instructions.count, 3, debug(result))
        XCTAssertTrue(result.instructions.contains { $0.contains("フライパンで焼く") })
        XCTAssertFalse(result.instructions.contains { $0.contains("PR") })
    }

    func testInstagramCaptionNoisy() throws {
        let result = try extract("instagram_caption_noisy", ext: "txt")

        XCTAssertEqual(result.title, "レンジで作るチーズ蒸しパン")
        XCTAssertTrue(result.ingredients.contains { $0.contains("ホットケーキミックス") && $0.contains("100g") })
        XCTAssertTrue(result.ingredients.contains { $0.contains("卵") && $0.contains("1個") })
        XCTAssertTrue(result.ingredients.contains { $0.contains("牛乳") && $0.contains("80ml") })
        XCTAssertEqual(result.instructions.count, 4)
        XCTAssertTrue(result.instructions.contains { $0.contains("600W") && $0.contains("3分") })
        XCTAssertFalse(result.ingredients.contains { $0.contains("保存して") })
        XCTAssertFalse(result.instructions.contains { $0.contains("フォロー") })
        XCTAssertFalse(result.instructions.contains { $0.contains("PR") })
    }

    func testInstagramURLOnlyDoesNotInventRecipe() throws {
        let result = try extract("instagram_url_only", ext: "txt")

        XCTAssertTrue(result.ingredients.isEmpty)
        XCTAssertTrue(result.instructions.isEmpty)
        XCTAssertTrue(result.confidence < 0.3)
        XCTAssertTrue(result.warnings.contains { $0.contains("caption") || $0.contains("本文") || $0.contains("抽出できません") })
    }

    func testYouTubeURLOnlyDoesNotInventRecipe() throws {
        let result = try extract("youtube_url_only", ext: "txt")

        XCTAssertTrue(result.ingredients.isEmpty)
        XCTAssertTrue(result.instructions.isEmpty)
        XCTAssertTrue(result.confidence < 0.3)
        XCTAssertTrue(result.warnings.contains { $0.contains("caption") || $0.contains("本文") || $0.contains("抽出できません") })
    }

    func testYouTubeDescriptionPastedCanExtractRecipe() throws {
        let result = try extract("youtube_description_basic", ext: "txt")

        XCTAssertEqual(result.title, "基本のチキンカレー")
        XCTAssertTrue(result.ingredients.contains { $0.contains("鶏もも肉") && $0.contains("300g") }, debug(result))
        XCTAssertTrue(result.ingredients.contains { $0.contains("カレールウ") })
        XCTAssertEqual(result.instructions.count, 3)
        XCTAssertTrue(result.instructions.contains { $0.contains("カレールウ") && $0.contains("溶かす") })
    }

    func testInstagramEmbeddedCaptionFeedsImporterExtractorDraftIntegration() throws {
        let html = try fixtureText("instagram_caption_embedded", ext: "html")
        let inputURL = URL(string: "https://www.instagram.com/reel/debug/")!
        let initialFetched = importer.parseFetchedContent(html: html, inputURL: inputURL, importerType: "instagram")
        let caption = try XCTUnwrap(RecipeImporter.extractInstagramCaption(html: html, metadata: initialFetched.metadata))
        let draft = try makeDraft(
            html: html,
            inputURL: inputURL,
            importerType: "instagram",
            rawImportedTextOverride: caption,
            textSource: "instagramCaption"
        )

        XCTAssertEqual(draft.importedTextSource, "instagramCaption")
        XCTAssertTrue(draft.rawImportedText.contains("絶品トマトチキン"), debug(draft))
        XCTAssertTrue(draft.ingredientLines.contains { $0.contains("鶏もも肉") && $0.contains("300g") }, debug(draft))
        XCTAssertTrue(draft.instructionLines.contains { $0.contains("トマト缶") && $0.contains("煮る") }, debug(draft))
    }

    func testInstagramCaptionAvailableFeedsImporterExtractorDraftIntegration() throws {
        let html = try fixtureText("instagram_caption_available", ext: "html")
        let inputURL = URL(string: "https://www.instagram.com/reel/caption-available/")!
        let initialFetched = importer.parseFetchedContent(html: html, inputURL: inputURL, importerType: "instagram")
        let caption = try XCTUnwrap(RecipeImporter.extractInstagramCaption(html: html, metadata: initialFetched.metadata))
        let draft = try makeDraft(
            html: html,
            inputURL: inputURL,
            importerType: "instagram",
            rawImportedTextOverride: caption,
            textSource: "instagramCaption"
        )

        XCTAssertEqual(draft.importedTextSource, "instagramCaption")
        XCTAssertTrue(draft.ingredientLines.contains { $0.contains("豚こま肉") && $0.contains("200g") }, debug(draft))
        XCTAssertTrue(draft.ingredientLines.contains { $0.contains("しょうゆ") && $0.contains("大さじ1") }, debug(draft))
        XCTAssertEqual(draft.instructionLines.count, 3, debug(draft))
        XCTAssertTrue(draft.instructionLines.contains { $0.contains("豚こま肉") && $0.contains("片栗粉") }, debug(draft))
    }

    func testYouTubeEmbeddedDescriptionFeedsImporterExtractorDraftIntegration() throws {
        let html = try fixtureText("youtube_description_embedded", ext: "html")
        let inputURL = URL(string: "https://www.youtube.com/watch?v=debug123")!
        let description = try XCTUnwrap(RecipeImporter.extractYouTubeDescription(html: html))
        let draft = try makeDraft(
            html: html,
            inputURL: inputURL,
            importerType: "youtube",
            rawImportedTextOverride: description,
            textSource: "youtubeDescription"
        )

        XCTAssertEqual(RecipeImporter.youtubeVideoID(from: inputURL), "debug123")
        XCTAssertEqual(draft.importedTextSource, "youtubeDescription")
        XCTAssertTrue(draft.rawImportedText.contains("基本のチキンカレー"), debug(draft))
        XCTAssertTrue(draft.ingredientLines.contains { $0.contains("鶏もも肉") && $0.contains("300g") }, debug(draft))
        XCTAssertTrue(draft.instructionLines.contains { $0.contains("カレールウ") && $0.contains("溶かす") }, debug(draft))
    }

    func testYouTubeHTMLDescriptionFallbackFeedsPlainParserWithoutDataAPI() throws {
        let draft = try makeDraftFromFixture("youtube_description_embedded", ext: "html")

        XCTAssertEqual(draft.importedTextSource, "youtubeDescription")
        XCTAssertEqual(draft.importDiagnostics?.parserMode, "description")
        XCTAssertTrue(draft.rawImportedText.contains("基本のチキンカレー"), debug(draft))
        XCTAssertTrue(draft.ingredientLines.contains { $0.contains("鶏もも肉") && $0.contains("300g") }, debug(draft))
        XCTAssertTrue(draft.instructionLines.contains { $0.contains("カレールウ") && $0.contains("溶かす") }, debug(draft))
    }

    func testYouTubeDescriptionAvailableFeedsImporterExtractorDraftIntegration() throws {
        let html = try fixtureText("youtube_description_available", ext: "html")
        let inputURL = URL(string: "https://www.youtube.com/watch?v=descriptionAvailable")!
        let description = try XCTUnwrap(RecipeImporter.extractYouTubeDescription(html: html))
        let draft = try makeDraft(
            html: html,
            inputURL: inputURL,
            importerType: "youtube",
            rawImportedTextOverride: description,
            textSource: "youtubeDescription"
        )

        XCTAssertEqual(RecipeImporter.youtubeVideoID(from: inputURL), "descriptionAvailable")
        XCTAssertEqual(draft.importedTextSource, "youtubeDescription")
        XCTAssertTrue(draft.ingredientLines.contains { $0.contains("なす") && $0.contains("2本") }, debug(draft))
        XCTAssertTrue(draft.ingredientLines.contains { $0.contains("みそ") && $0.contains("大さじ1") }, debug(draft))
        XCTAssertEqual(draft.instructionLines.count, 3, debug(draft))
        XCTAssertTrue(draft.instructionLines.contains { $0.contains("みそだれ") && $0.contains("からめる") }, debug(draft))
    }

    func testStaticUnavailableFixturesDoNotInventRecipeText() throws {
        for expectation in Self.failingURLFixtureExpectations where expectation.expectedIngredientsCount == 0 && expectation.expectedInstructionsCount == 0 {
            let name = String(expectation.fixtureFileName.split(separator: ".").first ?? "")
            let ext = String(expectation.fixtureFileName.split(separator: ".").last ?? "html")
            let html = try fixtureText(name, ext: ext)
            let sourceURL = try fixtureSourceURL(name: name, ext: ext)
            if expectation.importerType == "instagram" {
                let fetched = importer.parseFetchedContent(html: html, inputURL: sourceURL, importerType: "instagram")
                XCTAssertNil(RecipeImporter.extractInstagramCaption(html: html, metadata: fetched.metadata))
                XCTAssertNotNil(RecipeImporter.instagramEmbedURL(from: sourceURL))
            }
            if expectation.importerType == "youtube" {
                XCTAssertNil(RecipeImporter.extractYouTubeDescription(html: html))
                XCTAssertNotNil(RecipeImporter.youtubeVideoID(from: sourceURL))
            }
            let draft = try makeDraftFromFixture(name, ext: ext)
            XCTAssertEqual(draft.sourceURL.absoluteString, URLNormalizer.normalizedString(for: expectation.sourceURL))
            XCTAssertTrue(draft.ingredientLines.isEmpty, debug(draft))
            XCTAssertTrue(draft.instructionLines.isEmpty, debug(draft))
            XCTAssertEqual(draft.importDiagnostics?.extractionSource, "none")
            XCTAssertEqual(draft.importDiagnostics?.extractorInputTextLength, 0)
            XCTAssertFalse(draft.extractionWarnings.isEmpty, debug(draft))
        }
    }

    @MainActor
    func testManualRealURLIntegrationSmoke() async throws {
        guard ProcessInfo.processInfo.environment["RUN_IMPORT_SMOKE_TESTS"] == "1" else {
            throw XCTSkip("Set RUN_IMPORT_SMOKE_TESTS=1 to fetch live URLs and print import diagnostics.")
        }

        let service = RecipeImportService()
        for expectation in Self.failingURLFixtureExpectations {
            let draft = try await service.importRecipe(from: expectation.sourceURL)
            let diagnostics = try XCTUnwrap(draft.importDiagnostics)
            print("""
            [RecipeImportSmoke]
            sourceURL: \(diagnostics.inputURL)
            finalURL: \(diagnostics.finalURL ?? "")
            importerType: \(diagnostics.importerType)
            rawHtmlLength: \(diagnostics.rawHtmlLength)
            rawImportedTextLength: \(diagnostics.rawImportedTextLength)
            recipeCandidateTextLength: \(diagnostics.recipeCandidateTextLength)
            extractorInputTextLength: \(diagnostics.extractorInputTextLength)
            extractionSource: \(diagnostics.extractionSource)
            rawImportedTextPreview: \(diagnostics.rawImportedTextPreview)
            recipeCandidateTextPreview: \(diagnostics.recipeCandidateTextPreview)
            extractorInputTextPreview: \(diagnostics.extractorInputTextPreview)
            extractedIngredients count: \(diagnostics.extractedIngredients.count)
            extractedInstructions count: \(diagnostics.extractedInstructions.count)
            warnings: \(draft.extractionWarnings.joined(separator: " | "))
            """)

            XCTAssertEqual(diagnostics.importerType, expectation.importerType)
            if expectation.sourceURL.contains("youtu") {
                XCTAssertEqual(RecipeImporter.youtubeVideoID(from: URL(string: expectation.sourceURL)!), "CdtVWTm-xU4")
            }
            if expectation.sourceURL.contains("mr-cheesecake") {
                XCTAssertGreaterThanOrEqual(draft.instructionLines.count, 6, debug(draft))
            }
            if expectation.sourceURL.contains("orangepage") {
                XCTAssertGreaterThanOrEqual(draft.instructionLines.count, 3, debug(draft))
            }
        }

        for expectation in Self.instagramLiveSmokeExpectations {
            let draft = try await service.importRecipe(from: expectation.sourceURL)
            let diagnostics = try XCTUnwrap(draft.importDiagnostics)
            print("""
            [RecipeImportSmoke][Instagram]
            sourceURL: \(diagnostics.inputURL)
            finalURL: \(diagnostics.finalURL ?? "")
            importerType: \(diagnostics.importerType)
            extractionSource: \(diagnostics.extractionSource)
            extractorInputTextLength: \(diagnostics.extractorInputTextLength)
            extractedIngredients count: \(diagnostics.extractedIngredients.count)
            extractedInstructions count: \(diagnostics.extractedInstructions.count)
            warnings: \(draft.extractionWarnings.joined(separator: " | "))
            expectedFailureMode: \(expectation.expectedFailureMode)
            """)

            XCTAssertEqual(diagnostics.importerType, expectation.importerType)
            XCTAssertEqual(diagnostics.extractionSource, "instagramCaption", debug(draft))
            XCTAssertGreaterThanOrEqual(draft.ingredientLines.count, expectation.minimumIngredientsCount, debug(draft))
            XCTAssertGreaterThanOrEqual(draft.instructionLines.count, expectation.minimumInstructionsCount, debug(draft))
        }
    }

    func testNoRecipeTextDoesNotInventRecipe() throws {
        let result = try extract("no_recipe_text", ext: "html")

        XCTAssertTrue(result.ingredients.isEmpty)
        XCTAssertTrue(result.instructions.isEmpty)
        XCTAssertTrue(result.confidence < 0.3)
        XCTAssertTrue(result.warnings.count > 0)
    }

    private func extract(_ name: String, ext: String) throws -> ExtractedRecipeText {
        let text = try fixtureText(name, ext: ext)
        return extractor.extract(from: text)
    }

    private func extractThroughImporter(_ name: String, ext: String) throws -> ExtractedRecipeText {
        let text = try fixtureText(name, ext: ext)
        let url = try fixtureSourceURL(name: name, ext: ext)
        let fetched = importer.parseFetchedContent(html: text, inputURL: url)
        let jsonLDRecipes = fetched.extractionSource == "jsonLD" ? fetched.jsonLDRecipes : []
        return extractor.extract(from: RecipeTextExtractorInput(
            html: "",
            visibleText: fetched.extractorInputText,
            metadata: fetched.metadata,
            jsonLDRecipes: jsonLDRecipes
        ))
    }

    private func makeDraftFromFixture(_ name: String, ext: String) throws -> ImportedRecipe {
        let text = try fixtureText(name, ext: ext)
        let url = try fixtureSourceURL(name: name, ext: ext)
        let detected = RecipeSourceKind.detect(urlString: url.absoluteString, host: url.host(percentEncoded: false) ?? "")
        let importerType = Self.failingURLFixtureExpectations.first { $0.fixtureFileName == "\(name).\(ext)" }?.importerType ?? detected.rawValue
        return try makeDraft(html: text, inputURL: url, importerType: importerType)
    }

    private func makeDraft(
        html: String,
        inputURL: URL,
        importerType: String = "web",
        rawImportedTextOverride: String? = nil,
        textSource: String = "html",
        warnings: [String] = []
    ) throws -> ImportedRecipe {
        try assertFixtureSourceURL(in: html, matches: inputURL.absoluteString)
        let fetched = importer.parseFetchedContent(
            html: html,
            inputURL: inputURL,
            importerType: importerType,
            rawImportedTextOverride: rawImportedTextOverride,
            textSource: textSource,
            warnings: warnings
        )
        let parserMode = parserMode(for: fetched)
        let extracted: ExtractedRecipeText
        switch parserMode {
        case "caption":
            extracted = plainParser.parse(fetched.extractorInputText, mode: .caption, metadataTitle: fetched.metadata.title)
        case "description":
            extracted = plainParser.parse(fetched.extractorInputText, mode: .description, metadataTitle: fetched.metadata.title)
        default:
            let jsonLDRecipes = fetched.extractionSource == "jsonLD" ? fetched.jsonLDRecipes : []
            extracted = extractor.extract(from: RecipeTextExtractorInput(
                html: "",
                visibleText: fetched.extractorInputText,
                metadata: fetched.metadata,
                jsonLDRecipes: jsonLDRecipes
            ))
        }
        var recipe = ImportedRecipe(
            title: extracted.title ?? "",
            summary: extracted.summary ?? "",
            sourceURL: fetched.finalURL ?? fetched.inputURL,
            sourceHost: fetched.inputURL.host(percentEncoded: false) ?? "",
            sourceImageURL: fetched.imageURL,
            imageData: nil,
            ingredientLines: extracted.ingredients,
            instructionLines: extracted.instructions,
            extractedRawText: fetched.visibleText,
            rawImportedText: fetched.visibleText,
            rawImportedHTML: fetched.html,
            importedTextSource: fetched.extractionSource,
            extractionConfidence: extracted.confidence,
            extractionWarnings: fetched.warnings + extracted.warnings,
            ingredientSource: extracted.ingredientSource,
            instructionSource: extracted.instructionSource
        )
        recipe.importDiagnostics = RecipeImportDiagnostics(
            inputURL: fetched.inputURL.absoluteString,
            finalURL: fetched.finalURL?.absoluteString,
            importerType: fetched.importerType,
            httpStatusCode: fetched.httpStatusCode,
            contentType: fetched.contentType,
            rawHtmlLength: fetched.html.count,
            rawImportedTextLength: fetched.visibleText.count,
            recipeCandidateTextLength: fetched.recipeCandidateText.count,
            extractorInputTextLength: fetched.extractorInputText.count,
            extractionSource: fetched.extractionSource,
            rawImportedTextPreview: String(fetched.visibleText.prefix(5000)),
            recipeCandidateTextPreview: String(fetched.recipeCandidateText.prefix(5000)),
            extractorInputTextPreview: String(fetched.extractorInputText.prefix(5000)),
            parserMode: parserMode,
            metadataTitle: fetched.metadata.title,
            ogTitle: fetched.metadata.ogTitle,
            hasJSONLD: !fetched.jsonLDRecipes.isEmpty,
            jsonLDRecipeCount: fetched.jsonLDRecipes.count,
            extractedTitle: extracted.title,
            extractedIngredients: extracted.ingredients,
            extractedInstructions: extracted.instructions,
            draftTitle: recipe.title,
            draftIngredientsText: recipe.ingredientLines.joined(separator: "\n"),
            draftInstructionsText: recipe.instructionLines.joined(separator: "\n"),
            warnings: recipe.extractionWarnings
        )
        return recipe
    }

    private func parserMode(for fetched: FetchedRecipeContent) -> String {
        switch fetched.extractionSource {
        case "instagramCaption":
            return "caption"
        case "youtubeDescription":
            return "description"
        default:
            return "webArticle"
        }
    }

    private static func jsonStringFragment(_ text: String) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: [text])
        let encoded = String(decoding: data, as: UTF8.self)
        return String(encoded.dropFirst(2).dropLast(2))
    }

    private func fixtureText(_ name: String, ext: String) throws -> String {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(
            forResource: name,
            withExtension: ext,
            subdirectory: "Fixtures/RecipeTextExtractor"
        ) ?? bundle.url(forResource: name, withExtension: ext))
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func fixtureSourceURL(name: String, ext: String) throws -> URL {
        let text = try fixtureText(name, ext: ext)
        if let source = text.firstCapture(pattern: #"Source URL:\s*([^<\n]+)"#)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           let url = URLNormalizer.normalizedURL(for: source) {
            return url
        }
        return URL(string: "https://example.com/\(name)")!
    }

    private func assertFixtureSourceURL(in fixture: String, matches expectedURL: String) throws {
        guard let source = fixture.firstCapture(pattern: #"Source URL:\s*([^<\n]+)"#)?
            .trimmingCharacters(in: .whitespacesAndNewlines) else {
            return
        }
        guard URLNormalizer.normalizedURL(for: source) != nil else {
            return
        }
        XCTAssertEqual(URLNormalizer.normalizedString(for: source), URLNormalizer.normalizedString(for: expectedURL))
    }

    private func debug(_ result: ExtractedRecipeText) -> String {
        "title=\(result.title ?? "nil") ingredients=\(result.ingredients) instructions=\(result.instructions) warnings=\(result.warnings) confidence=\(result.confidence)"
    }

    private func debug(_ draft: ImportedRecipe) -> String {
        let diagnostics = draft.importDiagnostics
        return "title=\(draft.title) ingredients=\(draft.ingredientLines) instructions=\(draft.instructionLines) warnings=\(draft.extractionWarnings) extractionSource=\(diagnostics?.extractionSource ?? "nil") extractorInput=\(diagnostics?.extractorInputTextPreview.prefix(500) ?? "") raw=\(String(draft.rawImportedText.prefix(300)))"
    }
}

private extension String {
    func firstCapture(pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(startIndex..<endIndex, in: self)
        guard let match = regex.firstMatch(in: self, range: range),
              match.numberOfRanges > 1,
              let swiftRange = Range(match.range(at: 1), in: self) else {
            return nil
        }
        return String(self[swiftRange])
    }
}
