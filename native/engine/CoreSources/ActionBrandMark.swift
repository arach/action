import CoreGraphics
import Foundation

/// Action's mark: a capital A whose counter is cut as a right-pointing play
/// triangle. One shape carries both readings — the letter and the take.
///
/// The geometry lives here, in Core, because three places draw it and they must
/// not drift apart: the menu bar status item, the in-app brand tile, and the
/// `.icns` the build stamps into `Action.app`. Everything is expressed in a
/// 100 x 100 design box with **y pointing down**, then mapped onto whatever
/// rect the caller hands in, so the mark is resolution-independent.
///
/// The counter's back edge is deliberately vertical. A slanted back edge (one
/// parallel to the A's left leg, which is what a type designer would draw)
/// evens out the left stem but stops reading as a play button — the triangle
/// just looks like an ordinary counter. The vertical edge is what buys the
/// second reading, and it is worth the slightly heavier lower-left stem.
public enum ActionBrandMark {
    /// The design box every coordinate below is expressed in. y points down.
    public static let designBox = CGSize(width: 100, height: 100)

    /// Which way y runs in the space the caller is drawing into.
    ///
    /// CoreGraphics contexts and unflipped `NSImage` drawing put y at the
    /// bottom; SwiftUI and flipped AppKit views put it at the top. The mark is
    /// authored y-down, so getting this wrong renders the A upside down rather
    /// than failing loudly — hence an explicit argument instead of a default
    /// that silently suits one caller.
    public enum YAxis: Sendable {
        case up
        case down
    }

    /// The letterform's proportions. These were tuned by rendering, not derived:
    /// the counter is the tightest constraint, and stroke weights had to give
    /// way to it before the triangle read as a triangle at menu bar size.
    public struct Metrics: Sendable {
        /// Top edge of the flat apex, and the baseline the legs stand on.
        public var apexY: Double = 9
        public var footY: Double = 91
        /// The flat apex spans `apexL ... apexR`; the legs splay to `footOuter*`.
        public var apexL: Double = 39
        public var apexR: Double = 61
        public var footOuterL: Double = 2
        public var footOuterR: Double = 98
        /// Leg thickness, measured horizontally (so the perpendicular stroke is
        /// slightly lighter — about 16.4 at the default splay).
        public var legT: Double = 18
        /// Crossbar thickness, measured vertically. Matched by eye to `legT`'s
        /// perpendicular weight rather than to `legT` itself.
        public var crossbarT: Double = 15
        /// Top of the notch between the legs. The crossbar is the band from the
        /// counter's bottom down to here.
        public var notchY: Double = 71

        /// Counter (the play triangle).
        public var counterTop: Double = 29
        /// Horizontal clearance from the left leg's outer edge to the triangle's
        /// back edge, taken at `counterTop` — the tightest point.
        public var backGap: Double = 12
        /// Horizontal clearance from the triangle's tip to the right leg's outer
        /// edge. This is the thinnest part of the right leg, so it is the number
        /// to watch when making the triangle bigger.
        public var apexGap: Double = 13
        /// Where the tip sits between `counterTop` and the counter's bottom.
        /// Biased low: the right leg's outer edge moves right as it descends, so
        /// a lower tip gets more room without thinning the stroke.
        public var apexBias: Double = 0.6

        /// Corner softening. Small on purpose — past roughly 4 the triangle
        /// rounds into a blob and loses the play reading.
        public var outerRadius: Double = 2.5
        public var counterRadius: Double = 2.0

        public init() {}

        public var slopeL: Double { (footOuterL - apexL) / (footY - apexY) }
        public var slopeR: Double { (footOuterR - apexR) / (footY - apexY) }
        /// x of the left leg's outer edge at a given y.
        public func outerLeft(_ y: Double) -> Double { apexL + slopeL * (y - apexY) }
        /// x of the right leg's outer edge at a given y.
        public func outerRight(_ y: Double) -> Double { apexR + slopeR * (y - apexY) }
        public var counterBottom: Double { notchY - crossbarT }
    }

    public static let metrics = Metrics()

    /// The mark, scaled to fit `rect`. Fill it with the even-odd rule: the
    /// counter is a second subpath, not a separate shape.
    ///
    /// The two subpaths are wound in opposite directions, so a non-zero fill
    /// also produces the hole — but even-odd is what the drawing was checked
    /// against, and it survives anyone reordering the points later.
    public static func markPath(
        in rect: CGRect,
        yAxis: YAxis = .up,
        metrics m: Metrics = metrics
    ) -> CGPath {
        let path = CGMutablePath()
        path.addPath(outerPath(in: rect, yAxis: yAxis, metrics: m))
        path.addPath(counterPath(in: rect, yAxis: yAxis, metrics: m))
        return path
    }

    /// The A's silhouette alone, with no counter cut out of it. Draw this and
    /// `counterPath` separately when the play triangle carries its own colour
    /// rather than showing the surface behind the mark.
    public static func outerPath(
        in rect: CGRect,
        yAxis: YAxis = .up,
        metrics m: Metrics = metrics
    ) -> CGPath {
        let points: [CGPoint] = [
            CGPoint(x: m.apexL, y: m.apexY),
            CGPoint(x: m.apexR, y: m.apexY),
            CGPoint(x: m.outerRight(m.footY), y: m.footY),
            CGPoint(x: m.outerRight(m.footY) - m.legT, y: m.footY),
            CGPoint(x: m.outerRight(m.notchY) - m.legT, y: m.notchY),
            CGPoint(x: m.outerLeft(m.notchY) + m.legT, y: m.notchY),
            CGPoint(x: m.outerLeft(m.footY) + m.legT, y: m.footY),
            CGPoint(x: m.outerLeft(m.footY), y: m.footY),
        ]
        return place(roundedPolygon(points, radius: m.outerRadius), in: rect, yAxis: yAxis)
    }

    /// The counter: the play triangle.
    public static func counterPath(
        in rect: CGRect,
        yAxis: YAxis = .up,
        metrics m: Metrics = metrics
    ) -> CGPath {
        let top = m.counterTop
        let bottom = m.counterBottom
        let tipY = top + (bottom - top) * m.apexBias
        let backX = m.outerLeft(top) + m.backGap
        let points: [CGPoint] = [
            CGPoint(x: backX, y: top),
            CGPoint(x: backX, y: bottom),
            CGPoint(x: m.outerRight(tipY) - m.apexGap, y: tipY),
        ]
        return place(roundedPolygon(points, radius: m.counterRadius), in: rect, yAxis: yAxis)
    }

    /// Four capture-corner ticks — the crop marks that run through Action's
    /// landing art and its earlier mark explorations. They say what the app is
    /// about (framing a region and recording it) in a way a bare letter cannot.
    ///
    /// `reach` and `weight` are fractions of `rect`'s shorter side; `inset` is
    /// how far in from its edges the corners sit.
    public static func captureTicksPath(
        in rect: CGRect,
        inset: Double = 0.14,
        reach: Double = 0.11,
        weight: Double = 0.028
    ) -> CGPath {
        let side = Double(min(rect.width, rect.height))
        let d = side * inset, r = side * reach, w = side * weight
        let x0 = Double(rect.minX) + d, x1 = Double(rect.maxX) - d
        let y0 = Double(rect.minY) + d, y1 = Double(rect.maxY) - d
        let path = CGMutablePath()
        for (cx, cy, sx, sy) in [(x0, y0, 1.0, 1.0), (x1, y0, -1.0, 1.0),
                                 (x0, y1, 1.0, -1.0), (x1, y1, -1.0, -1.0)] {
            // One L per corner, drawn as two overlapping bars so the elbow is solid.
            path.addRect(CGRect(x: min(cx, cx + sx * r), y: min(cy, cy + sy * w),
                                width: r, height: w))
            path.addRect(CGRect(x: min(cx, cx + sx * w), y: min(cy, cy + sy * r),
                                width: w, height: r))
        }
        return path
    }

    private static func place(_ path: CGPath, in rect: CGRect, yAxis: YAxis) -> CGPath {
        var transform = designTransform(into: rect, yAxis: yAxis)
        return path.copy(using: &transform) ?? path
    }

    /// The rounded tile the mark sits on, as the app icon and the in-app brand
    /// chip both draw it: a rounded rect with macOS "continuous" corners.
    public static func tilePath(in rect: CGRect, cornerRatio: Double = tileCornerRatio) -> CGPath {
        continuousRoundedRect(
            rect,
            radius: Double(min(rect.width, rect.height)) * cornerRatio,
            n: tileCornerExponent
        )
    }

    // MARK: - Tile proportions

    /// How much of each edge the corner eats, as a fraction of the tile's side.
    /// Larger than the circular equivalent because a superellipse corner starts
    /// bending later, so it needs more run to land in the same place.
    public static let tileCornerRatio = 0.28
    /// Squareness of the corner. 2 is a circle; 5 sits where the system mask does.
    public static let tileCornerExponent = 5.0

    /// Apple's icon grid: the tile is 824 of a 1024 canvas, leaving the margin
    /// the system expects for shadow and for optical alignment in the Dock.
    public static let iconBodyInsetRatio = 100.0 / 1024.0
    /// The mark's share of the tile, and a small upward nudge — the A is
    /// bottom-heavy, so geometric centring reads as sitting too low.
    public static let iconMarkScale = 0.58
    public static let iconMarkOffsetY = -1.0

    /// Where the mark sits inside a tile: centred, scaled to `iconMarkScale`,
    /// nudged up because the A is bottom-heavy. Shared by the `.icns` renderer
    /// and the in-app chip so the two compositions cannot drift.
    public static func markRect(inTile tile: CGRect, yAxis: YAxis = .up) -> CGRect {
        let side = tile.width * CGFloat(iconMarkScale)
        // The nudge is authored in design space, where y points down, so it
        // adds in a y-down space and subtracts in a y-up one.
        let dy = tile.height * CGFloat(iconMarkOffsetY) / CGFloat(designBox.height)
        return CGRect(
            x: tile.midX - side / 2,
            y: tile.midY - side / 2 + (yAxis == .down ? dy : -dy),
            width: side,
            height: side
        )
    }

    /// The tile's rect inside a square icon canvas.
    public static func iconBodyRect(inCanvas canvas: CGRect) -> CGRect {
        let inset = Double(canvas.width) * iconBodyInsetRatio
        return canvas.insetBy(dx: CGFloat(inset), dy: CGFloat(inset))
    }

    // MARK: - Brand colours

    /// The `action` built-in theme's HUD coral and ink, baked in.
    ///
    /// Source of truth is `ActionThemeBuiltin.swift`. They are duplicated here
    /// because an `.icns` on disk cannot follow a theme the user switches at
    /// runtime — the app icon has to commit to one palette. Anything drawn
    /// *inside* the app should read `StageHUDTheme` instead of these.
    public static let coral = CGColor(red: 0.937, green: 0.416, blue: 0.278, alpha: 1)
    public static let coralHot = CGColor(red: 1.0, green: 0.49, blue: 0.32, alpha: 1)
    public static let ink = CGColor(red: 0.055, green: 0.071, blue: 0.074, alpha: 1)
    /// The landing system's canvas and its graphite, same values as the theme's
    /// `canvas` and `ink` in light appearance.
    public static let paper = CGColor(red: 0xF3 / 255, green: 0xEB / 255, blue: 0xDD / 255, alpha: 1)
    public static let graphite = CGColor(red: 0x20 / 255, green: 0x28 / 255, blue: 0x2B / 255, alpha: 1)
    /// The landing system's `--action-paper-shadow`, used only to give the tile
    /// a shallow ramp so it does not read as a flat sticker in the Dock.
    public static let paperShadow = CGColor(red: 0xDC / 255, green: 0xCF / 255, blue: 0xB9 / 255, alpha: 1)

    // MARK: - Geometry helpers

    /// Maps the 100 x 100 design box (y down) onto `rect` (y up, as CoreGraphics
    /// and SwiftUI both hand it to us), fitting the shorter side and centring.
    private static func designTransform(into rect: CGRect, yAxis: YAxis) -> CGAffineTransform {
        let scale = min(rect.width, rect.height) / CGFloat(designBox.width)
        let dx = rect.minX + (rect.width - CGFloat(designBox.width) * scale) / 2
        let dy = rect.minY + (rect.height - CGFloat(designBox.height) * scale) / 2
        switch yAxis {
        case .down:
            return CGAffineTransform(translationX: dx, y: dy).scaledBy(x: scale, y: scale)
        case .up:
            return CGAffineTransform(translationX: dx, y: dy + CGFloat(designBox.height) * scale)
                .scaledBy(x: scale, y: -scale)
        }
    }

    /// A closed polygon with every corner rounded to `radius`.
    ///
    /// Starts at the midpoint of the closing edge so that the first vertex gets
    /// an arc too — `addArc(tangent1End:tangent2End:)` rounds the corner it is
    /// aiming at, so beginning on a vertex would leave that one sharp.
    private static func roundedPolygon(_ points: [CGPoint], radius: Double) -> CGPath {
        let path = CGMutablePath()
        guard radius > 0, points.count > 2 else {
            path.addLines(between: points)
            path.closeSubpath()
            return path
        }
        let last = points[points.count - 1]
        path.move(to: CGPoint(x: (last.x + points[0].x) / 2, y: (last.y + points[0].y) / 2))
        for i in points.indices {
            path.addArc(
                tangent1End: points[i],
                tangent2End: points[(i + 1) % points.count],
                radius: CGFloat(radius)
            )
        }
        path.closeSubpath()
        return path
    }

    /// A rounded rect whose corners are superellipse quadrants rather than
    /// circular arcs — the continuous curvature macOS uses, where the corner
    /// eases into the straight edge instead of meeting it at a curvature jump.
    ///
    /// `radius` is how far the corner reaches along each edge, not a circle's
    /// radius; with `n` above 2 the corner is fuller than a circle of the same
    /// reach. Sampled rather than fitted with béziers: at icon sizes the
    /// difference is invisible and the arithmetic stays honest.
    private static func continuousRoundedRect(
        _ rect: CGRect,
        radius: Double,
        n: Double,
        samples: Int = 48
    ) -> CGPath {
        let path = CGMutablePath()
        let x0 = Double(rect.minX), y0 = Double(rect.minY)
        let x1 = Double(rect.maxX), y1 = Double(rect.maxY)
        let r = min(radius, min(x1 - x0, y1 - y0) / 2)
        let exponent = 2 / n

        func corner(_ cx: Double, _ cy: Double, _ sx: Double, _ sy: Double, reversed: Bool) {
            for i in 0...samples {
                let k = reversed ? samples - i : i
                let t = Double.pi / 2 * Double(k) / Double(samples)
                path.addLine(to: CGPoint(
                    x: cx + sx * r * pow(cos(t), exponent),
                    y: cy + sy * r * pow(sin(t), exponent)
                ))
            }
        }

        path.move(to: CGPoint(x: x0 + r, y: y0))
        path.addLine(to: CGPoint(x: x1 - r, y: y0))
        corner(x1 - r, y0 + r, 1, -1, reversed: true)
        path.addLine(to: CGPoint(x: x1, y: y1 - r))
        corner(x1 - r, y1 - r, 1, 1, reversed: false)
        path.addLine(to: CGPoint(x: x0 + r, y: y1))
        corner(x0 + r, y1 - r, -1, 1, reversed: true)
        path.addLine(to: CGPoint(x: x0, y: y0 + r))
        corner(x0 + r, y0 + r, -1, -1, reversed: false)
        path.closeSubpath()
        return path
    }
}
