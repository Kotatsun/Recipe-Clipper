import Foundation

struct ImportedRecipe {
    var title: String
    var summary: String
    var sourceURL: URL
    var sourceHost: String
    var sourceImageURL: URL?
    var imageData: Data?
    var ingredientLines: [String] = []
    var instructionLines: [String] = []
    var extractedRawText: String = ""
    var rawImportedText: String = ""
    var rawImportedHTML: String = ""
    var importedTextSource: String = "none"
    var extractionConfidence: Double = 0.0
    var extractionWarnings: [String] = []
    var ingredientSource: String = "none"
    var instructionSource: String = "none"
    var importDiagnostics: RecipeImportDiagnostics?
}
