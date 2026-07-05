import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct RecipeListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var recipes: [Recipe]

    @AppStorage("RecipeListSort") private var sortRawValue = RecipeSort.recentlyUpdated.rawValue
    @State private var showingImport = false
    @State private var importURLText: String?
    @State private var searchText = ""
    @State private var selectedFilter: RecipeFilter = .all
    @State private var selectedTag: String?
    @State private var backupDocument: RecipeBackupDocument?
    @State private var showingBackupExporter = false
    @State private var showingBackupImporter = false
    @State private var showingPDFShareSheet = false
    @State private var pdfShareURL: URL?
    @State private var pendingRestoreURL: BackupRestoreSelection?
    @State private var backupMessage: BackupMessage?
    @State private var isRunningBackupTask = false

    private var sort: RecipeSort {
        RecipeSort(rawValue: sortRawValue) ?? .recentlyUpdated
    }

    private var visibleRecipes: [Recipe] {
        recipes
            .filter(matchesSearch)
            .filter { selectedFilter.matches($0) }
            .filter(matchesSelectedTag)
            .sorted(by: sort.areInIncreasingOrder)
    }

    private var allTags: [String] {
        let counts = Dictionary(grouping: recipes.flatMap(\.tags), by: { $0 })
            .mapValues(\.count)
        return counts.sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
        }
        .map(\.key)
    }

    private var totalCookCount: Int {
        recipes.reduce(0) { $0 + $1.cookLogs.count }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18, pinnedViews: [.sectionHeaders]) {
                    headerBlock
                    Section {
                        cardsBlock
                    } header: {
                        chipBlock
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
            .background(backgroundView)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "料理名・タグ・材料・メモで検索")
            .animation(.snappy(duration: 0.25), value: selectedFilter)
            .animation(.snappy(duration: 0.25), value: selectedTag)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("並び替え", selection: $sortRawValue) {
                            ForEach(RecipeSort.allCases) { sort in
                                Text(sort.title).tag(sort.rawValue)
                            }
                        }
                    } label: {
                        Label(sort.title, systemImage: "arrow.up.arrow.down")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        Menu {
                            Button {
                                Task { await exportBackup() }
                            } label: {
                                Label("バックアップを書き出し", systemImage: "square.and.arrow.up")
                            }
                            .disabled(isRunningBackupTask)

                            Button {
                                Task { await exportAllRecipesPDF() }
                            } label: {
                                Label("全レシピをPDFでバックアップ", systemImage: "doc.richtext")
                            }
                            .disabled(isRunningBackupTask)

                            Button {
                                showingBackupImporter = true
                            } label: {
                                Label("バックアップから復元", systemImage: "arrow.counterclockwise")
                            }
                            .disabled(isRunningBackupTask)
                        } label: {
                            Label("バックアップ", systemImage: "ellipsis.circle")
                        }

                        Button {
                            importURLText = nil
                            showingImport = true
                        } label: {
                            Label("URLから追加", systemImage: "plus")
                        }
                    }
                }
            }
            .fileExporter(
                isPresented: $showingBackupExporter,
                document: backupDocument,
                contentType: .zip,
                defaultFilename: defaultBackupFileName
            ) { result in
                switch result {
                case .success:
                    backupMessage = BackupMessage(title: "バックアップを書き出しました", detail: "Filesアプリで保存先を確認できます。")
                case .failure(let error):
                    backupMessage = BackupMessage(title: "バックアップ書き出しに失敗しました", detail: error.localizedDescription)
                }
            }
            .fileImporter(
                isPresented: $showingBackupImporter,
                allowedContentTypes: [.zip],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        pendingRestoreURL = BackupRestoreSelection(url: url)
                    }
                case .failure(let error):
                    backupMessage = BackupMessage(title: "バックアップを開けませんでした", detail: error.localizedDescription)
                }
            }
            .sheet(isPresented: $showingPDFShareSheet) {
                if let pdfShareURL {
                    ShareSheet(activityItems: [pdfShareURL])
                }
            }
            .confirmationDialog(
                "バックアップから上書き復元しますか？",
                isPresented: restoreConfirmationBinding,
                titleVisibility: .visible
            ) {
                Button("上書き復元", role: .destructive) {
                    guard let url = pendingRestoreURL?.url else { return }
                    pendingRestoreURL = nil
                    Task { await restoreBackup(from: url) }
                }
                Button("キャンセル", role: .cancel) {
                    pendingRestoreURL = nil
                }
            } message: {
                Text("現在のレシピと画像をバックアップ内容で置き換えます。")
            }
            .alert(item: $backupMessage) { message in
                Alert(
                    title: Text(message.title),
                    message: Text(message.detail),
                    dismissButton: .default(Text("OK"))
                )
            }
            .sheet(isPresented: $showingImport) {
                ImportRecipeView(initialURLText: importURLText)
            }
            .onOpenURL { url in
                guard let value = URLNormalizer.importURLValue(from: url) else { return }
                importURLText = value
                showingImport = true
            }
            .overlay {
                if recipes.isEmpty {
                    ContentUnavailableView(
                        "まだレシピがありません",
                        systemImage: "fork.knife.circle",
                        description: Text("右上の＋からURLを入れて、写真つきで保存します。")
                    )
                } else if visibleRecipes.isEmpty {
                    ContentUnavailableView(
                        "該当するレシピがありません",
                        systemImage: "magnifyingglass",
                        description: Text("検索語やフィルタを変更してください。")
                    )
                }
            }
            .overlay {
                if isRunningBackupTask {
                    ProgressView()
                        .padding(22)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    private var backgroundView: some View {
        LinearGradient(
            colors: [
                RecipePalette.tomato.opacity(0.10),
                Color(.systemBackground),
                RecipePalette.basil.opacity(0.07)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recipe Clipper")
                .font(.system(size: 34, weight: .bold, design: .serif))
                .foregroundStyle(
                    LinearGradient(
                        colors: [RecipePalette.tomato, RecipePalette.ember],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            HStack(spacing: 10) {
                Label("\(recipes.count)品", systemImage: "book.pages")
                Label("\(totalCookCount)回作った", systemImage: "frying.pan")
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .padding(.top, 6)
        .padding(.horizontal, 16)
    }

    private var chipBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(RecipeFilter.allCases) { filter in
                        ChipButton(
                            title: filter.title,
                            isSelected: selectedFilter == filter,
                            selectedColors: [RecipePalette.tomato, RecipePalette.ember]
                        ) {
                            selectedFilter = filter
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }

            if !allTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(displayTags, id: \.self) { tag in
                            ChipButton(
                                title: "# \(tag)",
                                isSelected: selectedTag == tag,
                                selectedColors: [RecipePalette.basil, RecipePalette.leafLight]
                            ) {
                                selectedTag = selectedTag == tag ? nil : tag
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var displayTags: [String] {
        guard let selectedTag, !allTags.contains(selectedTag) else { return allTags }
        return [selectedTag] + allTags
    }

    @ViewBuilder
    private var cardsBlock: some View {
        if let featured = visibleRecipes.first {
            NavigationLink {
                RecipeDetailView(recipe: featured)
            } label: {
                FeaturedRecipeCard(recipe: featured)
            }
            .buttonStyle(CardPressStyle())
            .contextMenu { cardMenu(for: featured) }
            .padding(.horizontal, 16)
        }

        let rest = Array(visibleRecipes.dropFirst())
        if !rest.isEmpty {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                spacing: 14
            ) {
                ForEach(rest) { recipe in
                    NavigationLink {
                        RecipeDetailView(recipe: recipe)
                    } label: {
                        GridRecipeCard(recipe: recipe)
                    }
                    .buttonStyle(CardPressStyle())
                    .contextMenu { cardMenu(for: recipe) }
                    .scrollTransition { content, phase in
                        content
                            .opacity(phase.isIdentity ? 1 : 0.55)
                            .scaleEffect(phase.isIdentity ? 1 : 0.94)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private func cardMenu(for recipe: Recipe) -> some View {
        Button {
            recipe.isFavorite.toggle()
            try? modelContext.save()
        } label: {
            Label(
                recipe.isFavorite ? "お気に入りを外す" : "お気に入りに追加",
                systemImage: recipe.isFavorite ? "heart.slash" : "heart"
            )
        }

        Button(role: .destructive) {
            delete(recipe)
        } label: {
            Label("削除", systemImage: "trash")
        }
    }

    private var defaultBackupFileName: String {
        let dateText = Date().formatted(.iso8601.year().month().day())
        return "RecipeClipper-Backup-\(dateText).zip"
    }

    private var restoreConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingRestoreURL != nil },
            set: { isPresented in
                if !isPresented {
                    pendingRestoreURL = nil
                }
            }
        )
    }

    @MainActor
    private func exportBackup() async {
        isRunningBackupTask = true
        defer { isRunningBackupTask = false }

        do {
            let data = try BackupService.makeArchiveData(from: recipes)
            backupDocument = RecipeBackupDocument(data: data)
            showingBackupExporter = true
        } catch {
            backupMessage = BackupMessage(title: "バックアップ作成に失敗しました", detail: error.localizedDescription)
        }
    }

    @MainActor
    private func exportAllRecipesPDF() async {
        guard !recipes.isEmpty else {
            backupMessage = BackupMessage(title: "書き出すレシピがありません。", detail: "")
            return
        }

        isRunningBackupTask = true
        defer { isRunningBackupTask = false }

        do {
            pdfShareURL = try RecipePDFExporter().exportAll(recipes: recipes)
            showingPDFShareSheet = true
        } catch {
            backupMessage = BackupMessage(title: "PDFの作成に失敗しました。", detail: error.localizedDescription)
        }
    }

    @MainActor
    private func restoreBackup(from url: URL) async {
        isRunningBackupTask = true
        defer { isRunningBackupTask = false }

        do {
            let count = try BackupService.restore(from: url, modelContext: modelContext)
            backupMessage = BackupMessage(title: "復元しました", detail: "\(count)件のレシピを復元しました。")
        } catch {
            backupMessage = BackupMessage(title: "復元に失敗しました", detail: error.localizedDescription)
        }
    }

    private func matchesSelectedTag(_ recipe: Recipe) -> Bool {
        guard let selectedTag else { return true }
        return recipe.tags.contains { $0.caseInsensitiveCompare(selectedTag) == .orderedSame }
    }

    private func matchesSearch(_ recipe: Recipe) -> Bool {
        let words = searchText
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !words.isEmpty else { return true }
        let target = recipe.searchableText
        return words.allSatisfy { target.contains($0) }
    }

    private func delete(_ recipe: Recipe) {
        modelContext.delete(recipe)
        try? modelContext.save()
    }
}

enum RecipePalette {
    static let tomato = Color(red: 0.86, green: 0.25, blue: 0.16)
    static let ember = Color(red: 0.95, green: 0.48, blue: 0.22)
    static let basil = Color(red: 0.15, green: 0.44, blue: 0.33)
    static let leafLight = Color(red: 0.35, green: 0.62, blue: 0.42)
    static let cream = Color(red: 1.00, green: 0.96, blue: 0.88)
}

private struct BackupMessage: Identifiable {
    let id = UUID()
    var title: String
    var detail: String
}

private struct BackupRestoreSelection: Identifiable {
    let id = UUID()
    var url: URL
}

private struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct ChipButton: View {
    let title: String
    let isSelected: Bool
    let selectedColors: [Color]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .foregroundStyle(isSelected ? .white : .primary)
                .background {
                    if isSelected {
                        Capsule().fill(
                            LinearGradient(
                                colors: selectedColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    } else {
                        Capsule().fill(.ultraThinMaterial)
                    }
                }
                .overlay {
                    if !isSelected {
                        Capsule().strokeBorder(.quaternary, lineWidth: 1)
                    }
                }
                .shadow(
                    color: isSelected ? selectedColors[0].opacity(0.35) : .clear,
                    radius: 6,
                    y: 3
                )
        }
        .buttonStyle(.plain)
    }
}

private struct CardImage: View {
    let fileName: String?
    var placeholderIconSize: CGFloat = 34

    var body: some View {
        Color.clear
            .overlay {
                if let image = ImageStore.uiImage(for: fileName) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        LinearGradient(
                            colors: [RecipePalette.cream, RecipePalette.ember.opacity(0.35)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        Image(systemName: "fork.knife")
                            .font(.system(size: placeholderIconSize, weight: .light))
                            .foregroundStyle(RecipePalette.tomato.opacity(0.55))
                    }
                }
            }
            .clipped()
            // scaledToFillの画像は枠外まではみ出しており、clippedは見た目しか
            // 切り抜かないため、タッチ判定ごと無効化して枠外のタップ吸収を防ぐ
            .allowsHitTesting(false)
    }
}

private struct FavoriteBadge: View {
    var body: some View {
        Image(systemName: "heart.fill")
            .font(.caption)
            .foregroundStyle(.pink)
            .padding(7)
            .background(.ultraThinMaterial, in: Circle())
    }
}

private struct FeaturedRecipeCard: View {
    let recipe: Recipe

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CardImage(fileName: recipe.localImageFileName, placeholderIconSize: 48)
                .frame(height: 230)

            LinearGradient(
                colors: [.black.opacity(0.78), .black.opacity(0.25), .clear],
                startPoint: .bottom,
                endPoint: .center
            )

            VStack(alignment: .leading, spacing: 7) {
                Text("PICK UP")
                    .font(.system(size: 11, weight: .heavy))
                    .kerning(2.5)
                    .foregroundStyle(RecipePalette.ember)

                HStack(spacing: 6) {
                    Text(recipe.sourceKind.displayName)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(RecipePalette.tomato, in: Capsule())
                        .foregroundStyle(.white)

                    if let firstTag = recipe.tags.first {
                        Text("# \(firstTag)")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(.ultraThinMaterial, in: Capsule())
                            .foregroundStyle(.white)
                    }
                }

                Text(recipe.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 8) {
                    if recipe.rating > 0 {
                        Text(RatingStars.text(for: recipe.rating))
                            .foregroundStyle(.yellow)
                    }
                    if let lastCookedAt = recipe.lastCookedAt {
                        Text("作った: \(lastCookedAt.formatted(date: .numeric, time: .omitted))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
            }
            .padding(16)
        }
        .frame(height: 230)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(alignment: .topTrailing) {
            if recipe.isFavorite {
                FavoriteBadge()
                    .padding(10)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
    }
}

private struct GridRecipeCard: View {
    let recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardImage(fileName: recipe.localImageFileName)
                .frame(height: 118)
                .overlay(alignment: .topTrailing) {
                    if recipe.isFavorite {
                        FavoriteBadge()
                            .padding(7)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if recipe.wantsRemake {
                        Image(systemName: "bookmark.fill")
                            .font(.caption)
                            .foregroundStyle(RecipePalette.leafLight)
                            .padding(7)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding(7)
                    }
                }

            VStack(alignment: .leading, spacing: 5) {
                Text(recipe.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 38, alignment: .top)

                HStack(spacing: 5) {
                    if recipe.rating > 0 {
                        Text(RatingStars.text(for: recipe.rating))
                            .foregroundStyle(.orange)
                    } else {
                        Text(recipe.sourceKind.displayName)
                    }
                    Spacer(minLength: 0)
                    if !recipe.cookLogs.isEmpty {
                        Label("\(recipe.cookLogs.count)", systemImage: "frying.pan")
                            .labelStyle(.titleAndIcon)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                if !recipe.tags.isEmpty {
                    Text(recipe.tags.prefix(3).map { "#\($0)" }.joined(separator: " "))
                        .font(.caption2)
                        .foregroundStyle(RecipePalette.basil)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.10), radius: 8, y: 4)
    }
}

private enum RecipeFilter: String, CaseIterable, Identifiable {
    case all
    case favorite
    case cooked
    case notCooked
    case hasImage
    case instagram
    case cookpad
    case youtube
    case web
    case ratingFourPlus
    case wantsRemake

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "すべて"
        case .favorite: "お気に入り"
        case .cooked: "作ったことあり"
        case .notCooked: "まだ作ってない"
        case .hasImage: "画像あり"
        case .instagram: "Instagram"
        case .cookpad: "Cookpad"
        case .youtube: "YouTube"
        case .web: "Web"
        case .ratingFourPlus: "評価4以上"
        case .wantsRemake: "また作りたい"
        }
    }

    func matches(_ recipe: Recipe) -> Bool {
        switch self {
        case .all: true
        case .favorite: recipe.isFavorite
        case .cooked: !recipe.cookLogs.isEmpty
        case .notCooked: recipe.cookLogs.isEmpty
        case .hasImage: recipe.hasImage
        case .instagram: recipe.sourceKind == .instagram
        case .cookpad: recipe.sourceKind == .cookpad
        case .youtube: recipe.sourceKind == .youtube
        case .web: recipe.sourceKind == .web
        case .ratingFourPlus: recipe.rating >= 4
        case .wantsRemake: recipe.wantsRemake
        }
    }
}

private enum RecipeSort: String, CaseIterable, Identifiable {
    case recentlyAdded
    case recentlyUpdated
    case recentlyCooked
    case highRating
    case title

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recentlyAdded: "最近追加"
        case .recentlyUpdated: "最近更新"
        case .recentlyCooked: "最近作った"
        case .highRating: "評価が高い"
        case .title: "タイトル順"
        }
    }

    func areInIncreasingOrder(_ lhs: Recipe, _ rhs: Recipe) -> Bool {
        switch self {
        case .recentlyAdded:
            lhs.createdAt > rhs.createdAt
        case .recentlyUpdated:
            lhs.updatedAt > rhs.updatedAt
        case .recentlyCooked:
            (lhs.lastCookedAt ?? .distantPast) > (rhs.lastCookedAt ?? .distantPast)
        case .highRating:
            lhs.rating == rhs.rating ? lhs.updatedAt > rhs.updatedAt : lhs.rating > rhs.rating
        case .title:
            lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }
}
