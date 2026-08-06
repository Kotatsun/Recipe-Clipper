import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct RecipeDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var recipe: Recipe

    @State private var showingAddCookLog = false
    @State private var showingEditView = false
    @State private var sharePayload: SharePayload?
    @State private var editingCookLog: CookLog?
    @State private var cookLogToDelete: CookLog?
    @State private var exportMessage: RecipeExportMessage?
    @State private var isExportingPDF = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                heroImage
                titleBlock
                ingredientsSection
                instructionsSection
                finishingSection
                cookLogsSection
            }
            .padding(16)
            .padding(.bottom, 28)
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
                        sharePayload = SharePayload(items: [shareText])
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
        .sheet(isPresented: $showingEditView) {
            RecipeEditView(recipe: recipe)
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheet(activityItems: payload.items)
        }
        .sheet(isPresented: $showingAddCookLog) {
            CookLogFormView(recipe: recipe)
        }
        .sheet(item: $editingCookLog) { log in
            CookLogFormView(recipe: recipe, editingLog: log)
        }
        .confirmationDialog(
            "この作った記録を削除しますか？",
            isPresented: deleteCookLogConfirmationBinding,
            titleVisibility: .visible
        ) {
            Button("削除", role: .destructive) {
                if let log = cookLogToDelete {
                    deleteCookLog(log)
                }
                cookLogToDelete = nil
            }
            Button("キャンセル", role: .cancel) {
                cookLogToDelete = nil
            }
        }
        .alert(item: $exportMessage) { message in
            Alert(
                title: Text(message.title),
                message: Text(message.detail),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var deleteCookLogConfirmationBinding: Binding<Bool> {
        Binding(
            get: { cookLogToDelete != nil },
            set: { isPresented in
                if !isPresented {
                    cookLogToDelete = nil
                }
            }
        )
    }

    private func deleteCookLog(_ log: CookLog) {
        // 画像ファイルはDB削除のコミット成功後に消す
        let imageFileName = log.localImageFileName
        modelContext.delete(log)
        recipe.updatedAt = Date()
        do {
            try modelContext.save()
        } catch {
            return
        }
        ImageStore.delete(fileName: imageFileName)
    }

    private var heroImage: some View {
        LocalImageView(fileName: recipe.localImageFileName, cornerRadius: 24, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 220, maxHeight: 340)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 14, y: 7)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(recipe.sourceKind.displayName)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(RecipePalette.tomato, in: Capsule())
                    .foregroundStyle(.white)

                ToggleChip(
                    title: "お気に入り",
                    systemImage: recipe.isFavorite ? "heart.fill" : "heart",
                    isOn: recipe.isFavorite,
                    onColor: .pink
                ) {
                    recipe.isFavorite.toggle()
                    saveLightChange()
                }

                ToggleChip(
                    title: "また作りたい",
                    systemImage: recipe.wantsRemake ? "bookmark.fill" : "bookmark",
                    isOn: recipe.wantsRemake,
                    onColor: RecipePalette.basil
                ) {
                    recipe.wantsRemake.toggle()
                    saveLightChange()
                }
            }

            Text(recipe.title)
                .font(.system(.title2, design: .serif, weight: .bold))
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)

            if !recipe.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(recipe.summary)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .textSelection(.enabled)
            }

            Divider()

            HStack(spacing: 10) {
                Text("評価")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                RatingPicker(rating: ratingBinding)
            }

            Text(metaText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .textSelection(.enabled)

            sourceLink
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.045), radius: 12, y: 6)
    }

    private var ratingBinding: Binding<Int> {
        Binding(
            get: { recipe.rating },
            set: { newValue in
                recipe.rating = newValue
                saveLightChange()
            }
        )
    }

    // お気に入り・また作りたい・評価・材料チェックのような軽い操作では
    // updatedAtを更新しない(一覧の「最近更新」ソート順が変わってしまうため)
    private func saveLightChange() {
        try? modelContext.save()
    }

    @ViewBuilder
    private var sourceLink: some View {
        if let url = recipe.sourceURL {
            Link(destination: url) {
                HStack {
                    Label("元レシピを開く", systemImage: "safari")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(RecipePalette.tomato.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(RecipePalette.tomato)
            }
        }
    }

    private var ingredientsSection: some View {
        DetailSection(title: "材料", systemImage: "carrot.fill", tint: RecipePalette.basil) {
            if !recipe.servingsText.isEmpty {
                Label(recipe.servingsText, systemImage: "person.2.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(RecipePalette.basil)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RecipePalette.basil.opacity(0.10), in: Capsule())
                    .accessibilityLabel("何人分 \(recipe.servingsText)")
            }
            if recipe.ingredientLines.isEmpty {
                EmptyDetailText("材料情報なし")
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    if checkedIngredientCount > 0 {
                        HStack {
                            Text("\(checkedIngredientCount)/\(recipe.ingredientLines.count) チェック済み")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("リセット") {
                                recipe.checkedIngredientLinesText = ""
                                saveLightChange()
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(RecipePalette.basil)
                        }
                    }

                    ForEach(recipe.ingredientLines, id: \.self) { line in
                        ingredientRow(line)
                    }
                }
                .font(.body)
                .lineSpacing(3)
            }
        }
    }

    private func ingredientRow(_ line: String) -> some View {
        let isChecked = recipe.isIngredientChecked(line)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isChecked ? RecipePalette.basil : Color.secondary)
            Text(line)
                .strikethrough(isChecked)
                .foregroundStyle(isChecked ? Color.secondary : Color.primary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            recipe.toggleIngredientChecked(line)
            saveLightChange()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isChecked ? "チェック済み" : "未チェック")
        .accessibilityAction {
            recipe.toggleIngredientChecked(line)
            saveLightChange()
        }
    }

    private var checkedIngredientCount: Int {
        // 材料編集後に残った古いチェック行を数えないよう、現在の材料と突き合わせる
        let currentLines = Set(recipe.ingredientLines)
        return recipe.checkedIngredientLines.filter(currentLines.contains).count
    }

    private var instructionsSection: some View {
        DetailSection(title: "作り方", systemImage: "list.number", tint: RecipePalette.tomato) {
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
    private var finishingSection: some View {
        let hasNotes = !recipe.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasTags = !recipe.tags.isEmpty

        if hasNotes || hasTags {
            DetailSection(title: "メモとタグ", systemImage: "tag.fill", tint: .indigo) {
                VStack(alignment: .leading, spacing: 12) {
                    if hasNotes {
                        Text(recipe.notes)
                            .font(.body)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                    }
                    if hasNotes && hasTags {
                        Divider()
                    }
                    if hasTags {
                        FlowTags(tags: recipe.tags)
                    }
                }
            }
        }
    }

    private var cookLogsSection: some View {
        DetailSection(title: "作った記録", systemImage: "clock.arrow.circlepath", tint: RecipePalette.ember) {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    showingAddCookLog = true
                } label: {
                    Label("作った記録を追加", systemImage: "camera")
                }
                .buttonStyle(.bordered)
                .tint(RecipePalette.ember)

                if recipe.cookLogs.isEmpty {
                    EmptyDetailText("まだ作った記録がありません")
                } else {
                    ForEach(recipe.cookLogs.sorted(by: { $0.cookedAt > $1.cookedAt })) { log in
                        CookLogCard(
                            log: log,
                            onEdit: { editingCookLog = log },
                            onDelete: { cookLogToDelete = log }
                        )
                        .contextMenu {
                            Button {
                                editingCookLog = log
                            } label: {
                                Label("編集", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                cookLogToDelete = log
                            } label: {
                                Label("削除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    // 評価・お気に入り・また作りたいは上のトグルUIが状態を示すため、ここには含めない
    private var metaText: String {
        var parts: [String] = []
        if !recipe.sourceHost.isEmpty {
            parts.append(recipe.sourceHost)
        }
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
            let heading = recipe.servingsText.isEmpty ? "材料" : "材料（\(recipe.servingsText)）"
            blocks.append("\(heading):\n" + recipe.ingredientLines.map { "・\($0)" }.joined(separator: "\n"))
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
            sharePayload = SharePayload(items: [url])
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
    // @Bindableでモデルへ直接書き込むため、キャンセル用に開いた時点の値を控えておく。
    // onAppearではなくinitで取ることで、シート表示ごとに必ず新しい値が入る
    @State private var snapshot: RecipeEditSnapshot
    @State private var didCancel = false
    @State private var isReplacingPhoto = false
    @State private var imageErrorMessage: String?

    init(recipe: Recipe) {
        self.recipe = recipe
        _snapshot = State(initialValue: RecipeEditSnapshot(recipe: recipe))
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
            editForm
        }
    }

    private var editForm: some View {
        ScrollView {
            VStack(spacing: 16) {
                editCoverCard
                editBasicsCard
                editTextCard(
                    title: "材料",
                    systemImage: "carrot.fill",
                    tint: RecipePalette.basil,
                    text: $recipe.ingredientLinesText,
                    minimumHeight: 145,
                    placeholder: "材料を自由に入力"
                )
                editTextCard(
                    title: "作り方",
                    systemImage: "list.number",
                    tint: RecipePalette.tomato,
                    text: $recipe.instructionLinesText,
                    minimumHeight: 190,
                    placeholder: "作り方を自由に入力"
                )
                editFinishingCard
                editPreferenceCard
                editSourceCard
                editSaveButton
            }
            .padding(16)
            .padding(.bottom, 36)
        }
        .background(
            LinearGradient(
                colors: [RecipePalette.tomato.opacity(0.07), Color(.systemGroupedBackground), RecipePalette.basil.opacity(0.06)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle("レシピを編集")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル") {
                    cancelAndDismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("完了") {
                    saveAndDismiss()
                }
                .fontWeight(.semibold)
                .disabled(recipe.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isReplacingPhoto)
            }
        }
        .alert("画像を変更できませんでした", isPresented: Binding(
            get: { imageErrorMessage != nil },
            set: { if !$0 { imageErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { imageErrorMessage = nil }
        } message: {
            Text(imageErrorMessage ?? "")
        }
        // シートのスワイプ閉じは従来どおり保存扱い
        .onDisappear {
            if !didCancel {
                save()
            }
        }
    }

    private var editCoverCard: some View {
        editCard {
            VStack(alignment: .leading, spacing: 14) {
                editCardHeading("できあがり写真", systemImage: "camera.fill", tint: RecipePalette.tomato)

                LocalImageView(fileName: recipe.localImageFileName, cornerRadius: 18, contentMode: .fit)
                    .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 280)
                    .background(RecipePalette.cream.opacity(0.45), in: RoundedRectangle(cornerRadius: 18))

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    HStack(spacing: 8) {
                        if isReplacingPhoto {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "photo.on.rectangle")
                        }
                        Text(isReplacingPhoto ? "写真を変更中…" : recipe.localImageFileName == nil ? "写真を選ぶ" : "写真を変更")
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .foregroundStyle(.white)
                    .background(
                        LinearGradient(colors: [RecipePalette.tomato, RecipePalette.ember], startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                }
                .disabled(isReplacingPhoto)
                .onChange(of: selectedPhoto) { _, newItem in
                    Task { await replaceHeroImage(with: newItem) }
                }
            }
        }
    }

    private var editBasicsCard: some View {
        editCard {
            VStack(alignment: .leading, spacing: 14) {
                editCardHeading("基本情報", systemImage: "sparkles", tint: RecipePalette.ember)

                VStack(alignment: .leading, spacing: 6) {
                    Text("レシピ名")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("レシピ名", text: $recipe.title)
                        .font(.title3.weight(.semibold))
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("ひとこと")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("味や特徴をメモ", text: $recipe.summary, axis: .vertical)
                        .lineLimit(3...10)
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Text("何人分")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("任意")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(RecipePalette.basil)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(RecipePalette.basil.opacity(0.10), in: Capsule())
                    }
                    TextField("例：2人分", text: $recipe.servingsText)
                        .textInputAutocapitalization(.never)
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }

                HStack {
                    Label("登録方法", systemImage: "square.and.pencil")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Picker("登録方法", selection: $recipe.sourceKindRaw) {
                        ForEach(RecipeSourceKind.allCases) { kind in
                            Text(kind.displayName).tag(kind.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func editTextCard(
        title: String,
        systemImage: String,
        tint: Color,
        text: Binding<String>,
        minimumHeight: CGFloat,
        placeholder: String
    ) -> some View {
        editCard {
            VStack(alignment: .leading, spacing: 10) {
                editCardHeading(title, systemImage: systemImage, tint: tint)
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

    private var editFinishingCard: some View {
        editCard {
            VStack(alignment: .leading, spacing: 16) {
                editCardHeading("仕上げ", systemImage: "tag.fill", tint: .indigo)
                TagEditorView(tagsText: $recipe.tagsText, suggestions: frequentTags)
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("自分用メモ")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ZStack(alignment: .topLeading) {
                        if recipe.notes.isEmpty {
                            Text("次回の調整、家族の好みなど")
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $recipe.notes)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 110)
                    }
                    .padding(8)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    private var editPreferenceCard: some View {
        editCard {
            VStack(alignment: .leading, spacing: 14) {
                editCardHeading("お気に入り・評価", systemImage: "heart.fill", tint: .pink)
                Toggle(isOn: $recipe.isFavorite) {
                    Label("お気に入り", systemImage: recipe.isFavorite ? "heart.fill" : "heart")
                }
                Toggle(isOn: $recipe.wantsRemake) {
                    Label("また作りたい", systemImage: recipe.wantsRemake ? "bookmark.fill" : "bookmark")
                }
                Divider()
                HStack {
                    Label("評価", systemImage: "star.fill")
                    Spacer()
                    RatingPicker(rating: $recipe.rating)
                }
            }
        }
    }

    private var editSourceCard: some View {
        editCard {
            VStack(alignment: .leading, spacing: 12) {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 10) {
                        if recipe.sourceURLString.isEmpty {
                            LabeledContent("登録方法", value: recipe.sourceKind.displayName)
                        } else if let url = recipe.sourceURL {
                            Link(destination: url) {
                                Label("元レシピを開く", systemImage: "safari")
                            }
                            Text(recipe.sourceURLString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Label("出典", systemImage: "link")
                        .font(.headline)
                }

                if !recipe.rawImportedText.isEmpty || !recipe.rawImportedHTML.isEmpty {
                    Divider()
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 10) {
                            TextEditor(text: $recipe.rawImportedText)
                                .font(.caption.monospaced())
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 220)
                                .padding(8)
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                            if !recipe.importedTextSource.isEmpty {
                                LabeledContent("取得元", value: recipe.importedTextSource)
                            }
                            Button {
                                UIPasteboard.general.string = recipe.rawImportedText
                            } label: {
                                Label("本文をコピー（テストケース用）", systemImage: "doc.on.doc")
                            }
                            .disabled(recipe.rawImportedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            Button {
                                UIPasteboard.general.string = recipe.rawImportedHTML
                            } label: {
                                Label("取得HTMLをコピー（テストケース用）", systemImage: "chevron.left.forwardslash.chevron.right")
                            }
                            .disabled(recipe.rawImportedHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .padding(.top, 8)
                    } label: {
                        Label("取得した元本文", systemImage: "doc.text.magnifyingglass")
                            .font(.headline)
                    }
                }
            }
        }
    }

    private var editSaveButton: some View {
        Button {
            saveAndDismiss()
        } label: {
            Label("変更を保存", systemImage: "checkmark.circle.fill")
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
        .disabled(recipe.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isReplacingPhoto)
        .opacity(recipe.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isReplacingPhoto ? 0.55 : 1)
    }

    private func editCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.045), radius: 12, y: 6)
    }

    private func editCardHeading(_ title: String, systemImage: String, tint: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(tint)
    }

    @MainActor
    private func replaceHeroImage(with item: PhotosPickerItem?) async {
        guard let item else { return }
        isReplacingPhoto = true
        imageErrorMessage = nil
        defer { isReplacingPhoto = false }

        guard let data = try? await item.loadTransferable(type: Data.self),
              let fileName = try? ImageStore.save(data: data) else {
            imageErrorMessage = "選択した画像を読み込めませんでした。"
            return
        }
        recipe.localImageFileName = fileName
        save()
    }

    private func saveAndDismiss() {
        save()
        dismiss()
    }

    private func cancelAndDismiss() {
        didCancel = true
        // この編集中に差し替えた代表画像は、キャンセルで参照が元に戻り
        // どこからも参照されなくなるため、ファイルごと削除する
        if let newFileName = recipe.localImageFileName, newFileName != snapshot.localImageFileName {
            ImageStore.delete(fileName: newFileName)
        }
        snapshot.apply(to: recipe)
        try? modelContext.save()
        dismiss()
    }

    private func save() {
        recipe.refreshDerivedFields()
        recipe.updatedAt = Date()
        try? modelContext.save()
    }
}

/// 編集開始時点のレシピの値。キャンセル時にモデルへ書き戻す
private struct RecipeEditSnapshot {
    var title: String
    var summary: String
    var sourceKindRaw: String
    var servingsText: String
    var ingredientLinesText: String
    var instructionLinesText: String
    var checkedIngredientLinesText: String
    var tagsText: String
    var notes: String
    var rawImportedText: String
    var isFavorite: Bool
    var wantsRemake: Bool
    var rating: Int
    var localImageFileName: String?

    init(recipe: Recipe) {
        title = recipe.title
        summary = recipe.summary
        sourceKindRaw = recipe.sourceKindRaw
        servingsText = recipe.servingsText
        ingredientLinesText = recipe.ingredientLinesText
        instructionLinesText = recipe.instructionLinesText
        checkedIngredientLinesText = recipe.checkedIngredientLinesText
        tagsText = recipe.tagsText
        notes = recipe.notes
        rawImportedText = recipe.rawImportedText
        isFavorite = recipe.isFavorite
        wantsRemake = recipe.wantsRemake
        rating = recipe.rating
        localImageFileName = recipe.localImageFileName
    }

    func apply(to recipe: Recipe) {
        recipe.title = title
        recipe.summary = summary
        recipe.sourceKindRaw = sourceKindRaw
        recipe.servingsText = servingsText
        recipe.ingredientLinesText = ingredientLinesText
        recipe.instructionLinesText = instructionLinesText
        recipe.checkedIngredientLinesText = checkedIngredientLinesText
        recipe.tagsText = tagsText
        recipe.notes = notes
        recipe.rawImportedText = rawImportedText
        recipe.isFavorite = isFavorite
        recipe.wantsRemake = wantsRemake
        recipe.rating = rating
        recipe.localImageFileName = localImageFileName
    }
}

private struct SharePayload: Identifiable {
    let id = UUID()
    var items: [Any]
}

/// 詳細画面でタップして切り替えられる状態チップ(お気に入り・また作りたい)。
/// 未設定時も薄く表示し、タップ対象であることが分かるようにする
private struct ToggleChip: View {
    let title: String
    let systemImage: String
    let isOn: Bool
    let onColor: Color
    let action: () -> Void

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                isOn ? onColor.opacity(0.14) : Color.secondary.opacity(0.08),
                in: Capsule()
            )
            .foregroundStyle(isOn ? onColor : Color.secondary)
            .contentShape(Capsule())
            .onTapGesture(perform: action)
            .accessibilityAddTraits(.isButton)
            .accessibilityRemoveTraits(.isStaticText)
            .accessibilityAction {
                action()
            }
            .accessibilityLabel(title)
            .accessibilityValue(isOn ? "オン" : "オフ")
    }
}

private struct DetailSection<Content: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.045), radius: 12, y: 6)
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
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                LocalImageView(fileName: log.localImageFileName, cornerRadius: 10, contentMode: .fill, maxPixelLength: 300)
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

                Spacer(minLength: 0)

                Menu {
                    Button {
                        onEdit()
                    } label: {
                        Label("編集", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("削除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(4)
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

/// 作った記録の追加・編集フォーム。editingLogがnilなら新規追加、指定されていればその記録を編集する
private struct CookLogFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var recipe: Recipe
    let editingLog: CookLog?

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var memo: String
    @State private var improvementMemo: String
    @State private var arrangementMemo: String
    @State private var cookedAt: Date
    @State private var rating: Int

    init(recipe: Recipe, editingLog: CookLog? = nil) {
        self.recipe = recipe
        self.editingLog = editingLog
        _memo = State(initialValue: editingLog?.memo ?? "")
        _improvementMemo = State(initialValue: editingLog?.improvementMemo ?? "")
        _arrangementMemo = State(initialValue: editingLog?.arrangementMemo ?? "")
        _cookedAt = State(initialValue: editingLog?.cookedAt ?? Date())
        _rating = State(initialValue: editingLog?.rating ?? 0)
    }

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
                    } else if editingLog?.localImageFileName != nil {
                        LocalImageView(fileName: editingLog?.localImageFileName, cornerRadius: 16, contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: 220)
                            .listRowInsets(EdgeInsets())
                    }

                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label(editingLog == nil ? "写真を選ぶ" : "写真を変更", systemImage: "photo")
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
            .navigationTitle(editingLog == nil ? "作った記録" : "記録を編集")
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
        // 差し替えで参照されなくなる旧画像。削除はDBコミット成功後に行う
        var replacedImageFileName: String?
        if let editingLog {
            if let selectedImageData, let fileName = try? ImageStore.save(data: selectedImageData) {
                replacedImageFileName = editingLog.localImageFileName
                editingLog.localImageFileName = fileName
            }
            editingLog.cookedAt = cookedAt
            editingLog.memo = memo
            editingLog.rating = rating
            editingLog.improvementMemo = improvementMemo
            editingLog.arrangementMemo = arrangementMemo
        } else {
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
        }
        recipe.updatedAt = Date()
        if rating > recipe.rating {
            recipe.rating = rating
        }
        if (try? modelContext.save()) != nil {
            ImageStore.delete(fileName: replacedImageFileName)
        }
        dismiss()
    }
}

private struct RecipeExportMessage: Identifiable {
    let id = UUID()
    var title: String
    var detail: String
}
