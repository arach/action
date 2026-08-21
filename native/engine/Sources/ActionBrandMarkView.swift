import ActionCore
import SwiftUI

/// The tile the mark sits on — the same continuous-corner rounded rect the app
/// icon uses, so the chip in a header and the icon in the Dock are one mark.
struct ActionBrandTileShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(ActionBrandMark.tilePath(in: rect))
    }
}

/// The A itself, placed inside a tile the way the app icon places it — hand it
/// the tile's bounds and it works out its own inset.
struct ActionBrandLetterShape: Shape {
    func path(in rect: CGRect) -> Path {
        let mark = ActionBrandMark.markRect(inTile: rect, yAxis: .down)
        return Path(ActionBrandMark.outerPath(in: mark, yAxis: .down))
    }
}

/// The counter: the play triangle, in the same tile-relative placement.
struct ActionBrandCounterShape: Shape {
    func path(in rect: CGRect) -> Path {
        let mark = ActionBrandMark.markRect(inTile: rect, yAxis: .down)
        return Path(ActionBrandMark.counterPath(in: mark, yAxis: .down))
    }
}

/// Action's brand chip: the app icon, drawn live.
///
/// Same paper field, graphite letterform and coral play triangle the `.icns`
/// carries, so the chip in a header and the icon in the Dock are one mark. It
/// reads theme tokens rather than `ActionBrandMark`'s baked colours, so it
/// follows a theme switch — which the icon on disk cannot, and that is the one
/// place the two are allowed to drift.
struct ActionBrandTile: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            ActionBrandTileShape()
                .fill(StageHUDTheme.hudPaper)
            ActionBrandLetterShape()
                .fill(StageHUDTheme.hudInk)
            ActionBrandCounterShape()
                .fill(StageHUDTheme.hudCoral)
        }
        .frame(width: size, height: size)
        .overlay(
            ActionBrandTileShape()
                .stroke(StageHUDTheme.hudInk.opacity(0.10), lineWidth: 1)
        )
        .accessibilityHidden(true)
    }
}
