import Foundation
import LinkPresentation
import UIKit
import UniformTypeIdentifiers

final class RecipeImportService {
    enum ImportError: LocalizedError {
        case invalidURL
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "URLとして解釈できませんでした。https:// から始まるURLを入力してください。"
            case .emptyResponse:
                return "ページからタイトルや画像を取得できませんでした。"
            }
        }
    }

    func importRecipe(from rawText: String) async throws -> ImportedRecipe {
        let url = try normalizeURL(rawText)
        let host = url.host(percentEncoded: false) ?? ""

        var result = ImportedRecipe(
            title: host.isEmpty ? url.absoluteString : host,
            summary: "",
            sourceURL: url,
            sourceHost: host,
            sourceImageURL: nil,
            imageData: nil
        )

        if let linkMetadata = try? await fetchLinkPresentationMetadata(for: url) {
            if let title = linkMetadata.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                result.title = title
            }
            if let canonical = linkMetadata.url ?? linkMetadata.originalURL {
                result.sourceURL = canonical
            }
            if let imageData = await loadImageData(from: linkMetadata.imageProvider) {
                result.imageData = imageData
            } else if let imageData = await loadImageData(from: linkMetadata.iconProvider) {
                result.imageData = imageData
            }
        }

        if let htmlMetadata = try? await fetchHTMLMetadata(for: url) {
            if result.title == host || result.title.isEmpty {
                result.title = htmlMetadata.title ?? result.title
            }
            if result.summary.isEmpty {
                result.summary = htmlMetadata.description ?? ""
            }
            if result.sourceImageURL == nil {
                result.sourceImageURL = htmlMetadata.imageURL
            }
            if let imageURL = htmlMetadata.imageURL, result.imageData == nil {
                result.imageData = try? await downloadImageData(from: imageURL, referer: url)
            }
        }

        if result.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && result.imageData == nil {
            throw ImportError.emptyResponse
        }

        return result
    }

    private func normalizeURL(_ rawText: String) throws -> URL {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImportError.invalidURL }

        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        if let url = URL(string: "https://\(trimmed)") {
            return url
        }
        throw ImportError.invalidURL
    }

    private func fetchLinkPresentationMetadata(for url: URL) async throws -> LPLinkMetadata {
        try await withCheckedThrowingContinuation { continuation in
            let provider = LPMetadataProvider()
            provider.timeout = 12
            provider.startFetchingMetadata(for: url) { metadata, error in
                if let metadata {
                    continuation.resume(returning: metadata)
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(throwing: ImportError.emptyResponse)
                }
            }
        }
    }

    private func loadImageData(from provider: NSItemProvider?) async -> Data? {
        guard let provider else { return nil }

        if provider.canLoadObject(ofClass: UIImage.self) {
            if let image = try? await provider.loadUIImage(), let data = image.jpegData(compressionQuality: 0.9) {
                return data
            }
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            return try? await provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier)
        }

        return nil
    }

    private func fetchHTMLMetadata(for url: URL) async throws -> HTMLMetadata {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("ja,en-US;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<400).contains(http.statusCode) {
            throw ImportError.emptyResponse
        }
        guard let html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .shiftJIS)
            ?? String(data: data, encoding: .isoLatin1) else {
            throw ImportError.emptyResponse
        }
        return HTMLMetadataParser.parse(html: html, baseURL: url)
    }

    private func downloadImageData(from imageURL: URL, referer: URL) async throws -> Data {
        var request = URLRequest(url: imageURL)
        request.timeoutInterval = 20
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue("image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<400).contains(http.statusCode) {
            throw ImportError.emptyResponse
        }
        return data
    }
}

private extension NSItemProvider {
    func loadUIImage() async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            _ = loadObject(ofClass: UIImage.self) { object, error in
                if let image = object as? UIImage {
                    continuation.resume(returning: image)
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(throwing: RecipeImportService.ImportError.emptyResponse)
                }
            }
        }
    }

    func loadDataRepresentation(forTypeIdentifier typeIdentifier: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let data {
                    continuation.resume(returning: data)
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(throwing: RecipeImportService.ImportError.emptyResponse)
                }
            }
        }
    }
}
