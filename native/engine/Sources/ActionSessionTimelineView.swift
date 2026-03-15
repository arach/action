import SwiftUI

struct ActionSessionTimelineView: View {
    let currentTimeSeconds: Double
    let durationSeconds: Double
    let draftStartTimeSeconds: Double?
    let draftEndTimeSeconds: Double?
    let feedbackItems: [ActionSessionFeedbackDocument.Item]
    let onSeek: (Double) -> Void

    private let markerLaneHeight: CGFloat = 18
    private let trackHeight: CGFloat = 24
    private let maximumMarkerLanes = 3

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let markerLayouts = feedbackMarkerLayouts(for: width)
            let laneCount = max(1, (markerLayouts.map(\.lane).max() ?? 0) + 1)
            let markerAreaHeight = CGFloat(laneCount) * markerLaneHeight
            let currentX = width * CGFloat(normalized(currentTimeSeconds))
            let trackY = markerAreaHeight + 10

            ZStack(alignment: .topLeading) {
                markerLaneBackground(width: width, height: markerAreaHeight)

                ForEach(markerLayouts) { layout in
                    feedbackMarker(layout: layout, width: width, trackY: trackY)
                }

                timelineTrack(width: width, currentX: currentX, trackY: trackY)

                playhead(currentX: currentX, width: width, totalHeight: markerAreaHeight + trackHeight + 18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onSeek(seconds(at: value.location.x, width: width))
                    }
            )
        }
        .frame(height: 94)
    }

    private func markerLaneBackground(width: CGFloat, height: CGFloat) -> some View {
        ActionChamferedShape(cornerCut: 4)
            .fill(StageHUDTheme.appBackground)
            .overlay(
                ActionChamferedShape(cornerCut: 4)
                    .stroke(StageHUDTheme.cardBorder.opacity(0.5), lineWidth: 1)
            )
            .frame(width: width, height: max(height, markerLaneHeight))
    }

    private func timelineTrack(width: CGFloat, currentX: CGFloat, trackY: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(StageHUDTheme.cardBorder.opacity(0.85))
                .frame(width: width, height: 2)

            Capsule(style: .continuous)
                .fill(StageHUDTheme.textPrimary.opacity(0.88))
                .frame(width: max(currentX, 2), height: 2)

            if let draftStartTimeSeconds {
                draftRangeOverlay(
                    in: width,
                    startTimeSeconds: draftStartTimeSeconds,
                    endTimeSeconds: draftEndTimeSeconds
                )
            }

            Circle()
                .fill(StageHUDTheme.cardFill)
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .stroke(StageHUDTheme.textPrimary.opacity(0.44), lineWidth: 1)
                )
                .overlay(
                    Circle()
                        .fill(StageHUDTheme.textPrimary)
                        .frame(width: 4, height: 4)
                )
                .offset(x: min(max(currentX - 6, -6), width - 6))
        }
        .frame(width: width, height: trackHeight)
        .offset(y: trackY)
    }

    private func playhead(currentX: CGFloat, width: CGFloat, totalHeight: CGFloat) -> some View {
        let labelWidth: CGFloat = 60
        let clampedLabelX = min(max(currentX - (labelWidth / 2), 0), width - labelWidth)

        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(StageHUDTheme.textPrimary.opacity(0.18))
                .frame(width: 1, height: totalHeight)
                .offset(x: currentX)

            Text(formattedTime(currentTimeSeconds))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(StageHUDTheme.textPrimary)
                .frame(width: labelWidth)
                .padding(.vertical, 4)
                .background(StageHUDTheme.cardFill.opacity(0.96))
                .overlay(
                    ActionChamferedShape(cornerCut: 4)
                        .stroke(StageHUDTheme.cardBorder, lineWidth: 1)
                )
                .clipShape(ActionChamferedShape(cornerCut: 4))
                .offset(x: clampedLabelX)
        }
    }

    private func feedbackMarker(layout: FeedbackMarkerLayout, width: CGFloat, trackY: CGFloat) -> some View {
        let laneY = CGFloat(layout.lane) * markerLaneHeight
        let markerX = width * CGFloat(normalized(layout.item.startTimeSeconds))

        return VStack(alignment: .leading, spacing: 4) {
            Button {
                onSeek(layout.item.startTimeSeconds)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: layout.item.region == nil ? "text.bubble" : "selection.pin.in.out")
                        .font(.system(size: 9, weight: .semibold))
                    Text("\(layout.index + 1)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(layout.tint)
                .padding(.horizontal, 8)
                .frame(height: 16)
                .background(StageHUDTheme.cardFill)
                .overlay(
                    ActionChamferedShape(cornerCut: 4)
                        .stroke(layout.tint.opacity(0.45), lineWidth: 1)
                )
                .clipShape(ActionChamferedShape(cornerCut: 4))
            }
            .buttonStyle(.plain)
            .help(helpText(for: layout.item))

            Rectangle()
                .fill(layout.tint.opacity(0.7))
                .frame(width: 1, height: max(trackY - laneY - 20, 8))
                .padding(.leading, 11)
        }
        .offset(x: min(max(markerX - 11, 0), width - 58), y: laneY + 4)
    }

    @ViewBuilder
    private func draftRangeOverlay(in width: CGFloat, startTimeSeconds: Double, endTimeSeconds: Double?) -> some View {
        let startX = width * CGFloat(normalized(startTimeSeconds))
        if let endTimeSeconds {
            let endX = width * CGFloat(normalized(endTimeSeconds))
            ActionChamferedShape(cornerCut: 3)
                .fill(StageHUDTheme.textPrimary.opacity(0.12))
                .frame(width: max(endX - startX, 4), height: 10)
                .offset(x: startX, y: 0)
        } else {
            Rectangle()
                .fill(StageHUDTheme.textPrimary.opacity(0.72))
                .frame(width: 2, height: 14)
                .offset(x: min(max(startX, 0), width - 2), y: -1)
        }
    }

    private func feedbackMarkerLayouts(for width: CGFloat) -> [FeedbackMarkerLayout] {
        let sorted = feedbackItems.sorted { lhs, rhs in
            lhs.startTimeSeconds < rhs.startTimeSeconds
        }

        var lanePositions = Array(repeating: -CGFloat.infinity, count: maximumMarkerLanes)
        let minimumGap = max(width * 0.075, 56)

        return sorted.enumerated().map { index, item in
            let markerX = width * CGFloat(normalized(item.startTimeSeconds))
            let lane = firstAvailableLane(for: markerX, lanePositions: lanePositions, minimumGap: minimumGap)
            lanePositions[lane] = markerX
            return FeedbackMarkerLayout(
                id: item.id,
                index: index,
                lane: lane,
                item: item,
                tint: item.region == nil
                    ? Color(red: 0.33, green: 0.71, blue: 0.92)
                    : Color(red: 0.95, green: 0.49, blue: 0.28)
            )
        }
    }

    private func firstAvailableLane(for x: CGFloat, lanePositions: [CGFloat], minimumGap: CGFloat) -> Int {
        if let lane = lanePositions.firstIndex(where: { x - $0 >= minimumGap }) {
            return lane
        }

        return lanePositions.enumerated().min(by: { lhs, rhs in
            lhs.element < rhs.element
        })?.offset ?? 0
    }

    private func helpText(for item: ActionSessionFeedbackDocument.Item) -> String {
        let prefix: String
        if let endTimeSeconds = item.endTimeSeconds {
            prefix = "\(formattedTime(item.startTimeSeconds))-\(formattedTime(endTimeSeconds))"
        } else {
            prefix = formattedTime(item.startTimeSeconds)
        }
        return "\(prefix) • \(item.instruction)"
    }

    private func normalized(_ seconds: Double) -> Double {
        guard durationSeconds > 0 else {
            return 0
        }
        return max(0, min(seconds / durationSeconds, 1))
    }

    private func seconds(at x: CGFloat, width: CGFloat) -> Double {
        guard durationSeconds > 0 else {
            return 0
        }
        let clampedX = max(0, min(x, width))
        return Double(clampedX / width) * durationSeconds
    }

    private func formattedTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else {
            return "00:00.0"
        }
        let minutes = Int(seconds) / 60
        let wholeSeconds = Int(seconds) % 60
        let tenths = Int((seconds * 10).rounded(.down)) % 10
        return String(format: "%02d:%02d.%01d", minutes, wholeSeconds, tenths)
    }
}

private struct FeedbackMarkerLayout: Identifiable {
    let id: String
    let index: Int
    let lane: Int
    let item: ActionSessionFeedbackDocument.Item
    let tint: Color
}
