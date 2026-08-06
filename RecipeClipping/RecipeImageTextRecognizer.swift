import Foundation
import ImageIO
import Vision

/// スクリーンショットを外部へ送信せず、端末内のVisionで文字起こしする。
struct RecipeImageTextRecognizer: Sendable {
    enum RecognitionError: LocalizedError {
        case unreadableImage
        case noText

        var errorDescription: String? {
            switch self {
            case .unreadableImage:
                "画像を読み込めませんでした。別の画像を選んでください。"
            case .noText:
                "画像から文字を見つけられませんでした。"
            }
        }
    }

    nonisolated func recognizeText(in data: Data) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, [
                    kCGImageSourceShouldCache: false
                  ] as CFDictionary) else {
                throw RecognitionError.unreadableImage
            }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["ja-JP", "en-US"]
            request.automaticallyDetectsLanguage = true

            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let orientationValue = properties?[kCGImagePropertyOrientation] as? UInt32 ?? 1
            let orientation = CGImagePropertyOrientation(rawValue: orientationValue) ?? .up
            let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
            try handler.perform([request])

            let lines = (request.results ?? [])
                .sorted { lhs, rhs in
                    let verticalDistance = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
                    if verticalDistance < 0.018 {
                        return lhs.boundingBox.minX < rhs.boundingBox.minX
                    }
                    return lhs.boundingBox.midY > rhs.boundingBox.midY
                }
                .compactMap { $0.topCandidates(1).first?.string }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            guard !lines.isEmpty else {
                throw RecognitionError.noText
            }
            return lines.joined(separator: "\n")
        }.value
    }
}
