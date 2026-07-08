import Foundation
import ImageIO
import UIKit

struct ImageStore {
    enum ImageStoreError: Error {
        case cannotCreateJPEG
    }

    /// 保存時にこれより長辺が大きい画像はJPEGへ再圧縮する(ストア・バックアップの肥大防止)
    private static let savedImageMaxPixelLength: CGFloat = 2048

    private static let thumbnailCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 300
        // 1200pxサムネイルは1枚数MBになるため、件数だけでなくメモリ量でも制限する
        cache.totalCostLimit = 128 * 1024 * 1024
        return cache
    }()

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
        if let downsampled = downsampledJPEGData(from: data, maxPixelLength: savedImageMaxPixelLength) {
            return try write(data: downsampled, fileExtension: "jpg")
        }
        let ext = preferredExtension.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return try write(data: data, fileExtension: ext.isEmpty ? "jpg" : ext)
    }

    @discardableResult
    static func save(uiImage: UIImage, compressionQuality: CGFloat = 0.88) throws -> String {
        guard let data = uiImage.jpegData(compressionQuality: compressionQuality) else {
            throw ImageStoreError.cannotCreateJPEG
        }
        return try save(data: data, preferredExtension: "jpg")
    }

    static func delete(fileName: String?) {
        guard let url = url(for: fileName) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func url(for fileName: String?) -> URL? {
        guard let fileName, !fileName.isEmpty else { return nil }
        return directoryURL.appendingPathComponent(fileName)
    }

    /// 一覧・詳細表示用の縮小画像。ImageIOでフル解像度をデコードせずに生成し、キャッシュする。
    /// 画像ファイル名はUUIDで不変のため、キャッシュが古くなることはない。
    static func thumbnail(for fileName: String?, maxPixelLength: CGFloat) -> UIImage? {
        guard let fileName, !fileName.isEmpty else { return nil }
        let key = "\(fileName)#\(Int(maxPixelLength))" as NSString
        if let cached = thumbnailCache.object(forKey: key) {
            return cached
        }
        guard let url = url(for: fileName),
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions(maxPixelLength: maxPixelLength)) else {
            return nil
        }
        let image = UIImage(cgImage: cgImage)
        thumbnailCache.setObject(image, forKey: key, cost: cgImage.bytesPerRow * cgImage.height)
        return image
    }

    private static func write(data: Data, fileExtension: String) throws -> String {
        let fileName = "\(UUID().uuidString).\(fileExtension)"
        let url = directoryURL.appendingPathComponent(fileName)
        try data.write(to: url, options: [.atomic])
        return fileName
    }

    /// 長辺がmaxPixelLengthを超える画像だけ縮小してJPEG化する。
    /// 小さい画像やデコードできないデータはnilを返し、元データのまま保存させる
    private static func downsampledJPEGData(from data: Data, maxPixelLength: CGFloat) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat,
              max(width, height) > maxPixelLength,
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions(maxPixelLength: maxPixelLength)) else {
            return nil
        }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.85)
    }

    private static func thumbnailOptions(maxPixelLength: CGFloat) -> CFDictionary {
        [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelLength
        ] as CFDictionary
    }
}
