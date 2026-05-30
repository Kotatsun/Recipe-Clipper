import Foundation

struct ImportedRecipe {
    var title: String
    var summary: String
    var sourceURL: URL
    var sourceHost: String
    var sourceImageURL: URL?
    var imageData: Data?

    var hasImage: Bool { imageData != nil }
}
