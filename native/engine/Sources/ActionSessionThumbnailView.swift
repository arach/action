import AppKit
import SwiftUI

struct ActionSessionThumbnailView: View {
    let session: ActionSessionSummary

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

            Text(caption)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(StageHUDTheme.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(StageHUDTheme.cardFill.opacity(0.92))
                .clipShape(ActionChamferedShape(cornerCut: 4))
                .padding(8)
        }
        .frame(width: 150, height: 94)
        .background(
            ActionChamferedShape(cornerCut: 6)
                .fill(StageHUDTheme.appBackground)
        )
        .overlay(
            ActionChamferedShape(cornerCut: 6)
                .stroke(StageHUDTheme.cardBorder, lineWidth: 1)
        )
        .task(id: previewURL) {
            loadImage()
        }
    }

    private var thumbnailPlaceholder: some View {
        ZStack {
            StageHUDTheme.appBackground

            VStack(spacing: 8) {
                Image(systemName: "film.stack")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(StageHUDTheme.textMuted)
                Text(session.actualResult)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
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
