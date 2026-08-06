import SwiftUI
import SwiftData
import UIKit

struct ImportRecipeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var recipes: [Recipe]

    @State private var urlText: String
    @State private var tagsText = ""
    @State private var notes = ""
    @State private var title = ""
    @State private var summary = ""
    @State private var ingredientLinesText = ""
    @State private var instructionLinesText = ""
    @State private var rawImportedText = ""
    @State private var rawImportedHTML = ""
    @State private var importedTextSource = "none"
    @State private var pastedBodyText = ""
    @State private var draft: ImportedRecipe?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var duplicateRecipe: Recipe?
    @State private var recipeToOpen: Recipe?
    @State private var isApplyingDraft = false
    @State private var isTitleManuallyEdited = false
    @State private var areIngredientsManuallyEdited = false
    @State private var areInstructionsManuallyEdited = false
    @State private var isSummaryManuallyEdited = false
    @State private var isNoteManuallyEdited = false
    @State private var isRawImportedTextManuallyEdited = false
    @State private var hasAutoFetchedInitialURL = false
    @FocusState private var isURLFieldFocused: Bool

    private let service = RecipeImportService()
    private let textExtractor = RecipeTextExtractor()
    private let plainTextParser = PlainRecipeTextParser()
    private let initialURLText: String?

    init(initialURLText: String? = nil) {
        self.initialURLText = initialURLText
        _urlText = State(initialValue: initialURLText ?? "")
    }

    private var frequentTags: [String] {
        let counts = Dictionary(grouping: recipes.flatMap(\.tags), by: { $0 })
            .mapValues(\.count)
        return counts.sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
        }
        .map(\.key)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    urlImportCard

                    if let errorMessage {
                        errorCard(errorMessage)
                    }

                    if let draft {
                        importedPreviewCard(draft)
                        recipeBasicsCard(draft)
                        recipeTextCard(
                            title: "材料",
                            systemImage: "carrot.fill",
                            tint: RecipePalette.basil,
                            text: manualBinding($ingredientLinesText, edited: $areIngredientsManuallyEdited),
                            minimumHeight: 145,
                            placeholder: "材料を自由に入力"
                        )
                        recipeTextCard(
                            title: "作り方",
                            systemImage: "list.number",
                            tint: RecipePalette.tomato,
                            text: manualBinding($instructionLinesText, edited: $areInstructionsManuallyEdited),
                            minimumHeight: 190,
                            placeholder: "作り方を自由に入力"
                        )
                        finishingCard
                    } else if !isLoading {
                        importGuideCard
                    }

                    pastedTextFallbackCard

                    if let draft {
                        sourceTextCard
                        if let diagnostics = draft.importDiagnostics {
                            diagnosticsCard(diagnostics)
                        }
                        saveButton
                    }
                }
                .padding(16)
                .padding(.bottom, 36)
            }
            .background(
                LinearGradient(
                    colors: [Color.indigo.opacity(0.09), Color(.systemGroupedBackground), RecipePalette.ember.opacity(0.06)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationTitle("URLから取り込む")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $recipeToOpen) { recipe in
                RecipeDetailView(recipe: recipe)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(draft == nil || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task {
                guard !hasAutoFetchedInitialURL,
                      initialURLText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                    return
                }
                hasAutoFetchedInitialURL = true
                await fetch()
            }
            .alert("同じURLのレシピがあります", isPresented: Binding(
                get: { duplicateRecipe != nil },
                set: { if !$0 { duplicateRecipe = nil } }
            ), presenting: duplicateRecipe) { recipe in
                Button("既存を開く") {
                    recipeToOpen = recipe
                    duplicateRecipe = nil
                }
                Button("別レシピとして保存") {
                    duplicateRecipe = nil
                    save(allowDuplicate: true)
                }
                Button("キャンセル", role: .cancel) {
                    duplicateRecipe = nil
                }
            } message: { recipe in
                Text("「\(recipe.title)」が既に保存されています。")
            }
        }
    }

    private var urlImportCard: some View {
        importCard {
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 12) {
                    Image(systemName: "link")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(
                            LinearGradient(colors: [.indigo, .blue], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                        )
                    VStack(alignment: .leading, spacing: 3) {
                        Text("リンクを貼るだけ")
                            .font(.headline)
                        Text("写真・材料・手順をまとめて取得します")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(alignment: .center, spacing: 8) {
                    TextField("https://example.com/recipe", text: $urlText, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .focused($isURLFieldFocused)
                        .lineLimit(1...3)
                        .submitLabel(.go)
                        .onSubmit { Task { await fetch() } }

                    Button {
                        if let pasted = UIPasteboard.general.string,
                           !pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            urlText = pasted
                        }
                        isURLFieldFocused = false
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                            .font(.body.weight(.semibold))
                            .frame(width: 36, height: 36)
                            .background(Color.indigo.opacity(0.12), in: Circle())
                    }
                    .accessibilityLabel("クリップボードから貼り付け")
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))

                Button {
                    isURLFieldFocused = false
                    Task { await fetch() }
                } label: {
                    HStack(spacing: 9) {
                        if isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(isLoading ? "レシピを読み込み中…" : draft == nil ? "レシピを取り込む" : "このURLから再取得")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .foregroundStyle(.white)
                    .background(
                        LinearGradient(colors: [.indigo, .blue], startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 15)
                    )
                }
                .disabled(isLoading || urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(isLoading || urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.58 : 1)

                if isLoading {
                    HStack(spacing: 14) {
                        importProgressLabel("ページ", isActive: true)
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        importProgressLabel("レシピ解析", isActive: true)
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        importProgressLabel("写真", isActive: true)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func importProgressLabel(_ title: String, isActive: Bool) -> some View {
        VStack(spacing: 4) {
            Circle()
                .fill(isActive ? Color.indigo : Color.secondary.opacity(0.2))
                .frame(width: 7, height: 7)
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("うまく取得できませんでした")
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(15)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(Color.orange.opacity(0.22)) }
    }

    private func importedPreviewCard(_ draft: ImportedRecipe) -> some View {
        importCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Label("取り込み完了", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(RecipePalette.basil)
                    Spacer()
                    Text(draft.sourceHost)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let imageData = draft.imageData, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "photo.badge.exclamationmark")
                        Text("代表画像は見つかりませんでした")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    private func recipeBasicsCard(_ draft: ImportedRecipe) -> some View {
        importCard {
            VStack(alignment: .leading, spacing: 14) {
                importCardHeading("保存前に確認", systemImage: "pencil.line", tint: RecipePalette.ember)
                VStack(alignment: .leading, spacing: 6) {
                    Text("レシピ名").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    TextField("タイトル", text: manualBinding($title, edited: $isTitleManuallyEdited))
                        .font(.title3.weight(.semibold))
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("ひとこと").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    TextField("概要", text: manualBinding($summary, edited: $isSummaryManuallyEdited), axis: .vertical)
                        .lineLimit(2...6)
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }

                if draft.ingredientLines.isEmpty || draft.instructionLines.isEmpty {
                    Label(
                        "一部を自動抽出できませんでした。空欄へ直接入力できます。画像内に書かれたレシピは「画像から読み取る」もお試しください。",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if !draft.extractionWarnings.isEmpty {
                    DisclosureGroup("抽出結果のメモ") {
                        ForEach(draft.extractionWarnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 3)
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
        }
    }

    private func recipeTextCard(
        title: String,
        systemImage: String,
        tint: Color,
        text: Binding<String>,
        minimumHeight: CGFloat,
        placeholder: String
    ) -> some View {
        importCard {
            VStack(alignment: .leading, spacing: 10) {
                importCardHeading(title, systemImage: systemImage, tint: tint)
                Text("入力中は自由に改行・挿入できます。表示時に改行ごとに分かれます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ZStack(alignment: .topLeading) {
                    if text.wrappedValue.isEmpty {
                        Text(placeholder)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: text)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: minimumHeight)
                }
                .padding(8)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var finishingCard: some View {
        importCard {
            VStack(alignment: .leading, spacing: 16) {
                importCardHeading("仕上げ", systemImage: "tag.fill", tint: .indigo)
                TagEditorView(tagsText: $tagsText, suggestions: frequentTags)
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("自分用メモ").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    TextField("次回の調整など", text: manualBinding($notes, edited: $isNoteManuallyEdited), axis: .vertical)
                        .lineLimit(3...8)
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var importGuideCard: some View {
        importCard {
            VStack(alignment: .leading, spacing: 13) {
                importCardHeading("取り込めるもの", systemImage: "wand.and.stars", tint: RecipePalette.ember)
                HStack(spacing: 8) {
                    importSourceChip("Web", icon: "safari")
                    importSourceChip("Instagram", icon: "camera")
                    importSourceChip("YouTube", icon: "play.rectangle")
                }
                Text("リンク先を解析したあと、内容を自由に直してから保存できます。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func importSourceChip(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.indigo.opacity(0.09), in: Capsule())
    }

    private var pastedTextFallbackCard: some View {
        importCard {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Instagramの本文やページのレシピ部分を貼り付けると、材料と手順を抽出できます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("本文をここへ貼り付け", text: $pastedBodyText, axis: .vertical)
                        .lineLimit(4...12)
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    Button {
                        analyzePastedBody()
                    } label: {
                        Label("貼り付けた本文を解析", systemImage: "text.magnifyingglass")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .disabled(pastedBodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.top, 10)
            } label: {
                Label("URLからうまく取れないとき", systemImage: "lifepreserver")
                    .font(.headline)
            }
        }
    }

    private var sourceTextCard: some View {
        importCard {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 12) {
                    if rawImportedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("本文を取得できていません")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        TextEditor(text: manualBinding($rawImportedText, edited: $isRawImportedTextManuallyEdited))
                            .font(.caption.monospaced())
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 220)
                            .padding(8)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                    Button {
                        reextractFromRawImportedText()
                    } label: {
                        Label("元本文から再抽出", systemImage: "text.magnifyingglass")
                    }
                    .disabled(rawImportedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button {
                        UIPasteboard.general.string = rawImportedText
                    } label: {
                        Label("本文をコピー（テストケース用）", systemImage: "doc.on.doc")
                    }
                    .disabled(rawImportedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button {
                        UIPasteboard.general.string = rawImportedHTML
                    } label: {
                        Label("取得HTMLをコピー（テストケース用）", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    .disabled(rawImportedHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.top, 10)
            } label: {
                Label("取得した元本文", systemImage: "doc.text.magnifyingglass")
                    .font(.headline)
            }
        }
    }

    private func diagnosticsCard(_ diagnostics: RecipeImportDiagnostics) -> some View {
        importCard {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 4) {
                    debugField("inputURL", diagnostics.inputURL)
                    debugField("finalURL", diagnostics.finalURL ?? "")
                    debugField("importerType", diagnostics.importerType)
                    debugField("rawHtmlLength", "\(diagnostics.rawHtmlLength)")
                    debugField("rawImportedTextLength", "\(diagnostics.rawImportedTextLength)")
                    debugField("recipeCandidateTextLength", "\(diagnostics.recipeCandidateTextLength)")
                    debugField("extractorInputTextLength", "\(diagnostics.extractorInputTextLength)")
                    debugField("reparseInputTextLength", "\(diagnostics.reparseInputTextLength)")
                    debugField("reparseInputTextHash", diagnostics.reparseInputTextHash)
                    debugField("parserMode", diagnostics.parserMode)
                    debugField("extractionSource", diagnostics.extractionSource)
                    debugField("rawImportedText先頭5000文字", diagnostics.rawImportedTextPreview)
                    debugField("recipeCandidateText先頭5000文字", diagnostics.recipeCandidateTextPreview)
                    debugField("extractorInputText先頭5000文字", diagnostics.extractorInputTextPreview)
                    debugField("reparseInputTextPreview", diagnostics.reparseInputTextPreview)
                    debugField("normalizedReparseInputPreview", diagnostics.normalizedReparseInputPreview)
                    debugField("jsonLDRecipeCount", "\(diagnostics.jsonLDRecipeCount)")
                    debugField("metadataTitle", diagnostics.metadataTitle ?? "")
                    debugField("ogTitle", diagnostics.ogTitle ?? "")
                    debugField("extractedTitle", diagnostics.extractedTitle ?? "")
                    debugField("extractedIngredients", diagnostics.extractedIngredients.joined(separator: "\n"))
                    debugField("extractedInstructions", diagnostics.extractedInstructions.joined(separator: "\n"))
                    debugField("draft.title", diagnostics.draftTitle)
                    debugField("draft.ingredientsText", diagnostics.draftIngredientsText)
                    debugField("draft.instructionsText", diagnostics.draftInstructionsText)
                    debugField("warnings", diagnostics.warnings.joined(separator: "\n"))
                }
                .padding(.top, 10)
            } label: {
                Label("取得・抽出ログ", systemImage: "ladybug")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var saveButton: some View {
        Button {
            save()
        } label: {
            Label("この内容でレシピを保存", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.white)
                .background(
                    LinearGradient(colors: [RecipePalette.tomato, RecipePalette.ember], startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 17)
                )
        }
        .buttonStyle(.plain)
        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .opacity(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.55 : 1)
    }

    private func importCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.045), radius: 12, y: 6)
    }

    private func importCardHeading(_ title: String, systemImage: String, tint: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(tint)
    }

    @MainActor
    private func fetch() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let imported = try await service.importRecipe(from: urlText)
            apply(imported, overwriteExistingFields: draft == nil)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func analyzePastedBody() {
        let reparseInputText = pastedBodyText
        let parserMode = parserModeForPlainTextInput()
        let extracted = plainTextParser.parse(
            reparseInputText,
            mode: plainParserMode(from: parserMode),
            metadataTitle: title
        )
        let sourceURL = URLNormalizer.normalizedURL(for: urlText)
            ?? URL(string: "recipeclipper://manual/\(UUID().uuidString)")!
        let host = sourceURL.host(percentEncoded: false) ?? ""
        var imported = ImportedRecipe(
            title: extracted.title ?? title,
            summary: extracted.summary ?? summary,
            sourceURL: sourceURL,
            sourceHost: host,
            sourceImageURL: draft?.sourceImageURL,
            imageData: draft?.imageData,
            ingredientLines: extracted.ingredients,
            instructionLines: extracted.instructions,
            extractedRawText: pastedBodyText,
            rawImportedText: pastedBodyText,
            rawImportedHTML: draft?.rawImportedHTML ?? "",
            importedTextSource: "manual",
            extractionConfidence: extracted.confidence,
            extractionWarnings: extracted.warnings,
            ingredientSource: extracted.ingredientSource,
            instructionSource: extracted.instructionSource
        )
        imported.importDiagnostics = diagnosticsForPlainTextParse(
            sourceURL: sourceURL,
            parserMode: parserMode,
            reparseInputText: reparseInputText,
            extracted: extracted,
            imported: imported
        )
        apply(imported, overwriteExistingFields: false)
    }

    private func apply(_ imported: ImportedRecipe, overwriteExistingFields: Bool) {
        var imported = imported
        if imported.importDiagnostics == nil, var diagnostics = draft?.importDiagnostics {
            let rawText = imported.rawImportedText.isEmpty ? imported.extractedRawText : imported.rawImportedText
            diagnostics.rawImportedTextLength = rawText.count
            diagnostics.rawImportedTextPreview = String(rawText.prefix(5000))
            diagnostics.reparseInputTextLength = rawText.count
            diagnostics.reparseInputTextPreview = String(rawText.prefix(5000))
            diagnostics.reparseInputTextHash = PlainRecipeTextParser.stableHash(rawText)
            diagnostics.normalizedReparseInputPreview = String(PlainRecipeTextParser.normalizedText(rawText).prefix(5000))
            diagnostics.extractedTitle = imported.title
            diagnostics.extractedIngredients = imported.ingredientLines
            diagnostics.extractedInstructions = imported.instructionLines
            diagnostics.draftTitle = imported.title
            diagnostics.draftIngredientsText = imported.ingredientLines.joined(separator: "\n")
            diagnostics.draftInstructionsText = imported.instructionLines.joined(separator: "\n")
            diagnostics.warnings = imported.extractionWarnings
            imported.importDiagnostics = diagnostics
        }
        draft = imported
        isApplyingDraft = true
        defer { isApplyingDraft = false }

        if shouldApplyField(currentValue: title, overwriteExistingFields: overwriteExistingFields, wasManuallyEdited: isTitleManuallyEdited) {
            title = imported.title
        }
        if shouldApplyField(currentValue: summary, overwriteExistingFields: overwriteExistingFields, wasManuallyEdited: isSummaryManuallyEdited) {
            summary = imported.summary
        }
        if shouldApplyField(currentValue: ingredientLinesText, overwriteExistingFields: overwriteExistingFields, wasManuallyEdited: areIngredientsManuallyEdited) {
            ingredientLinesText = imported.ingredientLines.joined(separator: "\n")
        }
        if shouldApplyField(currentValue: instructionLinesText, overwriteExistingFields: overwriteExistingFields, wasManuallyEdited: areInstructionsManuallyEdited) {
            instructionLinesText = imported.instructionLines.joined(separator: "\n")
        }
        if shouldApplyField(currentValue: rawImportedText, overwriteExistingFields: overwriteExistingFields, wasManuallyEdited: isRawImportedTextManuallyEdited) {
            rawImportedText = imported.rawImportedText.isEmpty ? imported.extractedRawText : imported.rawImportedText
        }
        if overwriteExistingFields || rawImportedHTML.isEmpty {
            rawImportedHTML = imported.rawImportedHTML
        }
        if overwriteExistingFields || importedTextSource == "none" {
            importedTextSource = imported.importedTextSource
        }
    }

    private func reextractFromRawImportedText() {
        let reparseInputText = rawImportedText
        let parserMode = parserModeForCurrentReparse()
        let extracted: ExtractedRecipeText
        if parserMode == "webArticle" {
            extracted = textExtractor.extract(from: reparseInputText, metadataTitle: title)
        } else {
            extracted = plainTextParser.parse(
                reparseInputText,
                mode: plainParserMode(from: parserMode),
                metadataTitle: title
            )
        }
        let sourceURL = draft?.sourceURL
            ?? URLNormalizer.normalizedURL(for: urlText)
            ?? URL(string: "recipeclipper://manual/\(UUID().uuidString)")!
        let host = sourceURL.host(percentEncoded: false) ?? draft?.sourceHost ?? ""
        var imported = ImportedRecipe(
            title: extracted.title ?? title,
            summary: extracted.summary ?? summary,
            sourceURL: sourceURL,
            sourceHost: host,
            sourceImageURL: draft?.sourceImageURL,
            imageData: draft?.imageData,
            ingredientLines: extracted.ingredients,
            instructionLines: extracted.instructions,
            extractedRawText: rawImportedText,
            rawImportedText: rawImportedText,
            rawImportedHTML: rawImportedHTML,
            importedTextSource: importedTextSource == "none" ? "manual" : importedTextSource,
            extractionConfidence: extracted.confidence,
            extractionWarnings: extracted.warnings,
            ingredientSource: extracted.ingredientSource,
            instructionSource: extracted.instructionSource
        )
        imported.importDiagnostics = diagnosticsForPlainTextParse(
            sourceURL: sourceURL,
            parserMode: parserMode,
            reparseInputText: reparseInputText,
            extracted: extracted,
            imported: imported
        )
        apply(imported, overwriteExistingFields: false)
    }

    private func parserModeForPlainTextInput() -> String {
        let sourceKind = URLNormalizer.normalizedURL(for: urlText)
            .map { RecipeSourceKind.detect(urlString: $0.absoluteString, host: $0.host(percentEncoded: false) ?? "") }
        switch sourceKind {
        case .some(.instagram):
            return "caption"
        case .some(.youtube):
            return "description"
        default:
            return "plainText"
        }
    }

    private func parserModeForCurrentReparse() -> String {
        if let mode = draft?.importDiagnostics?.parserMode,
           ["caption", "description", "plainText", "webArticle"].contains(mode) {
            return mode
        }
        switch importedTextSource {
        case "instagramCaption":
            return "caption"
        case "youtubeDescription":
            return "description"
        case "manual":
            return "plainText"
        default:
            return parserModeForPlainTextInput()
        }
    }

    private func plainParserMode(from parserMode: String) -> PlainRecipeTextParser.Mode {
        switch parserMode {
        case "caption":
            return .caption
        case "description":
            return .description
        default:
            return .plainText
        }
    }

    private func diagnosticsForPlainTextParse(
        sourceURL: URL,
        parserMode: String,
        reparseInputText: String,
        extracted: ExtractedRecipeText,
        imported: ImportedRecipe
    ) -> RecipeImportDiagnostics {
        let normalized = PlainRecipeTextParser.normalizedText(reparseInputText)
        let existing = draft?.importDiagnostics
        return RecipeImportDiagnostics(
            inputURL: existing?.inputURL ?? sourceURL.absoluteString,
            finalURL: existing?.finalURL,
            importerType: existing?.importerType ?? RecipeSourceKind.detect(
                urlString: sourceURL.absoluteString,
                host: sourceURL.host(percentEncoded: false) ?? ""
            ).rawValue,
            httpStatusCode: existing?.httpStatusCode,
            contentType: existing?.contentType,
            rawHtmlLength: existing?.rawHtmlLength ?? rawImportedHTML.count,
            rawImportedTextLength: reparseInputText.count,
            recipeCandidateTextLength: reparseInputText.count,
            extractorInputTextLength: reparseInputText.count,
            extractionSource: imported.importedTextSource,
            rawImportedTextPreview: String(reparseInputText.prefix(5000)),
            recipeCandidateTextPreview: String(reparseInputText.prefix(5000)),
            extractorInputTextPreview: String(reparseInputText.prefix(5000)),
            reparseInputTextLength: reparseInputText.count,
            reparseInputTextPreview: String(reparseInputText.prefix(5000)),
            reparseInputTextHash: PlainRecipeTextParser.stableHash(reparseInputText),
            normalizedReparseInputPreview: String(normalized.prefix(5000)),
            parserMode: parserMode,
            metadataTitle: existing?.metadataTitle,
            ogTitle: existing?.ogTitle,
            hasJSONLD: existing?.hasJSONLD ?? false,
            jsonLDRecipeCount: existing?.jsonLDRecipeCount ?? 0,
            extractedTitle: extracted.title,
            extractedIngredients: extracted.ingredients,
            extractedInstructions: extracted.instructions,
            draftTitle: imported.title,
            draftIngredientsText: imported.ingredientLines.joined(separator: "\n"),
            draftInstructionsText: imported.instructionLines.joined(separator: "\n"),
            warnings: imported.extractionWarnings
        )
    }

    private func shouldApplyField(currentValue: String, overwriteExistingFields: Bool, wasManuallyEdited: Bool) -> Bool {
        !wasManuallyEdited && (overwriteExistingFields || currentValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func manualBinding(_ value: Binding<String>, edited: Binding<Bool>) -> Binding<String> {
        Binding(
            get: { value.wrappedValue },
            set: { newValue in
                value.wrappedValue = newValue
                if !isApplyingDraft {
                    edited.wrappedValue = true
                }
            }
        )
    }

    @ViewBuilder
    private func debugField(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "空" : value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
    }

    private func save(allowDuplicate: Bool = false) {
        guard let draft else { return }

        let normalizedURL = URLNormalizer.normalizedString(for: draft.sourceURL.absoluteString)
        if !allowDuplicate, let existing = recipes.first(where: { recipe in
            let existingNormalized = recipe.normalizedSourceURLString.isEmpty
                ? URLNormalizer.normalizedString(for: recipe.sourceURLString)
                : recipe.normalizedSourceURLString
            return existingNormalized == normalizedURL
        }) {
            duplicateRecipe = existing
            return
        }

        var imageFileName: String?
        if let data = draft.imageData {
            imageFileName = try? ImageStore.save(data: data)
        }

        let host = draft.sourceURL.host(percentEncoded: false) ?? draft.sourceHost
        let recipe = Recipe(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceURLString: draft.sourceURL.absoluteString,
            sourceHost: host,
            sourceImageURLString: draft.sourceImageURL?.absoluteString,
            localImageFileName: imageFileName,
            notes: notes,
            tagsText: tagsText,
            ingredientLinesText: ingredientLinesText,
            instructionLinesText: instructionLinesText,
            normalizedSourceURLString: normalizedURL,
            sourceKindRaw: RecipeSourceKind.detect(urlString: draft.sourceURL.absoluteString, host: host).rawValue,
            extractedRawText: draft.extractedRawText,
            rawImportedText: rawImportedText,
            rawImportedHTML: rawImportedHTML,
            importedTextSource: importedTextSource,
            extractionConfidence: draft.extractionConfidence,
            extractionWarningsText: Recipe.text(from: draft.extractionWarnings),
            ingredientSource: draft.ingredientSource,
            instructionSource: draft.instructionSource
        )
        recipe.refreshDerivedFields()
        modelContext.insert(recipe)
        try? modelContext.save()
        dismiss()
    }
}
