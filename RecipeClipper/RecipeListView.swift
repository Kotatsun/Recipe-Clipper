import SwiftUI
import SwiftData

struct RecipeListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recipe.updatedAt, order: .reverse) private var recipes: [Recipe]

    @State private var showingImport = false
    @State private var searchText = ""

    private var filteredRecipes: [Recipe] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return recipes }
        return recipes.filter { recipe in
            recipe.title.lowercased().contains(query)
            || recipe.summary.lowercased().contains(query)
            || recipe.notes.lowercased().contains(query)
            || recipe.tagsText.lowercased().contains(query)
            || recipe.sourceHost.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredRecipes) { recipe in
                    NavigationLink {
                        RecipeDetailView(recipe: recipe)
                    } label: {
                        RecipeRow(recipe: recipe)
                    }
                }
                .onDelete(perform: deleteRecipes)
            }
            .navigationTitle("Recipe Clipper")
            .searchable(text: $searchText, prompt: "料理名・タグ・メモで検索")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingImport = true
                    } label: {
                        Label("URLから追加", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingImport) {
                ImportRecipeView()
            }
            .overlay {
                if recipes.isEmpty {
                    ContentUnavailableView(
                        "まだレシピがありません",
                        systemImage: "fork.knife.circle",
                        description: Text("右上の＋からURLを入れて、写真つきで保存します。")
                    )
                }
            }
        }
    }

    private func deleteRecipes(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(filteredRecipes[index])
        }
        try? modelContext.save()
    }
}

private struct RecipeRow: View {
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 12) {
            LocalImageView(fileName: recipe.localImageFileName)
                .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title)
                    .font(.headline)
                    .lineLimit(2)
                if !recipe.sourceHost.isEmpty {
                    Text(recipe.sourceHost)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !recipe.tags.isEmpty {
                    Text(recipe.tags.joined(separator: " / "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
