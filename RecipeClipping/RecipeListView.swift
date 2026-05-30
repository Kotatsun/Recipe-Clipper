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
    @State private var backupDocument: RecipeBackupDocument?
    @State private var showingBackupExporter = false
    @State private var showingBackupImporter = false
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
            .sorted(by: sort.areInIncreasingOrder)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    FilterChipRow(selectedFilter: $selectedFilter)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))

                ForEach(visibleRecipes) { recipe in
                    NavigationLink {
                        RecipeDetailView(recipe: recipe)
                    } label: {
                        RecipeRow(recipe: recipe)
                    }
                }
                .onDelete(perform: deleteRecipes)
            }
            .navigationTitle("Recipe Clipper")
            .searchable(text: $searchText, prompt: "料理名・タグ・材料・メモで検索")
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

    private func matchesSearch(_ recipe: Recipe) -> Bool {
        let words = searchText
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !words.isEmpty else { return true }
        let target = recipe.searchableText
        return words.allSatisfy { target.contains($0) }
    }

    private func deleteRecipes(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(visibleRecipes[index])
        }
        try? modelContext.save()
    }
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

private struct FilterChipRow: View {
    @Binding var selectedFilter: RecipeFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(RecipeFilter.allCases) { filter in
                    Button {
                        selectedFilter = filter
                    } label: {
                        Text(filter.title)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(selectedFilter == filter ? .accentColor : .secondary)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct RecipeRow: View {
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 12) {
            LocalImageView(fileName: recipe.localImageFileName, cornerRadius: 12, contentMode: .fill)
                .frame(width: 72, height: 72)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(recipe.title)
                        .font(.headline)
                        .lineLimit(2)
                    if recipe.isFavorite {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.pink)
                            .font(.caption)
                    }
                }

                HStack(spacing: 6) {
                    Text(recipe.sourceKind.displayName)
                    if recipe.rating > 0 {
                        Text(RatingStars.text(for: recipe.rating))
                    }
                    if let lastCookedAt = recipe.lastCookedAt {
                        Text("作った: \(lastCookedAt.formatted(date: .numeric, time: .omitted))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                if !recipe.tags.isEmpty {
                    Text(recipe.tags.joined(separator: " / "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if !recipe.sourceHost.isEmpty {
                    Text(recipe.sourceHost)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
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
