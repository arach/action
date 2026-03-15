import SwiftUI

struct ActionSessionTimelineView: View {
    let currentTimeSeconds: Double
    let durationSeconds: Double
    let draftStartTimeSeconds: Double?
    let draftEndTimeSeconds: Double?
    let feedbackItems: [ActionSessionFeedbackDocument.Item]
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let normalizedCurrent = normalized(currentTimeSeconds)
            let currentX = width * normalizedCurrent

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 10)

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.96, green: 0.44, blue: 0.27),
                                Color(red: 0.98, green: 0.63, blue: 0.38),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(currentX, 8), height: 10)

                if let draftStartTimeSeconds {
                    draftRangeOverlay(in: width, startTimeSeconds: draftStartTimeSeconds, endTimeSeconds: draftEndTimeSeconds)
                }

                ForEach(feedbackItems) { item in
                    feedbackMarker(item: item, width: width)
                }

                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.25), radius: 4)
                    .offset(x: min(max(currentX - 8, -8), width - 8))
            }
            .frame(height: 24)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onSeek(seconds(at: value.location.x, width: width))
                    }
            )
        }
        .frame(height: 24)
    }

    private func feedbackMarker(item: ActionSessionFeedbackDocument.Item, width: Double) -> some View {
        let markerX = width * normalized(item.startTimeSeconds)
        let markerColor = item.region == nil
            ? Color(red: 0.39, green: 0.76, blue: 0.95)
            : Color(red: 0.96, green: 0.44, blue: 0.27)

        return Rectangle()
            .fill(markerColor)
            .frame(width: 4, height: 18)
            .cornerRadius(2)
            .offset(x: min(max(markerX - 2, 0), width - 4))
            .help(item.instruction)
    }

    @ViewBuilder
    private func draftRangeOverlay(in width: Double, startTimeSeconds: Double, endTimeSeconds: Double?) -> some View {
        let startX = width * normalized(startTimeSeconds)
        if let endTimeSeconds {
            let endX = width * normalized(endTimeSeconds)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.18))
                .frame(width: max(endX - startX, 4), height: 14)
                .offset(x: startX)
        } else {
            Rectangle()
                .fill(Color.white.opacity(0.85))
                .frame(width: 2, height: 18)
                .offset(x: min(max(startX, 0), width - 2))
        }
    }

    private func normalized(_ seconds: Double) -> Double {
        guard durationSeconds > 0 else {
            return 0
        }
        return max(0, min(seconds / durationSeconds, 1))
    }

    private func seconds(at x: Double, width: Double) -> Double {
        guard durationSeconds > 0 else {
            return 0
        }
        let clampedX = max(0, min(x, width))
        return (clampedX / width) * durationSeconds
    }
}
