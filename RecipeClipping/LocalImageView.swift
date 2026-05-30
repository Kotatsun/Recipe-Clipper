import SwiftUI

struct LocalImageView: View {
    let fileName: String?
    var cornerRadius: CGFloat = 12
    var contentMode: ContentMode = .fill

    var body: some View {
        Group {
            if let image = ImageStore.uiImage(for: fileName) {
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
