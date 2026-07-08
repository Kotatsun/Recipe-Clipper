import SwiftUI

struct LocalImageView: View {
    let fileName: String?
    var cornerRadius: CGFloat = 12
    var contentMode: ContentMode = .fill
    /// 表示に必要な解像度の上限。フル解像度のデコードを避け、キャッシュも効かせる
    var maxPixelLength: CGFloat = 1400

    var body: some View {
        Group {
            if let image = ImageStore.thumbnail(for: fileName, maxPixelLength: maxPixelLength) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.secondary.opacity(0.12))
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
