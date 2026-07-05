import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct RecipeDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var recipe: Recipe

    @State private var showingAddCookLog = false
    @State private var showingEditView = false
    @State private var showingShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var exportMessage: RecipeExportMessage?
    @State private var isExportingPDF = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                heroImage
                titleBlock
                sourceButton
                summarySection
                ingredientsSection
                instructionsSection
                notesSection
                tagsSection
                cookLogsSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .background(
            LinearGradient(
                colors: [
                    RecipePalette.tomato.opacity(0.09),
                    Color(.systemGroupedBackground),
                    RecipePalette.basil.opacity(0.06)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle("レシピ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button {
                        shareItems = [shareText]
                        showingShareSheet = true
                    } label: {
                        Label("テキストで共有", systemImage: "text.alignleft")
                    }

                    Button {
                        exportSinglePDF()
                    } label: {
                        Label("PDFで共有", systemImage: "doc.richtext")
                    }
                    .disabled(isExportingPDF)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }

                if isExportingPDF {
                    ProgressView()
                }
                Button("編集") {
                    showingEditView = true
                }
            }
        }
        .navigationDestination(isPresented: $showingEditView) {
            RecipeEditView(recipe: recipe)
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(activityItems: shareItems)
        }
        .sheet(isPresented: $showingAddCookLog) {
            AddCookLogView(recipe: recipe)
        }
        .alert(item: $exportMessage) { message in
            Alert(
                title: Text(message.title),
                message: Text(message.detail),
                dismissButton: .default(Text("OK"))
            )
        }
        .onAppear {
            recipe.refreshDerivedFields()
        }
    }

    private var heroImage: some View {
        LocalImageView(fileName: recipe.localImageFileName, cornerRadius: 24, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 220, maxHeight: 340)
            .background(.background, in: RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.14), radius: 12, y: 6)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(recipe.sourceKind.displayName)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(RecipePalette.tomato, in: Capsule())
                    .foregroundStyle(.white)

                if recipe.isFavorite {
                    Label("お気に入り", systemImage: "heart.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.pink.opacity(0.14), in: Capsule())
                        .foregroundStyle(.pink)
                }

                if recipe.wantsRemake {
                    Text("また作りたい")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(RecipePalette.basil.opacity(0.14), in: Capsule())
                        .foregroundStyle(RecipePalette.basil)
                }
            }

            Text(recipe.title)
                .font(.system(.title2, design: .serif, weight: .bold))
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)

            Text(metaText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var sourceButton: some View {
        if let url = recipe.sourceURL {
            Link(destination: url) {
                Label("元レシピを開く", systemImage: "safari")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        LinearGradient(
                            colors: [RecipePalette.tomato, RecipePalette.ember],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: Capsule()
                    )
                    .foregroundStyle(.white)
                    .shadow(color: RecipePalette.tomato.opacity(0.35), radius: 8, y: 4)
            }
        }
    }

    @ViewBuilder
    private var summarySection: some View {
        if !recipe.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            DetailSection(title: "概要") {
                Text(recipe.summary)
                    .font(.body)
                    .lineSpacing(4)
                    .textSelection(.enabled)
            }
        }
    }

    private var ingredientsSection: some View {
        DetailSection(title: "材料") {
            if recipe.ingredientLines.isEmpty {
                EmptyDetailText("材料情報なし")
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(recipe.ingredientLines, id: \.self) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("・")
                                .foregroundStyle(.secondary)
                            Text(line)
                                .textSelection(.enabled)
                        }
                    }
                }
                .font(.body)
                .lineSpacing(3)
            }
        }
    }

    private var instructionsSection: some View {
        DetailSection(title: "作り方") {
            if recipe.instructionLines.isEmpty {
                EmptyDetailText("作り方情報なし")
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(recipe.instructionLines.enumerated()), id: \.offset) { index, line in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 26, height: 26)
                                .background(
                                    Circle().fill(
                                        LinearGradient(
                                            colors: [RecipePalette.tomato, RecipePalette.ember],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                )
                            Text(line)
                                .font(.body)
                                .lineSpacing(4)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var notesSection: some View {
        if !recipe.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            DetailSection(title: "自分メモ") {
                Text(recipe.notes)
                    .font(.body)
                    .lineSpacing(4)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var tagsSection: some View {
        if !recipe.tags.isEmpty {
            DetailSection(title: "タグ") {
                FlowTags(tags: recipe.tags)
            }
        }
    }

    private var cookLogsSection: some View {
        DetailSection(title: "作った記録") {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    showingAddCookLog = true
                } label: {
                    Label("作った記録を追加", systemImage: "camera")
                }
                .buttonStyle(.bordered)

                if recipe.cookLogs.isEmpty {
                    EmptyDetailText("まだ作った記録がありません")
                } else {
                    ForEach(recipe.cookLogs.sorted(by: { $0.cookedAt > $1.cookedAt })) { log in
                        CookLogCard(log: log)
                    }
                }
            }
        }
    }

    private var metaText: String {
        var parts: [String] = []
        let source = recipe.sourceHost.isEmpty ? recipe.sourceKind.displayName : recipe.sourceHost
        parts.append("\(source) / \(recipe.sourceKind.displayName)")
        if recipe.rating > 0 { parts.append(RatingStars.text(for: recipe.rating)) }
        if recipe.isFavorite { parts.append("お気に入り") }
        if recipe.wantsRemake { parts.append("また作りたい") }
        parts.append("\(recipe.cookLogs.count)回作成")
        if let lastCookedAt = recipe.lastCookedAt {
            parts.append("最終: \(lastCookedAt.formatted(date: .numeric, time: .omitted))")
        }
        return parts.joined(separator: " ・ ")
    }

    private var shareText: String {
        var blocks = [recipe.title]
        if !recipe.summary.isEmpty {
            blocks.append("概要:\n\(recipe.summary)")
        }
        if !recipe.ingredientLines.isEmpty {
            blocks.append("材料:\n" + recipe.ingredientLines.map { "・\($0)" }.joined(separator: "\n"))
        }
        if !recipe.instructionLines.isEmpty {
            let steps = recipe.instructionLines.enumerated().map { "\($0.offset + 1). \($0.element)" }
            blocks.append("作り方:\n" + steps.joined(separator: "\n"))
        }
        if !recipe.notes.isEmpty {
            blocks.append("メモ:\n\(recipe.notes)")
        }
        if !recipe.sourceURLString.isEmpty {
            blocks.append("元URL:\n\(recipe.sourceURLString)")
        }
        return blocks.joined(separator: "\n\n")
    }

    @MainActor
    private func exportSinglePDF() {
        isExportingPDF = true
        do {
            let url = try RecipePDFExporter().exportSingle(recipe: recipe)
            shareItems = [url]
            showingShareSheet = true
        } catch {
            exportMessage = RecipeExportMessage(title: "PDFの作成に失敗しました。", detail: error.localizedDescription)
        }
        isExportingPDF = false
    }
}

private struct RecipeEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var recipes: [Recipe]

    @Bindable var recipe: Recipe
    @State private var selectedPhoto: PhotosPickerItem?

    private var frequentTags: [String] {
        let counts = Dictionary(grouping: recipes.flatMap(\.tags), by: { $0 })
            .mapValues(\.count)
        return counts.sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
        }
        .map(\.key)
    }

    var body: some View {
        Form {
            Section("代表画像") {
                LocalImageView(fileName: recipe.localImageFileName, cornerRadius: 16, contentMode: .fit)
                    .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 260)
                    .listRowInsets(EdgeInsets())

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("代表画像を変更", systemImage: "photo.on.rectangle")
                }
                .onChange(of: selectedPhoto) { _, newItem in
                    Task { await replaceHeroImage(with: newItem) }
                }
            }

            Section("基本情報") {
                TextField("タイトル", text: $recipe.title)
                TextField("概要", text: $recipe.summary, axis: .vertical)
                    .lineLimit(3...10)
                Picker("ソース種別", selection: $recipe.sourceKindRaw) {
                    ForEach(RecipeSourceKind.allCases) { kind in
                        Text(kind.displayName).tag(kind.rawValue)
                    }
                }
            }

            Section("材料") {
                TextEditor(text: $recipe.ingredientLinesText)
                    .frame(minHeight: 140)
            }

            Section("作り方") {
                TextEditor(text: $recipe.instructionLinesText)
                    .frame(minHeight: 190)
            }

            Section("タグ") {
                TagEditorView(tagsText: $recipe.tagsText, suggestions: frequentTags)
            }

            Section("自分メモ") {
                TextEditor(text: $recipe.notes)
                    .frame(minHeight: 110)
            }

            Section {
                DisclosureGroup("取得した元本文") {
                    TextEditor(text: $recipe.rawImportedText)
                        .frame(minHeight: 220)
                    if !recipe.importedTextSource.isEmpty {
                        LabeledContent("取得元", value: recipe.importedTextSource)
                    }
                }
            }

            Section("お気に入り・評価") {
                Toggle("お気に入り", isOn: $recipe.isFavorite)
                Toggle("また作りたい", isOn: $recipe.wantsRemake)
                HStack {
                    Text("評価")
                    Spacer()
                    RatingPicker(rating: $recipe.rating)
                }
            }

            Section("出典") {
                if let url = recipe.sourceURL {
                    Link("元レシピを開く", destination: url)
                }
                Text(recipe.sourceURLString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .navigationTitle("レシピを編集")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完了") {
                    saveAndDismiss()
                }
            }
        }
        .onDisappear {
            save()
        }
    }

    @MainActor
    private func replaceHeroImage(with item: PhotosPickerItem?) async {
        guard let data = try? await item?.loadTransferable(type: Data.self),
              let fileName = try? ImageStore.save(data: data) else {
            return
        }
        recipe.localImageFileName = fileName
        save()
    }

    private func saveAndDismiss() {
        save()
        dismiss()
    }

    private func save() {
        recipe.refreshDerivedFields()
        recipe.updatedAt = Date()
        try? modelContext.save()
    }
}

private struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [RecipePalette.tomato, RecipePalette.ember],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 4, height: 17)
                Text(title)
                    .font(.system(.headline, design: .serif, weight: .bold))
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
    }
}

private struct EmptyDetailText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.secondary)
    }
}

private struct FlowTags: View {
    let tags: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Text("# \(tag)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(RecipePalette.basil.opacity(0.12), in: Capsule())
                    .foregroundStyle(RecipePalette.basil)
            }
        }
    }
}

private struct CookLogCard: View {
    let log: CookLog

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                LocalImageView(fileName: log.localImageFileName, cornerRadius: 10, contentMode: .fill)
                    .frame(width: 72, height: 72)
                    .clipped()

                VStack(alignment: .leading, spacing: 4) {
                    Text(log.cookedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.subheadline.weight(.semibold))
                    if log.rating > 0 {
                        Text(RatingStars.text(for: log.rating))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !log.memo.isEmpty {
                LabeledCookLogText(title: "メモ", text: log.memo)
            }
            if !log.arrangementMemo.isEmpty {
                LabeledCookLogText(title: "アレンジ", text: log.arrangementMemo)
            }
            if !log.improvementMemo.isEmpty {
                LabeledCookLogText(title: "次回改善", text: log.improvementMemo)
            }
        }
        .padding(12)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct LabeledCookLogText: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline)
                .lineSpacing(3)
        }
    }
}

private struct AddCookLogView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var recipe: Recipe
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var memo = ""
    @State private var improvementMemo = ""
    @State private var arrangementMemo = ""
    @State private var cookedAt = Date()
    @State private var rating = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("写真") {
                    if let selectedImageData, let uiImage = UIImage(data: selectedImageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .listRowInsets(EdgeInsets())
                    }

                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("写真を選ぶ", systemImage: "photo")
                    }
                    .onChange(of: selectedPhoto) { _, newItem in
                        Task {
                            selectedImageData = try? await newItem?.loadTransferable(type: Data.self)
                        }
                    }
                }

                Section("記録") {
                    DatePicker("作った日", selection: $cookedAt, displayedComponents: .date)
                    HStack {
                        Text("評価")
                        Spacer()
                        RatingPicker(rating: $rating)
                    }
                    TextField("メモ", text: $memo, axis: .vertical)
                        .lineLimit(3...8)
                    TextField("次回改善メモ", text: $improvementMemo, axis: .vertical)
                        .lineLimit(2...6)
                    TextField("アレンジ内容", text: $arrangementMemo, axis: .vertical)
                        .lineLimit(2...6)
                }
            }
            .navigationTitle("作った記録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
        }
    }

    private func save() {
        let fileName = selectedImageData.flatMap { try? ImageStore.save(data: $0) }
        let log = CookLog(
            cookedAt: cookedAt,
            memo: memo,
            localImageFileName: fileName,
            rating: rating,
            improvementMemo: improvementMemo,
            arrangementMemo: arrangementMemo,
            recipe: recipe
        )
        modelContext.insert(log)
        recipe.updatedAt = Date()
        if rating > recipe.rating {
            recipe.rating = rating
        }
        try? modelContext.save()
        dismiss()
    }
}

private struct RecipeExportMessage: Identifiable {
    let id = UUID()
    var title: String
    var detail: String
}
