import SwiftUI

struct TagEditorView: View {
    @Binding var tagsText: String
    var suggestions: [String] = []

    @State private var input = ""

    private var tags: [String] {
        Recipe.normalizedTags(from: tagsText)
    }

    private var availableSuggestions: [String] {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return suggestions.filter { suggestion in
            let notAdded = !tags.contains { $0.caseInsensitiveCompare(suggestion) == .orderedSame }
            let matchesInput = trimmedInput.isEmpty
                || suggestion.localizedCaseInsensitiveContains(trimmedInput)
            return notAdded && matchesInput
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tags, id: \.self) { tag in
                            Button {
                                remove(tag)
                            } label: {
                                Label(tag, systemImage: "xmark.circle.fill")
                                    .labelStyle(.titleAndIcon)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }

            HStack {
                TextField("タグを追加", text: $input)
                    .textInputAutocapitalization(.never)
                    .onSubmit(addInput)
                Button {
                    addInput()
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !availableSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(availableSuggestions, id: \.self) { suggestion in
                            Button(suggestion) {
                                add(suggestion)
                                input = ""
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
        .onDisappear {
            tagsText = Recipe.normalizedTagsText(from: tagsText)
        }
    }

    private func addInput() {
        add(input)
        input = ""
    }

    private func add(_ rawTag: String) {
        let newTags = Recipe.normalizedTags(from: tagsText + "," + rawTag)
        tagsText = newTags.joined(separator: ", ")
    }

    private func remove(_ tag: String) {
        tagsText = tags
            .filter { $0 != tag }
            .joined(separator: ", ")
    }
}

enum RatingStars {
    static func text(for rating: Int) -> String {
        guard rating > 0 else { return "未評価" }
        return String(repeating: "★", count: max(0, min(5, rating)))
            + String(repeating: "☆", count: max(0, 5 - min(5, rating)))
    }
}

struct RatingPicker: View {
    @Binding var rating: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { value in
                Button {
                    rating = rating == value ? 0 : value
                } label: {
                    Image(systemName: value <= rating ? "star.fill" : "star")
                        .foregroundStyle(value <= rating ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("評価\(value)")
            }
        }
    }
}
