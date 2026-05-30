import Foundation
import UIKit

struct ImageStore {
    enum ImageStoreError: Error {
        case cannotCreateJPEG
    }

    static var directoryURL: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("RecipeImages", isDirectory: true)
    }

    static func ensureDirectoryExists() throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    @discardableResult
    static func save(data: Data, preferredExtension: String = "jpg") throws -> String {
        try ensureDirectoryExists()
        let ext = preferredExtension.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let fileName = "\(UUID().uuidString).\(ext.isEmpty ? "jpg" : ext)"
        let url = directoryURL.appendingPathComponent(fileName)
        try data.write(to: url, options: [.atomic])
        return fileName
    }

    @discardableResult
    static func save(uiImage: UIImage, compressionQuality: CGFloat = 0.88) throws -> String {
        guard let data = uiImage.jpegData(compressionQuality: compressionQuality) else {
            throw ImageStoreError.cannotCreateJPEG
        }
        return try save(data: data, preferredExtension: "jpg")
    }

    static func url(for fileName: String?) -> URL? {
        guard let fileName, !fileName.isEmpty else { return nil }
        return directoryURL.appendingPathComponent(fileName)
    }

    static func uiImage(for fileName: String?) -> UIImage? {
        guard let url = url(for: fileName), let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}
