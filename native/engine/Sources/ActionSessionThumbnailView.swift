import AppKit
import SwiftUI

struct ActionSessionThumbnailView: View {
    let session: ActionSessionSummary
    /// Fixed width. Pass `nil` to fill the parent width.
    var width: CGFloat? = 150
    var height: CGFloat = 94
    var showCaption: Bool = true
    var cornerRadius: CGFloat = 10
    var showBorder: Bool = true

    @State private var image: NSImage?

    private var previewURL: URL? {
        session.resultScreenshotURL ?? session.stageScreenshotURL
    }

    private var caption: String {
        if session.resultScreenshotURL != nil {
            return "Result"
        }
        if session.stageScreenshotURL != nil {
            return "Stage"
        }
        return "Video"
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    thumbnailPlaceholder
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            if showCaption {
                Text(caption)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(StageHUDTheme.textPrimary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                    .padding(8)
            }
        }
        .frame(width: width, height: height)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .background(StageHUDTheme.appBackground)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            if showBorder {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(StageHUDTheme.cardBorder, lineWidth: 1)
            }
        }
        .task(id: previewURL) {
            loadImage()
        }
    }

    private var thumbnailPlaceholder: some View {
        ZStack {
            StageHUDTheme.appBackground

            VStack(spacing: 8) {
                Image(systemName: "film")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(StageHUDTheme.textMuted)
                Text(session.actualResult)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(StageHUDTheme.textSecondary)
            }
        }
    }

    private func loadImage() {
        guard let previewURL else {
            image = nil
            return
        }
        image = NSImage(contentsOf: previewURL)
    }
}
