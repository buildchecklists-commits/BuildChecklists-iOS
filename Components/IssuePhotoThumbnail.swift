import SwiftUI
import UIKit

/// Lazy downsampled preview. Does not decode the full photo on the main thread.
struct IssuePhotoThumbnail: View {
    let path: String
    var side: CGFloat = 56

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if failed {
                Image(systemName: "photo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(width: side, height: side)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .task(id: path) {
            let loaded = await PhotoThumbnailLoader.load(path: path, maxPixelSize: side * 3)
            image = loaded
            failed = loaded == nil
        }
    }
}
