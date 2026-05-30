import SwiftUI
import SwiftData
import PhotosUI

struct RecipeDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var recipe: Recipe

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var cookMemo = ""
    @State private var showingAddCookLog = false

    var body: some View {
        Form {
            Section {
                LocalImageView(fileName: recipe.localImageFileName)
                    .frame(height: 240)
                    .listRowInsets(EdgeInsets())
            }

            Section("概要") {
                TextField("タイトル", text: $recipe.title)
                if !recipe.summary.isEmpty {
                    Text(recipe.summary)
                }
                TextField("タグ", text: $recipe.tagsText)
            }

            Section("出典") {
                if let url = recipe.sourceURL {
                    Link(recipe.sourceURLString, destination: url)
                        .lineLimit(2)
                }
                if let imageURL = recipe.sourceImageURL {
                    Link("取得画像URL", destination: imageURL)
                }
            }

            Section("自分メモ") {
                TextEditor(text: $recipe.notes)
                    .frame(minHeight: 90)
            }

            Section("作った記録") {
                Button {
                    showingAddCookLog = true
                } label: {
                    Label("作った記録を追加", systemImage: "camera")
                }

                ForEach(recipe.cookLogs.sorted(by: { $0.cookedAt > $1.cookedAt })) { log in
                    CookLogRow(log: log)
                }
                .onDelete(perform: deleteCookLogs)
            }
        }
        .navigationTitle(recipe.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddCookLog) {
            AddCookLogView(recipe: recipe)
        }
        .onDisappear {
            recipe.updatedAt = Date()
            try? modelContext.save()
        }
    }

    private func deleteCookLogs(offsets: IndexSet) {
        let sortedLogs = recipe.cookLogs.sorted(by: { $0.cookedAt > $1.cookedAt })
        for index in offsets {
            modelContext.delete(sortedLogs[index])
        }
        try? modelContext.save()
    }
}

private struct CookLogRow: View {
    let log: CookLog

    var body: some View {
        HStack(spacing: 12) {
            LocalImageView(fileName: log.localImageFileName, cornerRadius: 10)
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(log.cookedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline.weight(.semibold))
                if !log.memo.isEmpty {
                    Text(log.memo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
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
    @State private var cookedAt = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("写真") {
                    if let selectedImageData, let uiImage = UIImage(data: selectedImageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 220)
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
                    TextField("味の調整、次回の改善など", text: $memo, axis: .vertical)
                        .lineLimit(3...8)
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
        let log = CookLog(cookedAt: cookedAt, memo: memo, localImageFileName: fileName, recipe: recipe)
        modelContext.insert(log)
        recipe.updatedAt = Date()
        try? modelContext.save()
        dismiss()
    }
}
