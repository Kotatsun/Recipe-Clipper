import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct AddRecipeView: View {
    @Environment(\.dismiss) private var dismiss
    let onChooseURL: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("新しいレシピ")
                            .font(.system(size: 32, weight: .bold, design: .serif))
                        Text("いちばん近い追加方法を選んでください")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 4)

                    NavigationLink {
                        RecipeComposerView(mode: .original) {
                            dismiss()
                        }
                    } label: {
                        AddRecipeMethodCard(
                            title: "自分でレシピを書く",
                            subtitle: "材料と手順を少しずつ。写真もきれいに登録できます",
                            systemImage: "pencil.and.scribble",
                            colors: [RecipePalette.tomato, RecipePalette.ember]
                        )
                    }

                    NavigationLink {
                        RecipeComposerView(mode: .images) {
                            dismiss()
                        }
                    } label: {
                        AddRecipeMethodCard(
                            title: "画像から読み取る",
                            subtitle: "スクリーンショットを複数選択して、材料・手順を自動入力",
                            systemImage: "text.viewfinder",
                            colors: [RecipePalette.basil, RecipePalette.leafLight]
                        )
                    }

                    Button {
                        onChooseURL()
                    } label: {
                        AddRecipeMethodCard(
                            title: "URLから取り込む",
                            subtitle: "Webページ、Instagram、YouTubeのレシピに",
                            systemImage: "link",
                            colors: [.indigo, .blue]
                        )
                    }
                    .buttonStyle(.plain)

                    Label("画像の文字認識は端末内で行われ、画像は外部へ送信されません。", systemImage: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                }
                .padding(20)
            }
            .background(
                LinearGradient(
                    colors: [RecipePalette.cream.opacity(0.7), Color(.systemBackground)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}

private struct AddRecipeMethodCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let colors: [Color]

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(
                    LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .shadow(color: colors[0].opacity(0.25), radius: 9, y: 5)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 18, y: 8)
    }
}

private enum RecipeComposerMode {
    case original
    case images

    var title: String {
        switch self {
        case .original: "自分のレシピ"
        case .images: "画像からレシピ"
        }
    }
}

private struct SelectedRecipeImage: Identifiable {
    let id = UUID()
    let data: Data
    let image: UIImage
}

private struct RecipeComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var recipes: [Recipe]

    let mode: RecipeComposerMode
    let onSaved: () -> Void

    @State private var title = ""
    @State private var summary = ""
    @State private var ingredientsText = ""
    @State private var instructionsText = ""
    @State private var tagsText = ""
    @State private var notes = ""
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var selectedImages: [SelectedRecipeImage] = []
    @State private var coverImageID: UUID?
    @State private var recognizedText = ""
    @State private var extractionResult: ExtractedRecipeText?
    @State private var isLoadingImages = false
    @State private var isRecognizing = false
    @State private var recognitionProgress = 0
    @State private var errorMessage: String?

    private let recognizer = RecipeImageTextRecognizer()
    private let parser = PlainRecipeTextParser()

    private var frequentTags: [String] {
        let counts = Dictionary(grouping: recipes.flatMap(\.tags), by: { $0 }).mapValues(\.count)
        return counts.sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
        }.map(\.key)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoadingImages && !isRecognizing
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if mode == .images {
                    imageImportCard
                } else {
                    coverPhotoCard
                }
                basicsCard
                recipeTextCard(
                    title: "材料",
                    systemImage: "carrot.fill",
                    tint: RecipePalette.basil,
                    text: $ingredientsText,
                    minimumHeight: 145,
                    placeholder: "例：\n玉ねぎ 1/2個\n鶏もも肉 300g"
                )
                recipeTextCard(
                    title: "作り方",
                    systemImage: "list.number",
                    tint: RecipePalette.tomato,
                    text: $instructionsText,
                    minimumHeight: 190,
                    placeholder: "作り方を自由に入力してください。\n表示するときは改行ごとに手順へ分かれます。"
                )
                detailsCard

                if mode == .images, !recognizedText.isEmpty {
                    recognizedTextCard
                }
            }
            .padding(16)
            .padding(.bottom, 40)
        }
        .background(
            LinearGradient(
                colors: [RecipePalette.tomato.opacity(0.07), Color(.systemGroupedBackground), RecipePalette.basil.opacity(0.06)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle(mode.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("戻る") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save)
                    .fontWeight(.semibold)
                    .disabled(!canSave)
            }
        }
        .alert("処理できませんでした", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var imageImportCard: some View {
        composerCard {
            VStack(alignment: .leading, spacing: 14) {
                cardHeading("スクリーンショット", systemImage: "text.viewfinder", tint: RecipePalette.basil)
                Text("材料と手順が別々の画像でも大丈夫。読みたい順に最大10枚選べます。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: 10,
                    selectionBehavior: .ordered,
                    matching: .images
                ) {
                    Label(selectedImages.isEmpty ? "画像を選ぶ" : "画像を選び直す", systemImage: "photo.stack")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white)
                        .background(RecipePalette.basil.gradient, in: RoundedRectangle(cornerRadius: 14))
                }
                .onChange(of: selectedPhotoItems) { _, items in
                    Task { await loadAndRecognize(items) }
                }

                if !selectedImages.isEmpty {
                    selectedImagesStrip
                }

                if isLoadingImages || isRecognizing {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: Double(recognitionProgress), total: Double(max(selectedImages.count, 1)))
                            .tint(RecipePalette.basil)
                        Text(isLoadingImages ? "画像を準備しています…" : "\(recognitionProgress)/\(selectedImages.count)枚目を読み取り中…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if !selectedImages.isEmpty {
                    Button {
                        Task { await recognizeSelectedImages() }
                    } label: {
                        Label("もう一度読み取る", systemImage: "arrow.clockwise")
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
        }
    }

    private var coverPhotoCard: some View {
        composerCard {
            VStack(alignment: .leading, spacing: 14) {
                cardHeading("できあがり写真", systemImage: "camera.fill", tint: RecipePalette.tomato)
                if let image = selectedImages.first?.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 210)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(RecipePalette.cream.gradient)
                        .frame(height: 150)
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: "fork.knife.circle")
                                    .font(.system(size: 38))
                                Text("写真はあとからでも追加できます")
                                    .font(.subheadline)
                            }
                            .foregroundStyle(RecipePalette.tomato)
                        }
                }

                PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 1, matching: .images) {
                    Label(selectedImages.isEmpty ? "写真を選ぶ" : "写真を変更", systemImage: "photo")
                        .frame(maxWidth: .infinity)
                }
                .onChange(of: selectedPhotoItems) { _, items in
                    Task { await loadImages(items) }
                }
            }
        }
    }

    private var selectedImagesStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(selectedImages.enumerated()), id: \.element.id) { index, item in
                    Button {
                        coverImageID = item.id
                    } label: {
                        Image(uiImage: item.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 92, height: 118)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .overlay(alignment: .topLeading) {
                                Text("\(index + 1)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .padding(6)
                                    .background(.black.opacity(0.65), in: Circle())
                                    .padding(5)
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .stroke(coverImageID == item.id ? RecipePalette.tomato : .clear, lineWidth: 3)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(index + 1)枚目。代表画像\(coverImageID == item.id ? "に選択中" : "にする")")
                }
            }
        }
        .overlay(alignment: .bottomLeading) {
            if !selectedImages.isEmpty {
                Text("タップした画像を表紙にします")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                    .offset(y: 19)
            }
        }
        .padding(.bottom, 18)
    }

    private var basicsCard: some View {
        composerCard {
            VStack(alignment: .leading, spacing: 14) {
                cardHeading("基本情報", systemImage: "sparkles", tint: RecipePalette.ember)
                VStack(alignment: .leading, spacing: 6) {
                    Text("レシピ名")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("例：いつものチキンカレー", text: $title)
                        .font(.title3.weight(.semibold))
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("ひとこと")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("味や特徴をメモ", text: $summary, axis: .vertical)
                        .lineLimit(2...4)
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
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
        composerCard {
            VStack(alignment: .leading, spacing: 10) {
                cardHeading(title, systemImage: systemImage, tint: tint)
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

    private var detailsCard: some View {
        composerCard {
            VStack(alignment: .leading, spacing: 16) {
                cardHeading("仕上げ", systemImage: "tag.fill", tint: .indigo)
                TagEditorView(tagsText: $tagsText, suggestions: frequentTags)
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("自分用メモ")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("次回の調整、家族の好みなど", text: $notes, axis: .vertical)
                        .lineLimit(3...7)
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var recognizedTextCard: some View {
        composerCard {
            DisclosureGroup {
                TextEditor(text: $recognizedText)
                    .font(.caption.monospaced())
                    .frame(minHeight: 220)
                Button {
                    applyRecognizedText()
                } label: {
                    Label("編集した文字から再抽出", systemImage: "text.magnifyingglass")
                }
            } label: {
                Label("読み取った元の文字", systemImage: "doc.text.magnifyingglass")
                    .font(.headline)
            }
        }
    }

    private func composerCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.045), radius: 12, y: 6)
    }

    private func cardHeading(_ title: String, systemImage: String, tint: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(tint)
    }

    @MainActor
    private func loadImages(_ items: [PhotosPickerItem]) async {
        isLoadingImages = true
        errorMessage = nil
        defer { isLoadingImages = false }

        var loaded: [SelectedRecipeImage] = []
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = ImageStore.previewImage(from: data, maxPixelLength: 900) else { continue }
            loaded.append(SelectedRecipeImage(data: data, image: image))
        }
        selectedImages = loaded
        coverImageID = loaded.first?.id
        if loaded.isEmpty, !items.isEmpty {
            errorMessage = "選択した画像を読み込めませんでした。"
        }
    }

    @MainActor
    private func loadAndRecognize(_ items: [PhotosPickerItem]) async {
        await loadImages(items)
        guard !selectedImages.isEmpty else { return }
        await recognizeSelectedImages()
    }

    @MainActor
    private func recognizeSelectedImages() async {
        isRecognizing = true
        recognitionProgress = 0
        errorMessage = nil
        defer { isRecognizing = false }

        var pages: [String] = []
        var failures = 0
        for (index, item) in selectedImages.enumerated() {
            do {
                let text = try await recognizer.recognizeText(in: item.data)
                pages.append(text)
            } catch {
                failures += 1
            }
            recognitionProgress = index + 1
        }

        guard !pages.isEmpty else {
            errorMessage = "画像から文字を見つけられませんでした。文字が大きく写った画像を選んでください。"
            return
        }
        recognizedText = pages.joined(separator: "\n\n")
        applyRecognizedText()
        if failures > 0 {
            errorMessage = "\(failures)枚は文字を読み取れませんでした。読み取れた画像の内容だけを反映しました。"
        }
    }

    @MainActor
    private func applyRecognizedText() {
        let result = parser.parse(recognizedText, mode: .plainText, metadataTitle: title)
        extractionResult = result
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let parsedTitle = result.title {
            title = parsedTitle
        }
        if summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let parsedSummary = result.summary {
            summary = parsedSummary
        }
        if !result.ingredients.isEmpty {
            ingredientsText = Recipe.text(from: result.ingredients)
        }
        if !result.instructions.isEmpty {
            instructionsText = Recipe.text(from: result.instructions)
        }
    }

    @MainActor
    private func save() {
        guard canSave else { return }
        let sourceKind: RecipeSourceKind = mode == .original ? .original : .image

        var imageFileName: String?
        if let cover = selectedImages.first(where: { $0.id == coverImageID }) ?? selectedImages.first {
            do {
                imageFileName = try ImageStore.save(data: cover.data)
            } catch {
                errorMessage = "画像を保存できませんでした。\n\(error.localizedDescription)"
                return
            }
        }

        let result = extractionResult
        let recipe = Recipe(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceURLString: "",
            localImageFileName: imageFileName,
            notes: notes,
            tagsText: tagsText,
            ingredientLinesText: ingredientsText,
            instructionLinesText: instructionsText,
            normalizedSourceURLString: "",
            sourceKindRaw: sourceKind.rawValue,
            extractedRawText: recognizedText,
            rawImportedText: recognizedText,
            importedTextSource: mode == .images ? "visionOCR" : "manual",
            extractionConfidence: result?.confidence ?? 0,
            extractionWarningsText: Recipe.text(from: result?.warnings ?? []),
            ingredientSource: mode == .images && !(result?.ingredients.isEmpty ?? true) ? "visionOCR" : "manual",
            instructionSource: mode == .images && !(result?.instructions.isEmpty ?? true) ? "visionOCR" : "manual"
        )
        recipe.refreshDerivedFields()
        modelContext.insert(recipe)
        do {
            try modelContext.save()
            onSaved()
        } catch {
            ImageStore.delete(fileName: imageFileName)
            modelContext.delete(recipe)
            errorMessage = "レシピを保存できませんでした。\n\(error.localizedDescription)"
        }
    }
}
