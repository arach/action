import AppKit
import SwiftUI

/// Pure resize math for the launcher rail's label column.
///
/// Kept separate from the gesture so every width decision can be reasoned about
/// without simulating a drag. Two clamps matter and they are deliberately
/// different:
///
/// - **Preview** width may fall below the minimum, all the way to zero, so the
///   edge can visually travel toward the collapse threshold while dragging.
/// - **Committed** width always lands inside `min...max`, so whatever is stored
///   is a width the rail can actually re-expand to.
///
/// Ported from Hudson's `HudSidebarResizeGeometry` (`~/dev/hudson`), which Linea
/// uses; the contract is theirs, the numbers are tuned to Action's rail.
struct ActionSidebarResizeGeometry: Equatable {
    let minLabelWidth: CGFloat
    let maxLabelWidth: CGFloat
    /// Dragging left past this preview width collapses the rail.
    let collapseLabelWidth: CGFloat
    /// Horizontal travel before a drag counts as a resize rather than a click.
    let activationDistance: CGFloat

    /// How much a drag must favour horizontal travel before it counts. Without
    /// this, a vertical scroll that drifts sideways starts resizing the rail.
    private static let horizontalDominance: CGFloat = 1.5
    /// Collapsed, the rail is already at its floor, so any deliberate rightward
    /// pull should expand it — a full activation distance feels stuck.
    private static let compactActivationFloor: CGFloat = 2

    static let `default` = ActionSidebarResizeGeometry(
        minLabelWidth: 168,
        maxLabelWidth: 320,
        collapseLabelWidth: 128,
        activationDistance: 6
    )

    init(
        minLabelWidth: CGFloat,
        maxLabelWidth: CGFloat,
        collapseLabelWidth: CGFloat,
        activationDistance: CGFloat
    ) {
        let low = max(0, minLabelWidth)
        self.minLabelWidth = low
        // An inverted range would otherwise make `committedWidth` snap to the
        // maximum and strand the rail below its own minimum.
        self.maxLabelWidth = max(low, maxLabelWidth)
        self.collapseLabelWidth = max(0, collapseLabelWidth)
        self.activationDistance = max(0, activationDistance)
    }

    func committedWidth(_ width: CGFloat) -> CGFloat {
        min(maxLabelWidth, max(minLabelWidth, width))
    }

    func previewWidth(_ width: CGFloat) -> CGFloat {
        min(maxLabelWidth, max(0, width))
    }

    func activationThreshold(isCompact: Bool) -> CGFloat {
        isCompact ? max(Self.compactActivationFloor, activationDistance * 0.5) : activationDistance
    }

    func isResizeActivated(
        isCompact: Bool,
        horizontalDelta: CGFloat,
        verticalDelta: CGFloat
    ) -> Bool {
        guard abs(horizontalDelta) >= activationThreshold(isCompact: isCompact) else { return false }
        guard abs(horizontalDelta) > abs(verticalDelta) * Self.horizontalDominance else { return false }
        // From compact there is no narrower state to drag toward, so a leftward
        // pull is not a resize.
        if isCompact, horizontalDelta <= 0 { return false }
        return true
    }

    func isClick(
        isCompact: Bool,
        horizontalDelta: CGFloat,
        verticalDelta: CGFloat
    ) -> Bool {
        let threshold = activationThreshold(isCompact: isCompact)
        return abs(horizontalDelta) < threshold && abs(verticalDelta) < threshold
    }

    /// Compact drags start at zero so the labels grow out of the rail instead of
    /// snapping to their stored width the instant the drag activates.
    func dragStartWidth(isCompact: Bool, currentWidth: CGFloat) -> CGFloat {
        isCompact ? 0 : committedWidth(currentWidth)
    }

    enum Outcome: Equatable {
        case expand(labelWidth: CGFloat)
        /// `restoreWidth` is kept in storage so the next expansion returns to a
        /// usable size rather than to the collapse threshold.
        case collapse(restoreWidth: CGFloat)
        case resize(labelWidth: CGFloat)
    }

    func outcome(
        isCompact: Bool,
        startWidth: CGFloat,
        finalWidth: CGFloat,
        horizontalDelta: CGFloat
    ) -> Outcome {
        if isCompact {
            return .expand(labelWidth: committedWidth(max(finalWidth, minLabelWidth)))
        }
        if finalWidth <= collapseLabelWidth, horizontalDelta < 0 {
            return .collapse(restoreWidth: committedWidth(startWidth))
        }
        return .resize(labelWidth: committedWidth(finalWidth))
    }
}

/// The draggable edge of the rail.
///
/// A click with no travel toggles collapse — the same affordance as the toolbar
/// button, reachable where the hand already is.
struct ActionSidebarEdgeHandle: View {
    @Binding var isCompact: Bool
    @Binding var labelWidth: Double
    /// Width to render while a drag is in flight, or nil when settled.
    @Binding var previewWidth: CGFloat?

    var geometry: ActionSidebarResizeGeometry = .default

    @State private var dragStartWidth: CGFloat?
    @State private var didActivate = false

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .frame(width: 8)
            .onHover { inside in
                if inside {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let start = dragStartWidth ?? {
                            let width = geometry.dragStartWidth(
                                isCompact: isCompact,
                                currentWidth: CGFloat(labelWidth)
                            )
                            dragStartWidth = width
                            return width
                        }()

                        if !didActivate {
                            guard geometry.isResizeActivated(
                                isCompact: isCompact,
                                horizontalDelta: value.translation.width,
                                verticalDelta: value.translation.height
                            ) else { return }
                            didActivate = true
                        }

                        previewWidth = geometry.previewWidth(start + value.translation.width)
                    }
                    .onEnded { value in
                        defer {
                            dragStartWidth = nil
                            didActivate = false
                            previewWidth = nil
                        }

                        let start = dragStartWidth ?? CGFloat(labelWidth)

                        if !didActivate {
                            if geometry.isClick(
                                isCompact: isCompact,
                                horizontalDelta: value.translation.width,
                                verticalDelta: value.translation.height
                            ) {
                                withAnimation(.easeInOut(duration: 0.16)) {
                                    isCompact.toggle()
                                }
                            }
                            return
                        }

                        let final = geometry.previewWidth(start + value.translation.width)
                        switch geometry.outcome(
                            isCompact: isCompact,
                            startWidth: start,
                            finalWidth: final,
                            horizontalDelta: value.translation.width
                        ) {
                        case let .expand(width):
                            labelWidth = Double(width)
                            withAnimation(.easeInOut(duration: 0.16)) { isCompact = false }
                        case let .collapse(restoreWidth):
                            labelWidth = Double(restoreWidth)
                            withAnimation(.easeInOut(duration: 0.16)) { isCompact = true }
                        case let .resize(width):
                            labelWidth = Double(width)
                        }
                    }
            )
    }
}
