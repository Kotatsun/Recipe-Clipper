import Foundation
import LinkPresentation
import UIKit
import UniformTypeIdentifiers

struct FetchedRecipeContent {
    var inputURL: URL
    var finalURL: URL?
    var httpStatusCode: Int?
    var contentType: String?
    var importerType: String
    var html: String
    var metadata: RecipeMetadata
    var jsonLDRecipes: [JSONLDRecipe]
    var visibleText: String
    var recipeCandidateText: String
    var extractorInputText: String
    var extractionSource: String
    var imageURL: URL?
    var textSource: String = "html"
    var warnings: [String] = []
}

struct RecipeImportDiagnostics {
    var inputURL: String
    var finalURL: String?
    var importerType: String
    var httpStatusCode: Int?
    var contentType: String?
    var rawHtmlLength: Int
    var rawImportedTextLength: Int
    var recipeCandidateTextLength: Int
    var extractorInputTextLength: Int
    var extractionSource: String
    var rawImportedTextPreview: String
    var recipeCandidateTextPreview: String
    var extractorInputTextPreview: String
    var reparseInputTextLength: Int = 0
    var reparseInputTextPreview: String = ""
    var reparseInputTextHash: String = ""
    var normalizedReparseInputPreview: String = ""
    var parserMode: String = "webArticle"
    var metadataTitle: String?
    var ogTitle: String?
    var hasJSONLD: Bool
    var jsonLDRecipeCount: Int
    var extractedTitle: String?
    var extractedIngredients: [String]
    var extractedInstructions: [String]
    var draftTitle: String
    var draftIngredientsText: String
    var draftInstructionsText: String
    var warnings: [String]

    func log() {
        #if DEBUG
        print("""
        [RecipeImportDebug]
        sourceURL:
        \(inputURL)
        finalURL:
        \(finalURL ?? "")
        importerType:
        \(importerType)
        rawHtmlLength:
        \(rawHtmlLength)
        rawImportedTextLength:
        \(rawImportedTextLength)
        recipeCandidateTextLength:
        \(recipeCandidateTextLength)
        extractorInputTextLength:
        \(extractorInputTextLength)
        extractionSource:
        \(extractionSource)
        rawImportedTextPreview:
        \(rawImportedTextPreview)
        recipeCandidateTextPreview:
        \(recipeCandidateTextPreview)
        extractorInputTextPreview:
        \(extractorInputTextPreview)
        reparseInputTextLength:
        \(reparseInputTextLength)
        reparseInputTextPreview:
        \(reparseInputTextPreview)
        reparseInputTextHash:
        \(reparseInputTextHash)
        normalizedReparseInputPreview:
        \(normalizedReparseInputPreview)
        parserMode:
        \(parserMode)
        jsonLDRecipeCount:
        \(jsonLDRecipeCount)
        metadataTitle:
        \(metadataTitle ?? "")
        ogTitle:
        \(ogTitle ?? "")
        extractedTitle:
        \(extractedTitle ?? "")
        extractedIngredients:
        \(extractedIngredients.joined(separator: "\n"))
        extractedInstructions:
        \(extractedInstructions.joined(separator: "\n"))
        draftTitle:
        \(draftTitle)
        draftIngredientsText:
        \(draftIngredientsText)
        draftInstructionsText:
        \(draftInstructionsText)
        warnings:
        \(warnings.joined(separator: "\n"))
        """)
        #endif
    }
}

// 正規化で末尾スラッシュを落としたURL等に対し、httpへ301するサイトがある
// (例: kikkoman.co.jp)。ATSに弾かれる前にリダイレクト先をhttpsへ昇格させる
private final class HTTPSUpgradingRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        var request = request
        if let url = request.url,
           url.scheme == "http",
           var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.scheme = "https"
            request.url = components.url ?? url
        }
        completionHandler(request)
    }
}

final class RecipeImporter {
    private static let redirectDelegate = HTTPSUpgradingRedirectDelegate()

    private struct YouTubeOEmbed {
        var title: String?
        var thumbnailURL: URL?
    }

    enum ImportError: LocalizedError {
        case invalidURL
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "URLとして解釈できませんでした。https:// から始まるURLを入力してください。"
            case .emptyResponse:
                return "ページ本文を取得できませんでした。空欄のまま保存前確認へ進みます。"
            }
        }
    }

    func fetch(from rawText: String) async throws -> FetchedRecipeContent {
        let url = try normalizeURL(rawText)
        return try await fetch(from: url)
    }

    func fetch(from url: URL) async throws -> FetchedRecipeContent {
        try await fetchWeb(from: url, importerType: "web")
    }

    func fetchInstagram(from url: URL) async throws -> FetchedRecipeContent {
        let canonicalURL = Self.canonicalInstagramURL(from: url) ?? url
        let fetched = try await fetchWeb(from: canonicalURL, importerType: "instagram")
        if let caption = Self.extractInstagramCaption(html: fetched.html, metadata: fetched.metadata) {
            var captionFetched = parseFetchedContent(
                html: fetched.html,
                inputURL: fetched.inputURL,
                finalURL: fetched.finalURL,
                httpStatusCode: fetched.httpStatusCode,
                contentType: fetched.contentType,
                importerType: "instagram",
                rawImportedTextOverride: caption,
                textSource: "instagramCaption"
            )
            captionFetched.imageURL = fetched.imageURL
            return captionFetched
        }

        if let embedURL = Self.instagramEmbedURL(from: canonicalURL),
           let embedHTML = try? await fetchHTMLString(from: embedURL),
           let caption = Self.extractInstagramCaption(
                html: embedHTML,
                metadata: parseFetchedContent(html: embedHTML, inputURL: embedURL, importerType: "instagram").metadata
           ) ?? Self.instagramCaptionFromEmbedText(embedHTML) {
            var captionFetched = parseFetchedContent(
                html: fetched.html,
                inputURL: fetched.inputURL,
                finalURL: fetched.finalURL,
                httpStatusCode: fetched.httpStatusCode,
                contentType: fetched.contentType,
                importerType: "instagram",
                rawImportedTextOverride: caption,
                textSource: "instagramCaption"
            )
            captionFetched.imageURL = fetched.imageURL
            return captionFetched
        }

        var fallback = fetched
        fallback.warnings.append("Instagramのcaptionを自動取得できませんでした。投稿本文を貼り付けると再抽出できます。")
        fallback.extractionSource = "none"
        fallback.recipeCandidateText = ""
        fallback.extractorInputText = ""
        return fallback
    }

    func fetchYouTube(from url: URL) async throws -> FetchedRecipeContent {
        let fetched = try await fetchWeb(from: url, importerType: "youtube")
        let videoID = Self.youtubeVideoID(from: url)
        let oEmbed: YouTubeOEmbed?
        if videoID != nil {
            oEmbed = try? await fetchYouTubeOEmbed(for: url)
        } else {
            oEmbed = nil
        }
        let apiDescription: String?
        var warnings: [String] = []
        if let videoID {
            if Self.youtubeAPIKey() == nil {
                warnings.append("YouTube Data API key未設定のため説明欄を取得できません。")
                apiDescription = nil
            } else {
                apiDescription = try? await fetchYouTubeDataAPIDescription(videoID: videoID)
                if apiDescription?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                    warnings.append("YouTubeの説明欄を取得できませんでした。YouTube Data API keyが未設定、または説明欄取得に失敗した可能性があります。")
                }
            }
        } else {
            warnings.append("YouTubeのvideoIdを抽出できませんでした。")
            apiDescription = nil
        }
        let htmlDescription = Self.extractYouTubeDescription(html: fetched.html)
        let description = Self.firstNonEmpty([apiDescription, htmlDescription])

        var metadata = fetched.metadata
        if metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            metadata.title = oEmbed?.title
        }
        let imageURL = fetched.imageURL ?? oEmbed?.thumbnailURL

        if let description {
            var descriptionFetched = parseFetchedContent(
                html: fetched.html,
                inputURL: fetched.inputURL,
                finalURL: fetched.finalURL,
                httpStatusCode: fetched.httpStatusCode,
                contentType: fetched.contentType,
                importerType: "youtube",
                rawImportedTextOverride: description,
                textSource: "youtubeDescription"
            )
            descriptionFetched.metadata = metadata
            descriptionFetched.imageURL = imageURL
            return descriptionFetched
        }

        var fallback = fetched
        fallback.metadata = metadata
        fallback.imageURL = imageURL
        fallback.warnings.append(contentsOf: warnings)
        fallback.warnings.append("YouTubeの説明欄を取得できませんでした。YouTube Data API keyが未設定、または説明欄取得に失敗した可能性があります。")
        fallback.extractionSource = "none"
        fallback.recipeCandidateText = ""
        fallback.extractorInputText = ""
        return fallback
    }

    func fetchCookpad(from url: URL) async throws -> FetchedRecipeContent {
        try await fetchWeb(from: url, importerType: "cookpad")
    }

    private func fetchWeb(from url: URL, importerType: String) async throws -> FetchedRecipeContent {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("ja,en-US;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await URLSession.shared.data(for: request, delegate: Self.redirectDelegate)
        let http = response as? HTTPURLResponse
        let html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .shiftJIS)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        return parseFetchedContent(
            html: html,
            inputURL: url,
            finalURL: response.url,
            httpStatusCode: http?.statusCode,
            contentType: http?.value(forHTTPHeaderField: "Content-Type"),
            importerType: importerType
        )
    }

    func parseFetchedContent(
        html: String,
        inputURL: URL,
        finalURL: URL? = nil,
        httpStatusCode: Int? = 200,
        contentType: String? = "text/html",
        importerType: String = "web",
        rawImportedTextOverride: String? = nil,
        textSource: String = "html",
        warnings: [String] = []
    ) -> FetchedRecipeContent {
        let baseURL = finalURL ?? inputURL
        let metaTags = Self.parseMetaTags(html: html)
        let metadata = RecipeMetadata(
            title: Self.parseTitle(html: html),
            description: metaTags["description"],
            ogTitle: metaTags["og:title"],
            ogDescription: metaTags["og:description"],
            twitterTitle: metaTags["twitter:title"],
            twitterDescription: metaTags["twitter:description"]
        )
        let jsonLDRecipes = Self.parseJSONLDRecipes(html: html, baseURL: baseURL)
        let effectiveRawImportedTextOverride = rawImportedTextOverride
            ?? (importerType == "youtube" ? Self.extractYouTubeDescription(html: html) : nil)
        let visibleText = effectiveRawImportedTextOverride ?? RecipeTextExtractor.visibleText(fromHTML: html)
        let extractionPlan = Self.extractionPlan(
            html: html,
            visibleText: visibleText,
            importerType: importerType,
            rawImportedTextOverride: effectiveRawImportedTextOverride,
            jsonLDRecipes: jsonLDRecipes
        )
        let imageURL = Self.firstURL([
            jsonLDRecipes.compactMap(\.imageURL).first,
            Self.absoluteURL(from: metaTags["og:image"], baseURL: baseURL),
            Self.absoluteURL(from: metaTags["og:image:secure_url"], baseURL: baseURL),
            Self.absoluteURL(from: metaTags["twitter:image"], baseURL: baseURL),
            Self.parseBestImageTagURL(html: html, baseURL: baseURL)
        ])

        #if DEBUG
        print("[RecipeImport] fetchedHTMLPreview=\(String(visibleText.prefix(3000)))")
        #endif

        return FetchedRecipeContent(
            inputURL: inputURL,
            finalURL: finalURL,
            httpStatusCode: httpStatusCode,
            contentType: contentType,
            importerType: importerType,
            html: html,
            metadata: metadata,
            jsonLDRecipes: jsonLDRecipes,
            visibleText: visibleText,
            recipeCandidateText: extractionPlan.recipeCandidateText,
            extractorInputText: extractionPlan.extractorInputText,
            extractionSource: extractionPlan.extractionSource,
            imageURL: imageURL,
            textSource: extractionPlan.extractionSource == "none" ? textSource : extractionPlan.extractionSource,
            warnings: warnings + extractionPlan.warnings
        )
    }

    private struct ExtractionPlan {
        var recipeCandidateText: String
        var extractorInputText: String
        var extractionSource: String
        var warnings: [String] = []
    }

    private nonisolated static func extractionPlan(
        html: String,
        visibleText: String,
        importerType: String,
        rawImportedTextOverride: String?,
        jsonLDRecipes: [JSONLDRecipe]
    ) -> ExtractionPlan {
        if importerType == "instagram" {
            guard let caption = rawImportedTextOverride?.trimmingCharacters(in: .whitespacesAndNewlines), !caption.isEmpty else {
                return ExtractionPlan(recipeCandidateText: "", extractorInputText: "", extractionSource: "none")
            }
            return ExtractionPlan(recipeCandidateText: caption, extractorInputText: caption, extractionSource: "instagramCaption")
        }

        if importerType == "youtube" {
            guard let description = rawImportedTextOverride?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty else {
                return ExtractionPlan(recipeCandidateText: "", extractorInputText: "", extractionSource: "none")
            }
            return ExtractionPlan(recipeCandidateText: description, extractorInputText: description, extractionSource: "youtubeDescription")
        }

        // JSON-LDがサーバ側の文字コードバグで「?」だらけになっているサイトがあるため、
        // 本文らしい文字を含む行が過半数のときだけJSON-LDを採用し、
        // 壊れている場合はHTML本文からの抽出にフォールバックする
        if let recipe = bestJSONLDRecipe(from: jsonLDRecipes),
           recipe.ingredients.count >= 2,
           !recipe.instructions.isEmpty,
           jsonLDLinesLookUsable(recipe.ingredients),
           jsonLDLinesLookUsable(recipe.instructions) {
            let text = structuredRecipeText(from: recipe)
            return ExtractionPlan(recipeCandidateText: text, extractorInputText: text, extractionSource: "jsonLD")
        }

        if importerType == "cookpad",
           let cookpadText = cookpadDOMRecipeText(fromHTML: html) {
            return ExtractionPlan(recipeCandidateText: cookpadText, extractorInputText: cookpadText, extractionSource: "cookpadDOM")
        }

        if let candidate = articleCandidateText(fromHTML: html), !candidate.isEmpty {
            return ExtractionPlan(recipeCandidateText: candidate, extractorInputText: candidate, extractionSource: "articleCandidate")
        }

        // HTMLブロック単位で候補が取れなかった場合の最終フォールバック。
        // 可視テキスト全体から材料/作り方見出し起点で絞り込み、
        // レシピらしさ(見出し+分量or手順番号)を満たすときだけ採用する
        let focusedVisible = focusedRecipeText(fromVisibleText: visibleText)
        if recipeTextLooksUsable(focusedVisible) {
            return ExtractionPlan(
                recipeCandidateText: focusedVisible,
                extractorInputText: focusedVisible,
                extractionSource: "visibleTextFocused"
            )
        }

        return ExtractionPlan(
            recipeCandidateText: "",
            extractorInputText: "",
            extractionSource: "none",
            warnings: ["レシピ候補本文を抽出できませんでした。ページ全文から材料・手順を推測しません。"]
        )
    }

    private nonisolated static func structuredRecipeText(from recipe: JSONLDRecipe) -> String {
        var parts: [String] = []
        if let title = recipe.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            parts.append(title)
        }
        if !recipe.ingredients.isEmpty {
            parts.append("材料")
            parts.append(contentsOf: recipe.ingredients)
        }
        if !recipe.instructions.isEmpty {
            parts.append("作り方")
            parts.append(contentsOf: recipe.instructions.enumerated().map { index, line in
                line.range(of: #"^(\([0-9０-９]+\)|（[0-9０-９]+）|[0-9０-９]+[\.)）．。])"#, options: .regularExpression) == nil
                    ? "\(index + 1). \(line)"
                    : line
            })
        }
        return parts.joined(separator: "\n")
    }

    private nonisolated static func cookpadDOMRecipeText(fromHTML html: String) -> String? {
        let text = RecipeTextExtractor.visibleText(fromHTML: sanitizedRecipeHTML(html))
        let focused = focusedRecipeText(fromVisibleText: text)
        guard recipeTextLooksUsable(focused) else { return nil }
        return focused
    }

    private nonisolated static func articleCandidateText(fromHTML html: String) -> String? {
        let sanitized = sanitizedRecipeHTML(html)
        let blocks = candidateHTMLBlocks(from: sanitized)
        let scored = blocks
            .map { block -> (text: String, score: Int) in
                let text = RecipeTextExtractor.visibleText(fromHTML: block)
                return (focusedRecipeText(fromVisibleText: text), scoreRecipeBlock(text))
            }
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.score > $1.score }

        // 最高スコアのブロックがネストしたdivの途中で切れている場合があるため、
        // 使える本文が得られる候補までスコア順に試す
        for candidate in scored where candidate.score > 0 {
            if recipeTextLooksUsable(candidate.text) {
                return candidate.text
            }
        }
        return nil
    }

    private nonisolated static func sanitizedRecipeHTML(_ html: String) -> String {
        var text = html
        let removablePatterns = [
            "<script\\b[^>]*>.*?</script>",
            "<style\\b[^>]*>.*?</style>",
            "<noscript\\b[^>]*>.*?</noscript>",
            "<iframe\\b[^>]*>.*?</iframe>",
            "<svg\\b[^>]*>.*?</svg>",
            "<header\\b[^>]*>.*?</header>",
            "<footer\\b[^>]*>.*?</footer>",
            "<nav\\b[^>]*>.*?</nav>",
            "<aside\\b[^>]*>.*?</aside>",
            "<form\\b[^>]*>.*?</form>"
        ]
        for pattern in removablePatterns {
            text = text.replacingOccurrences(of: pattern, with: "\n", options: [.regularExpression, .caseInsensitive])
        }
        return text
    }

    private nonisolated static func candidateHTMLBlocks(from html: String) -> [String] {
        let blockPatterns = [
            #"<article\b[^>]*>.*?</article>"#,
            #"<main\b[^>]*>.*?</main>"#,
            #"<section\b[^>]*(?:recipe|article|content|entry|journal|post|food)[^>]*>.*?</section>"#,
            #"<div\b[^>]*(?:recipe|article|content|entry|journal|post|food)[^>]*>.*?</div>"#,
            #"<body\b[^>]*>.*?</body>"#
        ]
        let blocks = blockPatterns.flatMap { matches(pattern: $0, in: html) }
        return blocks.isEmpty ? [html] : blocks
    }

    private nonisolated static func focusedRecipeText(fromVisibleText text: String) -> String {
        let lines = candidateLineBreaksInserted(text)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { $0.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression) }
            .filter { !$0.isEmpty }

        guard let startIndex = lines.firstIndex(where: { isRecipeStartLine($0) }) else {
            return ""
        }

        var result: [String] = []
        var seenInstructionHeading = false
        for line in lines.dropFirst(startIndex) {
            if isInstructionHeadingLine(line) {
                seenInstructionHeading = true
            }

            if seenInstructionHeading, isSupplementalRecipeLine(line) {
                continue
            }
            if isHardStopLine(line), result.contains(where: isInstructionHeadingLine) {
                break
            }
            if isLowValueNoiseLine(line) {
                continue
            }
            result.append(line)
        }
        return result.joined(separator: "\n")
    }

    private nonisolated static func candidateLineBreaksInserted(_ text: String) -> String {
        text
            .replacingOccurrences(
                of: #"(?<!^)(?<!\n)(?=\s*(?:\([0-9０-９]+\)|（[0-9０-９]+）|[①②③④⑤⑥⑦⑧⑨⑩]))"#,
                with: "\n",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?<!^)(?<!\n)(?<![\(（])(?=\s*[0-9０-９]+[\.)）．。])"#,
            with: "\n",
            options: .regularExpression
            )
    }

    private nonisolated static func isRecipeStartLine(_ line: String) -> Bool {
        isIngredientHeadingLine(line) || isInstructionHeadingLine(line)
    }

    private nonisolated static func isIngredientHeadingLine(_ line: String) -> Bool {
        // 「🍳材料」「≪材料≫」「■材料」のような飾り付き見出しも開始行として認める
        line.range(
            of: #"^[\p{So}\p{Sk}\p{P}\p{Sm}\s\\]*(?:材料|ingredients)(?:はこちら|はこれ)?(?:$|[^\p{L}\p{N}])"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private nonisolated static func isInstructionHeadingLine(_ line: String) -> Bool {
        line.range(
            of: #"^[\p{So}\p{Sk}\p{P}\p{Sm}\s\\]*(?:作り方|作りかた|つくり方|手順|instructions|directions|method)(?:$|[^\p{L}\p{N}])"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private nonisolated static func isHardStopLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        let stops = [
            "関連記事", "記事一覧", "著者紹介", "著者", "バックナンバー", "mail magazine",
            "topics", "お問い合わせ", "コメント", "sns", "instagram", "facebook", "twitter",
            "おすすめ", "ランキング", "プロフィール", "メールマガジン",
            "栄養成分", "基準重量", "使われている商品"
        ]
        return stops.contains { lower.contains($0) }
    }

    private nonisolated static func isSupplementalRecipeLine(_ line: String) -> Bool {
        let stripped = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if stripped.hasPrefix("▶︎") || stripped.hasPrefix("▷") {
            return true
        }
        return stripped.range(of: #"^(Point|ポイント)(?:$|[\s:：])"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private nonisolated static func isLowValueNoiseLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        let noise = ["シェア", "共有", "フォロー", "ログイン", "会員登録", "レシピを保存", "アプリでひらく"]
        return noise.contains { lower.contains($0) }
    }

    private nonisolated static func recipeTextLooksUsable(_ text: String) -> Bool {
        let lower = text.lowercased()
        let hasIngredients = lower.contains("材料") || lower.contains("ingredients")
        let hasInstructions = lower.contains("作り方") || lower.contains("作りかた")
            || lower.contains("つくり方") || lower.contains("つくりかた")
            || lower.contains("手順") || lower.contains("instructions")
        let hasQuantity = text.range(of: #"[0-9０-９./]+\s*(g|kg|ml|cc|l|L|個|本|枚|大さじ|小さじ|カップ)|少々|適量"#, options: .regularExpression) != nil
        let hasStep = text.range(of: #"(\([0-9０-９]+\)|（[0-9０-９]+）|[0-9０-９]+[\.)）．。])"#, options: .regularExpression) != nil
        return hasIngredients && hasInstructions && (hasQuantity || hasStep)
    }

    private nonisolated static func scoreRecipeBlock(_ text: String) -> Int {
        let lower = text.lowercased()
        var score = 0
        if lower.contains("材料") || lower.contains("ingredients") { score += 20 }
        if lower.contains("作り方") || lower.contains("作りかた")
            || lower.contains("つくり方") || lower.contains("つくりかた")
            || lower.contains("手順") || lower.contains("instructions") { score += 20 }
        score += min(matches(pattern: #"[0-9０-９./]+\s*(g|kg|ml|cc|l|L|個|本|枚|大さじ|小さじ|カップ)|少々|適量"#, in: text).count, 12)
        score += min(matches(pattern: #"(\([0-9０-９]+\)|（[0-9０-９]+）|[0-9０-９]+[\.)）．。])"#, in: text).count, 12)
        let penalties = ["関連記事", "記事一覧", "著者紹介", "バックナンバー", "mail magazine", "topics", "お問い合わせ", "sns", "facebook", "twitter", "instagram"]
        score -= penalties.reduce(0) { partial, token in partial + (lower.contains(token.lowercased()) ? 10 : 0) }
        return score
    }

    private nonisolated static func bestJSONLDRecipe(from recipes: [JSONLDRecipe]) -> JSONLDRecipe? {
        recipes.max { lhs, rhs in
            scoreJSONLDRecipe(lhs) < scoreJSONLDRecipe(rhs)
        }
    }

    // 記号・数字・空白を除いて文字が残る行(=本文らしい行)が過半数かどうか。
    // 「???????」「2. ????」のような文字化け行だけのリストを弾く
    nonisolated static func jsonLDLinesLookUsable(_ lines: [String]) -> Bool {
        guard !lines.isEmpty else { return false }
        let usableCount = lines.filter { line in
            line.range(of: #"\p{L}"#, options: .regularExpression) != nil
        }.count
        return usableCount * 2 >= lines.count
    }

    private nonisolated static func scoreJSONLDRecipe(_ recipe: JSONLDRecipe) -> Int {
        var score = 0
        if recipe.title?.isEmpty == false { score += 2 }
        if recipe.description?.isEmpty == false { score += 1 }
        score += min(recipe.ingredients.count, 20) * 3
        score += min(recipe.instructions.count, 20) * 3
        return score
    }

    private func normalizeURL(_ rawText: String) throws -> URL {
        if let url = URLNormalizer.normalizedURL(for: rawText) {
            return url
        }
        throw ImportError.invalidURL
    }

    private func fetchYouTubeOEmbed(for url: URL) async throws -> YouTubeOEmbed {
        var components = URLComponents(string: "https://www.youtube.com/oembed")!
        components.queryItems = [
            URLQueryItem(name: "url", value: url.absoluteString),
            URLQueryItem(name: "format", value: "json")
        ]
        let data = try await fetchData(from: components.url!)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ImportError.emptyResponse
        }
        return YouTubeOEmbed(
            title: object["title"] as? String,
            thumbnailURL: (object["thumbnail_url"] as? String).flatMap(URL.init(string:))
        )
    }

    private func fetchYouTubeDataAPIDescription(videoID: String) async throws -> String? {
        guard let apiKey = Self.youtubeAPIKey() else { return nil }
        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/videos")!
        components.queryItems = [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "id", value: videoID),
            URLQueryItem(name: "key", value: apiKey)
        ]
        let data = try await fetchData(from: components.url!)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = object["items"] as? [[String: Any]],
              let snippet = items.first?["snippet"] as? [String: Any] else {
            return nil
        }
        return (snippet["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func fetchData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("RecipeClipping/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<400).contains(http.statusCode) {
            throw ImportError.emptyResponse
        }
        return data
    }

    private func fetchHTMLString(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("ja,en-US;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await URLSession.shared.data(for: request, delegate: Self.redirectDelegate)
        if let http = response as? HTTPURLResponse, !(200..<400).contains(http.statusCode) {
            throw ImportError.emptyResponse
        }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .shiftJIS)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
    }

    nonisolated static func extractInstagramCaption(html: String, metadata: RecipeMetadata) -> String? {
        let metaCandidates = [
            metadata.ogDescription,
            metadata.description,
            metadata.twitterDescription
        ].compactMap(cleanInstagramCaptionCandidate)

        let scriptCandidates = matches(pattern: "<script\\b[^>]*>(.*?)</script>", in: html, captureGroup: 1)
            .flatMap { script in
                [
                    firstCapture(pattern: #"edge_media_to_caption"\s*:\s*\{.*?"text"\s*:\s*"((?:\\.|[^"\\])*)""#, in: script),
                    firstCapture(pattern: #"edge_media_to_caption\\":\{.*?\\"text\\":\\"((?:\\\\.|[^\"])*)\\""#, in: script),
                    firstCapture(pattern: #""caption"\s*:\s*\{.*?"text"\s*:\s*"((?:\\.|[^"\\])*)""#, in: script),
                    firstCapture(pattern: #"\\"caption\\"\s*:\s*\{.*?\\"text\\"\s*:\s*\\"((?:\\\\.|[^\"])*)\\""#, in: script),
                    firstCapture(pattern: #""caption"\s*:\s*"((?:\\.|[^"\\])*)""#, in: script),
                    firstCapture(pattern: #"\\"caption\\"\s*:\s*\\"((?:\\\\.|[^\"])*)\\""#, in: script),
                    firstCapture(pattern: #""text"\s*:\s*"((?:\\.|[^"\\]){40,})""#, in: script)
                ]
                .compactMap { $0 }
                .compactMap(decodeJSONStringFragment)
                .compactMap(cleanInstagramCaptionCandidate)
            }

        return (scriptCandidates + metaCandidates)
            .filter { looksLikeRecipeBody($0) || $0.count >= 80 }
            .max { lhs, rhs in scoreCaption(lhs) < scoreCaption(rhs) }
    }

    nonisolated static func instagramEmbedURL(from url: URL) -> URL? {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2, ["p", "reel", "tv"].contains(parts[0].lowercased()) else {
            return nil
        }
        return URL(string: "https://www.instagram.com/\(parts[0])/\(parts[1])/embed/captioned/")
    }

    nonisolated static func canonicalInstagramURL(from url: URL) -> URL? {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2, ["p", "reel", "tv"].contains(parts[0].lowercased()) else {
            return url
        }
        return URL(string: "https://www.instagram.com/\(parts[0])/\(parts[1])/")
    }

    nonisolated static func instagramCaptionFromEmbedText(_ html: String) -> String? {
        let text = RecipeTextExtractor.visibleText(fromHTML: html)
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let joined = lines.joined(separator: "\n")
        guard looksLikeRecipeBody(joined) || joined.count >= 80 else { return nil }
        return joined
    }

    private nonisolated static func cleanInstagramCaptionCandidate(_ raw: String?) -> String? {
        guard var text = raw?.htmlDecoded.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        if let quoted = firstCapture(pattern: #"(?s)^\s*[\d,.]+\s+likes?,\s*[\d,.]+\s+comments?\s+-\s+.*?:\s*"(.+?)"\s*\.?\s*$"#, in: text) {
            text = quoted
        } else if let quoted = firstCapture(pattern: #"(?s):\s*"(.+)"\s*\.?\s*$"#, in: text) {
            text = quoted
        }
        text = text
            .replacingOccurrences(of: "\\\\n", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\/", with: "/")
            .htmlDecoded
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.range(of: "^(View|See) all \\d+ comments", options: [.regularExpression, .caseInsensitive]) != nil {
            return nil
        }
        return text.isEmpty ? nil : text
    }

    nonisolated static func extractYouTubeDescription(html: String) -> String? {
        let scripts = matches(pattern: "<script\\b[^>]*>(.*?)</script>", in: html, captureGroup: 1)
        let candidates = scripts.flatMap { script in
            [
                firstCapture(pattern: #""shortDescription"\s*:\s*"((?:\\.|[^"\\])*)""#, in: script),
                firstCapture(pattern: #""description"\s*:\s*\{"simpleText"\s*:\s*"((?:\\.|[^"\\])*)""#, in: script)
            ]
        }
        .compactMap { $0 }
        .compactMap(decodeJSONStringFragment)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

        return candidates.max { lhs, rhs in lhs.count < rhs.count }
    }

    nonisolated static func youtubeVideoID(from url: URL) -> String? {
        let host = url.host(percentEncoded: false)?.lowercased() ?? ""
        if host.contains("youtu.be") {
            return url.pathComponents.dropFirst().first
        }
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let id = components.queryItems?.first(where: { $0.name == "v" })?.value,
           !id.isEmpty {
            return id
        }
        let components = url.pathComponents
        if let markerIndex = components.firstIndex(where: { ["shorts", "embed", "live"].contains($0) }),
           components.indices.contains(markerIndex + 1) {
            return components[markerIndex + 1]
        }
        return nil
    }

    private nonisolated static func youtubeAPIKey() -> String? {
        let keys = [
            Bundle.main.object(forInfoDictionaryKey: "YOUTUBE_DATA_API_KEY") as? String,
            Bundle.main.object(forInfoDictionaryKey: "YouTubeDataAPIKey") as? String,
            ProcessInfo.processInfo.environment["YOUTUBE_DATA_API_KEY"]
        ]
        return firstNonEmpty(keys)
    }

    private nonisolated static func decodeJSONStringFragment(_ fragment: String) -> String? {
        var current = fragment
        for _ in 0..<3 {
            let sanitized = current
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: "\t", with: "\\t")
            let json = "\"\(sanitized)\""
            guard let data = json.data(using: .utf8),
                  let decoded = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? String,
                  decoded != current else {
                break
            }
            current = decoded
        }
        return current
    }

    private nonisolated static func looksLikeRecipeBody(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("材料")
            || lower.contains("作り方")
            || lower.contains("ingredients")
            || lower.contains("instructions")
            || lower.range(of: "[0-9０-９]+\\s*(g|ml|個|大さじ|小さじ)", options: .regularExpression) != nil
    }

    private nonisolated static func scoreCaption(_ text: String) -> Int {
        var score = min(text.count / 20, 50)
        if looksLikeRecipeBody(text) { score += 50 }
        if text.contains("材料") { score += 20 }
        if text.contains("作り方") || text.contains("手順") { score += 20 }
        return score
    }

    private nonisolated static func firstNonEmpty(_ values: [String?]) -> String? {
        values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private static func parseMetaTags(html: String) -> [String: String] {
        var result: [String: String] = [:]
        for tag in matches(pattern: "<meta\\b[^>]*>", in: html) {
            let key = attribute("property", in: tag) ?? attribute("name", in: tag) ?? attribute("itemprop", in: tag)
            let content = attribute("content", in: tag)
            if let key = key?.lowercased(), let content, !content.isEmpty, result[key] == nil {
                result[key] = content.htmlDecoded
            }
        }
        return result
    }

    private static func parseTitle(html: String) -> String? {
        firstCapture(pattern: "<title[^>]*>(.*?)</title>", in: html)?.htmlDecoded
    }

    private static func parseJSONLDRecipes(html: String, baseURL: URL) -> [JSONLDRecipe] {
        let scripts = matches(pattern: "<script(?=[^>]*application/ld\\+json)[^>]*>(.*?)</script>", in: html, captureGroup: 1)
        var recipes: [JSONLDRecipe] = []

        for script in scripts {
            let cleaned = script
                .htmlEntityDecodedPreservingTags
                .replacingOccurrences(of: "\u{FEFF}", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = cleaned.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else {
                continue
            }
            recipes.append(contentsOf: findRecipeObjects(in: json).map { recipe in
                JSONLDRecipe(
                    title: recipe["name"] as? String,
                    description: recipe["description"] as? String,
                    imageURL: absoluteURL(from: extractImageString(from: recipe["image"] ?? recipe["thumbnailUrl"]), baseURL: baseURL),
                    ingredients: cleanedLines(extractStringArray(from: recipe["recipeIngredient"] ?? recipe["ingredients"])),
                    instructions: cleanedLines(extractInstructionLines(from: recipe["recipeInstructions"] ?? recipe["instructions"]))
                )
            })
        }
        return recipes
    }

    private static func findRecipeObjects(in object: Any) -> [[String: Any]] {
        if let dict = object as? [String: Any] {
            var found: [[String: Any]] = typeIsRecipe(dict["@type"]) ? [dict] : []
            if let graph = dict["@graph"] {
                found.append(contentsOf: findRecipeObjects(in: graph))
            }
            for value in dict.values {
                found.append(contentsOf: findRecipeObjects(in: value))
            }
            return found
        }
        if let array = object as? [Any] {
            return array.flatMap { findRecipeObjects(in: $0) }
        }
        return []
    }

    private static func typeIsRecipe(_ typeValue: Any?) -> Bool {
        if let type = typeValue as? String {
            return type.lowercased().contains("recipe")
        }
        if let types = typeValue as? [String] {
            return types.contains { $0.lowercased().contains("recipe") }
        }
        return false
    }

    private static func extractImageString(from value: Any?) -> String? {
        if let string = value as? String { return string }
        if let array = value as? [Any] {
            for item in array {
                if let image = extractImageString(from: item) { return image }
            }
        }
        if let dict = value as? [String: Any] {
            return extractImageString(from: dict["url"] ?? dict["contentUrl"])
        }
        return nil
    }

    private static func extractStringArray(from value: Any?) -> [String] {
        if let string = value as? String { return [string] }
        if let array = value as? [Any] {
            return array.flatMap { extractStringArray(from: $0) }
        }
        if let dict = value as? [String: Any] {
            if let text = dict["text"] as? String { return [text] }
            if let name = dict["name"] as? String { return [name] }
        }
        return []
    }

    private static func extractInstructionLines(from value: Any?) -> [String] {
        if let string = value as? String { return [string] }
        if let array = value as? [Any] {
            return array.flatMap { extractInstructionLines(from: $0) }
        }
        guard let dict = value as? [String: Any] else { return [] }

        let typeText = "\(dict["@type"] ?? "")".lowercased()
        if typeText.contains("howtosection") {
            let sectionName = (dict["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let nested = extractInstructionLines(from: dict["itemListElement"] ?? dict["steps"])
            guard let sectionName, !sectionName.isEmpty else { return nested }
            return nested.map { "\(sectionName): \($0)" }
        }
        if let text = dict["text"] as? String, !text.isEmpty {
            return [text]
        }
        if let name = dict["name"] as? String, !name.isEmpty {
            return [name]
        }
        if let nested = dict["itemListElement"] ?? dict["steps"] {
            return extractInstructionLines(from: nested)
        }
        return []
    }

    private static func cleanedLines(_ lines: [String]) -> [String] {
        var seen: Set<String> = []
        return lines
            .flatMap { $0.components(separatedBy: .newlines) }
            .map {
                $0
                    .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
                    .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                    .htmlDecoded
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
            .filter { line in
                guard !seen.contains(line) else { return false }
                seen.insert(line)
                return true
            }
    }

    private static func parseBestImageTagURL(html: String, baseURL: URL) -> URL? {
        var best: (score: Int, url: URL)?
        for tag in matches(pattern: "<img\\b[^>]*>", in: html).prefix(80) {
            let raw = attribute("data-src", in: tag)
                ?? attribute("data-original", in: tag)
                ?? firstURLFromSrcset(attribute("srcset", in: tag))
                ?? attribute("src", in: tag)
            guard let url = absoluteURL(from: raw, baseURL: baseURL) else { continue }
            let combined = (tag + " " + url.absoluteString).lowercased()
            var score = 0
            if combined.contains("recipe") || combined.contains("cook") || combined.contains("food") || combined.contains("dish") { score += 8 }
            if combined.contains("main") || combined.contains("hero") || combined.contains("eyecatch") || combined.contains("thumbnail") { score += 5 }
            if combined.contains(".jpg") || combined.contains(".jpeg") || combined.contains(".png") || combined.contains(".webp") { score += 3 }
            if combined.contains("logo") || combined.contains("icon") || combined.contains("avatar") || combined.contains("sprite") { score -= 10 }
            if best == nil || score > best!.score {
                best = (score, url)
            }
        }
        return best?.url
    }

    private static func firstURL(_ values: [URL?]) -> URL? {
        values.compactMap { $0 }.first
    }

    private static func firstURLFromSrcset(_ srcset: String?) -> String? {
        srcset?
            .split(separator: ",")
            .first?
            .split(separator: " ")
            .first
            .map(String.init)
    }

    private static func absoluteURL(from raw: String?, baseURL: URL) -> URL? {
        guard var raw = raw?.htmlDecoded.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.hasPrefix("//") {
            raw = "https:" + raw
        }
        if let url = URL(string: raw), url.scheme != nil {
            return url
        }
        return URL(string: raw, relativeTo: baseURL)?.absoluteURL
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        return firstCapture(pattern: "\\b\(escaped)\\s*=\\s*['\"]([^'\"]*)['\"]", in: tag)
    }

    private nonisolated static func firstCapture(pattern: String, in text: String) -> String? {
        matches(pattern: pattern, in: text, captureGroup: 1).first
    }

    private nonisolated static func matches(pattern: String, in text: String, captureGroup: Int = 0) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard match.numberOfRanges > captureGroup,
                  let range = Range(match.range(at: captureGroup), in: text) else {
                return nil
            }
            return String(text[range])
        }
    }
}

final class RecipeImportService {
    enum ImportError: LocalizedError {
        case invalidURL
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "URLとして解釈できませんでした。https:// から始まるURLを入力してください。"
            case .emptyResponse:
                return "ページからタイトルや画像を取得できませんでした。"
            }
        }
    }

    func importRecipe(from rawText: String) async throws -> ImportedRecipe {
        let url = try normalizeURL(rawText)
        let host = url.host(percentEncoded: false) ?? ""
        let importer = RecipeImporter()
        let extractor = RecipeTextExtractor()
        let plainTextParser = PlainRecipeTextParser()

        var result = ImportedRecipe(
            title: host.isEmpty ? url.absoluteString : host,
            summary: "",
            sourceURL: url,
            sourceHost: host,
            sourceImageURL: nil,
            imageData: nil,
            ingredientLines: [],
            instructionLines: [],
            extractedRawText: "",
            extractionConfidence: 0.0,
            extractionWarnings: [],
            ingredientSource: "none",
            instructionSource: "none"
        )

        let sourceKind = RecipeSourceKind.detect(urlString: url.absoluteString, host: host)
        let fetched: FetchedRecipeContent
        do {
            switch sourceKind {
            case .instagram:
                fetched = try await importer.fetchInstagram(from: url)
            case .youtube:
                fetched = try await importer.fetchYouTube(from: url)
            case .cookpad:
                fetched = try await importer.fetchCookpad(from: url)
            default:
                fetched = try await importer.fetch(from: url)
            }
        } catch {
            fetched = importer.parseFetchedContent(
                html: "",
                inputURL: url,
                finalURL: nil,
                httpStatusCode: nil,
                contentType: nil,
                importerType: sourceKind.rawValue,
                warnings: ["ページ本文を取得できませんでした（\(error.localizedDescription)）。必要に応じて手動で入力してください。"]
            )
        }

        let parserMode = Self.parserMode(for: fetched)
        let extracted: ExtractedRecipeText
        switch parserMode {
        case "caption":
            extracted = plainTextParser.parse(fetched.extractorInputText, mode: .caption, metadataTitle: fetched.metadata.title)
        case "description":
            extracted = plainTextParser.parse(fetched.extractorInputText, mode: .description, metadataTitle: fetched.metadata.title)
        default:
            let jsonLDRecipesForExtraction = fetched.extractionSource == "jsonLD" ? fetched.jsonLDRecipes : []
            let extractorInput = RecipeTextExtractorInput(
                html: "",
                visibleText: fetched.extractorInputText,
                metadata: fetched.metadata,
                jsonLDRecipes: jsonLDRecipesForExtraction
            )
            extracted = extractor.extract(from: extractorInput)
        }

        if let extractedTitle = extracted.title, result.title == host || result.title.isEmpty {
            result.title = extractedTitle
        }
        if result.summary.isEmpty {
            result.summary = extracted.summary ?? ""
        }
        result.sourceURL = fetched.finalURL ?? result.sourceURL
        result.sourceImageURL = fetched.imageURL
        result.ingredientLines = extracted.ingredients
        result.instructionLines = extracted.instructions
        result.extractedRawText = fetched.visibleText
        result.rawImportedText = fetched.visibleText
        result.rawImportedHTML = fetched.html
        result.importedTextSource = fetched.extractionSource
        result.extractionConfidence = extracted.confidence
        result.extractionWarnings = Self.uniqueWarnings(
            fetched.warnings
            + extracted.warnings
        )
        result.ingredientSource = extracted.ingredientSource
        result.instructionSource = extracted.instructionSource
        result.importDiagnostics = RecipeImportDiagnostics(
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
            draftTitle: result.title,
            draftIngredientsText: result.ingredientLines.joined(separator: "\n"),
            draftInstructionsText: result.instructionLines.joined(separator: "\n"),
            warnings: result.extractionWarnings
        )
        result.importDiagnostics?.log()

        if let imageURL = fetched.imageURL, result.imageData == nil {
            result.imageData = try? await downloadImageData(from: imageURL, referer: url)
        }

        // LinkPresentationはページを再取得するため、HTML解析でタイトルか画像が
        // 取れなかったときだけフォールバックとして使う(取得の二重化を避ける)。
        // hostが空のURLでは初期タイトルがURL文字列になるため、それもフォールバック扱い
        let titleIsFallback = result.title == host
            || result.title == url.absoluteString
            || result.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if result.imageData == nil || titleIsFallback,
           let linkMetadata = try? await fetchLinkPresentationMetadata(for: url) {
            if titleIsFallback,
               let title = linkMetadata.title?.trimmingCharacters(in: .whitespacesAndNewlines),
               !title.isEmpty {
                result.title = title
            }
            if result.imageData == nil {
                if let imageData = await loadImageData(from: linkMetadata.imageProvider) {
                    result.imageData = imageData
                } else if let imageData = await loadImageData(from: linkMetadata.iconProvider) {
                    result.imageData = imageData
                }
            }
        }

        if result.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.title = host.isEmpty ? url.absoluteString : host
        }

        return result
    }

    private static func parserMode(for fetched: FetchedRecipeContent) -> String {
        switch fetched.extractionSource {
        case "instagramCaption":
            return "caption"
        case "youtubeDescription":
            return "description"
        default:
            return "webArticle"
        }
    }

    private func normalizeURL(_ rawText: String) throws -> URL {
        if let url = URLNormalizer.normalizedURL(for: rawText) {
            return url
        }
        throw ImportError.invalidURL
    }

    private static func uniqueWarnings(_ warnings: [String]) -> [String] {
        var seen: Set<String> = []
        return warnings.filter { warning in
            let trimmed = warning.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { return false }
            seen.insert(trimmed)
            return true
        }
    }

    private func fetchLinkPresentationMetadata(for url: URL) async throws -> LPLinkMetadata {
        try await withCheckedThrowingContinuation { continuation in
            let provider = LPMetadataProvider()
            provider.timeout = 8
            let resumeBox = ContinuationResumeBox<LPLinkMetadata>()

            DispatchQueue.main.asyncAfter(deadline: .now() + 9) {
                provider.cancel()
                resumeBox.resume(continuation, with: .failure(ImportError.emptyResponse))
            }

            provider.startFetchingMetadata(for: url) { metadata, error in
                if let metadata {
                    resumeBox.resume(continuation, with: .success(metadata))
                } else if let error {
                    resumeBox.resume(continuation, with: .failure(error))
                } else {
                    resumeBox.resume(continuation, with: .failure(ImportError.emptyResponse))
                }
            }
        }
    }

    private func loadImageData(from provider: NSItemProvider?) async -> Data? {
        guard let provider else { return nil }

        if provider.canLoadObject(ofClass: UIImage.self) {
            if let image = try? await provider.loadUIImage(), let data = image.jpegData(compressionQuality: 0.9) {
                return data
            }
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            return try? await provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier)
        }

        return nil
    }

    private func downloadImageData(from imageURL: URL, referer: URL) async throws -> Data {
        var request = URLRequest(url: imageURL)
        request.timeoutInterval = 20
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue("image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<400).contains(http.statusCode) {
            throw ImportError.emptyResponse
        }
        return data
    }
}

private final class ContinuationResumeBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func resume(
        _ continuation: CheckedContinuation<Value, Error>,
        with result: Result<Value, Error>
    ) {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return }
        didResume = true

        switch result {
        case .success(let value):
            continuation.resume(returning: value)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

}

private extension NSItemProvider {
    func loadUIImage() async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            _ = loadObject(ofClass: UIImage.self) { object, error in
                if let image = object as? UIImage {
                    continuation.resume(returning: image)
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(throwing: RecipeImportService.ImportError.emptyResponse)
                }
            }
        }
    }

    func loadDataRepresentation(forTypeIdentifier typeIdentifier: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let data {
                    continuation.resume(returning: data)
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(throwing: RecipeImportService.ImportError.emptyResponse)
                }
            }
        }
    }
}

private extension String {
    nonisolated var htmlEntityDecodedPreservingTags: String {
        var result = self
        let named = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'"
        ]
        for (source, destination) in named {
            result = result.replacingOccurrences(of: source, with: destination)
        }
        return result
    }

    // NSAttributedStringのHTMLインポータはWebKitベースでメインスレッド必須かつ低速なため、
    // 数値文字参照と主要な名前付きエンティティのみを1パスで展開する
    // (1パス処理なので「&amp;amp;」が二重展開されることはない)
    nonisolated var htmlDecoded: String {
        guard contains("&") else { return self }
        guard let regex = Self.htmlEntityRegex else { return self }
        let nsRange = NSRange(startIndex..<endIndex, in: self)
        var result = self
        for match in regex.matches(in: self, range: nsRange).reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let bodyRange = Range(match.range(at: 1), in: self),
                  let decoded = Self.decodedHTMLEntity(String(self[bodyRange])) else {
                continue
            }
            result.replaceSubrange(fullRange, with: decoded)
        }
        return result
    }

    private nonisolated static func decodedHTMLEntity(_ body: String) -> String? {
        if body.hasPrefix("#x") || body.hasPrefix("#X") {
            return UInt32(body.dropFirst(2), radix: 16).flatMap(UnicodeScalar.init).map(String.init)
        }
        if body.hasPrefix("#") {
            return UInt32(body.dropFirst()).flatMap(UnicodeScalar.init).map(String.init)
        }
        return namedHTMLEntities[body.lowercased()]
    }

    // メタタグごとに呼ばれるため、コンパイル済み正規表現を使い回す
    private nonisolated static let htmlEntityRegex = try? NSRegularExpression(
        pattern: "&(#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6}|[a-zA-Z][a-zA-Z0-9]{1,30});"
    )

    private nonisolated static let namedHTMLEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": " ", "copy": "©", "reg": "®", "trade": "™",
        "hellip": "…", "mdash": "—", "ndash": "–", "middot": "·", "bull": "•",
        "lsquo": "\u{2018}", "rsquo": "\u{2019}", "ldquo": "\u{201C}", "rdquo": "\u{201D}",
        "laquo": "«", "raquo": "»", "deg": "°", "times": "×", "divide": "÷",
        "frac12": "½", "frac14": "¼", "frac34": "¾",
        "euro": "€", "pound": "£", "yen": "¥", "cent": "¢",
        "sect": "§", "para": "¶", "plusmn": "±"
    ]
}
