import SwiftUI
import SwiftData

struct ImportRecipeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var urlText = ""
    @State private var tagsText = ""
    @State private var notes = ""
    @State private var draft: ImportedRecipe?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let service = RecipeImportService()

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
                            Text(isLoading ? "取得中" : "写真と概要を取得")
                        }
                    }
                    .disabled(isLoading || urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                                .scaledToFill()
                                .frame(height: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .listRowInsets(EdgeInsets())
                        } else {
                            ContentUnavailableView("画像なし", systemImage: "photo.badge.exclamationmark")
                        }

                        LabeledContent("タイトル", value: draft.title)
                        if !draft.summary.isEmpty {
                            Text(draft.summary)
                        }
                        if let imageURL = draft.sourceImageURL {
                            LabeledContent("画像URL", value: imageURL.absoluteString)
                        }
                    }

                    Section("自分用メモ") {
                        TextField("タグ: 鶏肉, 時短, 和食", text: $tagsText)
                        TextField("次回調整など", text: $notes, axis: .vertical)
                            .lineLimit(3...8)
                    }
                }
            }
            .navigationTitle("URLから追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(draft == nil)
                }
            }
        }
    }

    @MainActor
    private func fetch() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            draft = try await service.importRecipe(from: urlText)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func save() {
        guard let draft else { return }
        var imageFileName: String?
        if let data = draft.imageData {
            imageFileName = try? ImageStore.save(data: data)
        }

        let recipe = Recipe(
            title: draft.title,
            summary: draft.summary,
            sourceURLString: draft.sourceURL.absoluteString,
            sourceHost: draft.sourceHost,
            sourceImageURLString: draft.sourceImageURL?.absoluteString,
            localImageFileName: imageFileName,
            notes: notes,
            tagsText: tagsText
        )
        modelContext.insert(recipe)
        try? modelContext.save()
        dismiss()
    }
}
