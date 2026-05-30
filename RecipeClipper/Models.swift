import Foundation
import SwiftData

@Model
final class Recipe {
    var id: UUID
    var title: String
    var summary: String
    var sourceURLString: String
    var sourceHost: String
    var sourceImageURLString: String?
    var localImageFileName: String?
    var notes: String
    var tagsText: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \CookLog.recipe)
    var cookLogs: [CookLog]

    init(
        title: String,
        summary: String = "",
        sourceURLString: String,
        sourceHost: String = "",
        sourceImageURLString: String? = nil,
        localImageFileName: String? = nil,
        notes: String = "",
        tagsText: String = ""
    ) {
        self.id = UUID()
        self.title = title
        self.summary = summary
        self.sourceURLString = sourceURLString
        self.sourceHost = sourceHost
        self.sourceImageURLString = sourceImageURLString
        self.localImageFileName = localImageFileName
        self.notes = notes
        self.tagsText = tagsText
        self.createdAt = Date()
        self.updatedAt = Date()
        self.cookLogs = []
    }

    var sourceURL: URL? { URL(string: sourceURLString) }
    var sourceImageURL: URL? { sourceImageURLString.flatMap(URL.init(string:)) }
    var tags: [String] {
        tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

@Model
final class CookLog {
    var id: UUID
    var cookedAt: Date
    var memo: String
    var localImageFileName: String?
    var rating: Int
    var recipe: Recipe?

    init(cookedAt: Date = Date(), memo: String = "", localImageFileName: String? = nil, rating: Int = 0, recipe: Recipe? = nil) {
        self.id = UUID()
        self.cookedAt = cookedAt
        self.memo = memo
        self.localImageFileName = localImageFileName
        self.rating = rating
        self.recipe = recipe
    }
}
