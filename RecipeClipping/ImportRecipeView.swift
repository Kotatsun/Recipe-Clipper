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
            Form {
                Section("URL") {
                    TextField("https://example.com/recipe", text: $urlText, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()

                    Button {
                        Task { await fetch() }
                    } label: {
                        HStack {
                            if isLoading { ProgressView() }
                            Text(isLoading ? "取得中" : "写真・材料・手順を取得")
                        }
                    }
                    .disabled(isLoading || urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section("本文貼り付け") {
                    TextField("Instagram本文やページ本文を貼り付け", text: $pastedBodyText, axis: .vertical)
                        .lineLimit(3...10)
                    Button {
                        analyzePastedBody()
                    } label: {
                        Label("本文を解析", systemImage: "text.magnifyingglass")
                    }
                    .disabled(pastedBodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                if let draft {
                    Section("プレビュー") {
                        if let imageData = draft.imageData, let uiImage = UIImage(data: imageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 240)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .listRowInsets(EdgeInsets())
                        } else {
                            ContentUnavailableView("画像なし", systemImage: "photo.badge.exclamationmark")
                        }

                        if let imageURL = draft.sourceImageURL {
                            LabeledContent("画像URL", value: imageURL.absoluteString)
                        }
                    }

                    Section("保存前編集") {
                        TextField("タイトル", text: manualBinding($title, edited: $isTitleManuallyEdited))
                        TextField("概要", text: manualBinding($summary, edited: $isSummaryManuallyEdited), axis: .vertical)
                            .lineLimit(2...6)
                        if draft.ingredientLines.isEmpty || draft.instructionLines.isEmpty {
                            Text("材料・作り方を自動抽出できませんでした。ページ本文を取得できなかったか、レシピ情報が画像内にある可能性があります。必要に応じて手動で入力してください。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !draft.extractionWarnings.isEmpty {
                            DisclosureGroup("抽出メモ") {
                                ForEach(draft.extractionWarnings, id: \.self) { warning in
                                    Label(warning, systemImage: "exclamationmark.triangle")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Section("タグ") {
                        TagEditorView(tagsText: $tagsText, suggestions: frequentTags)
                    }

                    Section("自分用メモ") {
                        TextField("次回調整など", text: manualBinding($notes, edited: $isNoteManuallyEdited), axis: .vertical)
                            .lineLimit(3...8)
                    }

                    Section("材料") {
                        TextEditor(text: manualBinding($ingredientLinesText, edited: $areIngredientsManuallyEdited))
                            .frame(minHeight: 110)
                    }

                    Section("手順") {
                        TextEditor(text: manualBinding($instructionLinesText, edited: $areInstructionsManuallyEdited))
                            .frame(minHeight: 150)
                    }

                    Section {
                        DisclosureGroup("取得した元本文") {
                            if rawImportedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("本文を取得できていません")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                TextEditor(text: manualBinding($rawImportedText, edited: $isRawImportedTextManuallyEdited))
                                    .frame(minHeight: 220)
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
                    }

                    if let diagnostics = draft.importDiagnostics {
                        Section("Import Debug") {
                            DisclosureGroup("取得・抽出ログ") {
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
                        }
                    }
                }
            }
            .navigationTitle("URLから追加")
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
                        .disabled(draft == nil || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
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
