import AVFoundation
import Foundation
import SwiftUI

struct ActionSessionPreviewView: View {
    let session: ActionSessionSummary
    @ObservedObject var model: ActionLauncherViewModel

    @StateObject private var playback: ActionSessionPlaybackCoordinator
    @State private var feedbackDocument: ActionSessionFeedbackDocument
    @State private var draftInstruction = ""
    @State private var draftStartTimeSeconds: Double?
    @State private var draftEndTimeSeconds: Double?
    @State private var draftRegion: ActionSessionFeedbackDocument.Region?
    @State private var dragStartPoint: CGPoint?
    @State private var dragCurrentPoint: CGPoint?
    @State private var isSelectingRegion = false
    @State private var feedbackStatus = "No agent feedback yet"

    init(session: ActionSessionSummary, model: ActionLauncherViewModel) {
        self.session = session
        self.model = model
        _playback = StateObject(wrappedValue: ActionSessionPlaybackCoordinator(url: session.videoURL))
        _feedbackDocument = State(initialValue: model.loadFeedback(for: session))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Playback Workstation")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(StageHUDTheme.textMuted)
                        Text("Review the capture, scrub precisely, and place feedback anchors without leaving the frame.")
                            .font(.system(size: 13, weight: .regular, design: .default))
                            .foregroundStyle(StageHUDTheme.textSecondary)
                    }
                    Spacer()
                    Text(draftAnchorSummary)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(StageHUDTheme.textMuted)
                }

                ZStack(alignment: .topLeading) {
                    ActionInlinePlayerView(player: playback.player)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(StageHUDTheme.cardBorder, lineWidth: 1)
                        )

                    overlayChrome
                }
                .frame(minHeight: 280, maxHeight: 340)
                .overlay(regionSelectionOverlay)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Text("Time \(formattedTime(playback.currentTimeSeconds)) / \(formattedTime(playback.durationSeconds))")
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(StageHUDTheme.textSecondary)
                        Spacer()
                    }

                    ActionSessionTimelineView(
                        currentTimeSeconds: playback.currentTimeSeconds,
                        durationSeconds: playback.durationSeconds,
                        draftStartTimeSeconds: draftStartTimeSeconds,
                        draftEndTimeSeconds: draftEndTimeSeconds,
                        feedbackItems: feedbackDocument.items,
                        onSeek: { playback.seek(to: $0) }
                    )

                    HStack(spacing: 10) {
                        transportButton(playback.isPlaying ? "Pause" : "Play", tone: .primary, action: playback.togglePlayback)
                        transportButton("Stop", action: playback.stop)
                        transportButton("Back 5s") { playback.skip(by: -5) }
                        transportButton("Forward 5s") { playback.skip(by: 5) }
                    }

                    HStack(spacing: 10) {
                        feedbackButton("Mark Time", action: markCurrentTime)
                        feedbackButton("Set In", action: setInPoint)
                        feedbackButton("Set Out", action: setOutPoint)
                        feedbackButton(isSelectingRegion ? "Dragging Region..." : "Mark Region", action: toggleRegionSelection)
                        feedbackButton("Clear", action: clearDraftAnchors)
                    }
                }
            }
            .padding(18)
            .background(reviewCardBackground)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Agent Feedback")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(StageHUDTheme.textMuted)
                    Spacer()
                    Text(feedbackStatus)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(StageHUDTheme.textMuted)
                }

                TextField("Tell the agent what to change here", text: $draftInstruction, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(3...6)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(StageHUDTheme.appBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(StageHUDTheme.cardBorder, lineWidth: 1)
                    )

                HStack(spacing: 10) {
                    feedbackButton("Save Feedback", tone: .primary, action: saveFeedback)
                    if !feedbackDocument.items.isEmpty {
                        feedbackButton("Open feedback.json", action: { model.openSessionFeedback(session) })
                    }
                    Spacer()
                }
            }
            .padding(14)
            .background(reviewCardBackground)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Saved Feedback")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(StageHUDTheme.textMuted)
                    Spacer()
                    Text("\(feedbackDocument.items.count)")
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(StageHUDTheme.textMuted)
                }

                if feedbackDocument.items.isEmpty {
                    Text("Stamp a time, drag a region if needed, and leave an instruction your agent can read directly.")
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .foregroundStyle(StageHUDTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(feedbackDocument.items) { item in
                            feedbackItemRow(item)
                        }
                    }
                }
            }
            .padding(14)
            .background(reviewCardBackground)
        }
        .onDisappear {
            playback.pause()
        }
        .onChange(of: session.id) { _, _ in
            reloadSession()
        }
    }

    private var overlayChrome: some View {
        VStack(alignment: .leading, spacing: 8) {
                Text(formattedTime(playback.currentTimeSeconds))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(StageHUDTheme.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.82), in: Capsule())

            if isSelectingRegion {
                Text("Drag over the frame to mark a region for the agent.")
                    .font(.system(size: 11, weight: .regular, design: .default))
                    .foregroundStyle(StageHUDTheme.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.82), in: Capsule())
            }
        }
        .padding(12)
    }

    private var regionSelectionOverlay: some View {
        GeometryReader { geometry in
            ZStack {
                if let draftRegion {
                    let frame = denormalize(draftRegion, in: geometry.size)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(StageHUDTheme.textPrimary.opacity(0.74), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(StageHUDTheme.textPrimary.opacity(0.08))
                        )
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                }

                if let previewRect = previewDragRect(in: geometry.size) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(StageHUDTheme.textPrimary.opacity(0.92), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(StageHUDTheme.textPrimary.opacity(0.10))
                        )
                        .frame(width: previewRect.width, height: previewRect.height)
                        .position(x: previewRect.midX, y: previewRect.midY)
                }
            }
            .contentShape(Rectangle())
            .gesture(regionDragGesture(in: geometry.size))
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var draftAnchorSummary: String {
        var parts: [String] = []
        if let draftStartTimeSeconds {
            if let draftEndTimeSeconds {
                parts.append("\(formattedTime(draftStartTimeSeconds))-\(formattedTime(draftEndTimeSeconds))")
            } else {
                parts.append("@\(formattedTime(draftStartTimeSeconds))")
            }
        }
        if let draftRegion {
            parts.append("region \(Int(draftRegion.x * 100))%,\(Int(draftRegion.y * 100))%")
        }
        return parts.isEmpty ? "No anchors" : parts.joined(separator: " • ")
    }

    private var reviewCardBackground: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(StageHUDTheme.cardFill)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(StageHUDTheme.cardBorder, lineWidth: 1)
            )
    }

    private func feedbackButton(_ title: String, action: @escaping () -> Void) -> some View {
        feedbackButton(title, tone: .secondary, action: action)
    }

    private func feedbackButton(_ title: String, tone: StageHUDViewModel.ButtonTone, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(StageHUDButtonStyle(tone: tone))
            .controlSize(.small)
    }

    private func transportButton(_ title: String, tone: StageHUDViewModel.ButtonTone = .secondary, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(StageHUDButtonStyle(tone: tone))
            .controlSize(.small)
    }

    private func feedbackItemRow(_ item: ActionSessionFeedbackDocument.Item) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(feedbackItemSummary(item))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(StageHUDTheme.textMuted)
                    Text(item.instruction)
                        .font(.system(size: 13, weight: .regular, design: .default))
                        .foregroundStyle(StageHUDTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    Button("Jump") {
                        playback.seek(to: item.startTimeSeconds)
                    }
                    .buttonStyle(StageHUDButtonStyle(tone: .secondary))
                    .controlSize(.small)

                    Button("Delete") {
                        deleteFeedbackItem(item)
                    }
                    .buttonStyle(StageHUDButtonStyle(tone: .secondary))
                    .controlSize(.small)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(StageHUDTheme.appBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(StageHUDTheme.cardBorder, lineWidth: 1)
        )
    }

    private func markCurrentTime() {
        draftStartTimeSeconds = playback.currentTimeSeconds
        draftEndTimeSeconds = nil
        feedbackStatus = "Marked current time"
    }

    private func setInPoint() {
        let current = playback.currentTimeSeconds
        draftStartTimeSeconds = current
        if let draftEndTimeSeconds, draftEndTimeSeconds < current {
            self.draftEndTimeSeconds = nil
        }
        feedbackStatus = "Set in point"
    }

    private func setOutPoint() {
        let current = playback.currentTimeSeconds
        if let draftStartTimeSeconds {
            draftEndTimeSeconds = max(draftStartTimeSeconds, current)
        } else {
            draftStartTimeSeconds = current
            draftEndTimeSeconds = current
        }
        feedbackStatus = "Set out point"
    }

    private func toggleRegionSelection() {
        isSelectingRegion.toggle()
        if isSelectingRegion {
            feedbackStatus = "Drag on the frame to mark a region"
        } else {
            dragStartPoint = nil
            dragCurrentPoint = nil
        }
    }

    private func clearDraftAnchors() {
        draftStartTimeSeconds = nil
        draftEndTimeSeconds = nil
        draftRegion = nil
        dragStartPoint = nil
        dragCurrentPoint = nil
        isSelectingRegion = false
        feedbackStatus = "Cleared draft anchors"
    }

    private func saveFeedback() {
        let instruction = draftInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else {
            feedbackStatus = "Add an instruction first"
            return
        }

        let item = ActionSessionFeedbackDocument.Item(
            id: UUID().uuidString,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            startTimeSeconds: draftStartTimeSeconds ?? playback.currentTimeSeconds,
            endTimeSeconds: draftEndTimeSeconds,
            region: draftRegion,
            instruction: instruction
        )

        var updated = feedbackDocument
        updated.items.insert(item, at: 0)

        do {
            try model.saveFeedback(updated, for: session)
            feedbackDocument = model.loadFeedback(for: session)
            draftInstruction = ""
            clearDraftAnchors()
            feedbackStatus = "Saved to feedback.json"
        } catch {
            feedbackStatus = "Save failed: \(error.localizedDescription)"
        }
    }

    private func deleteFeedbackItem(_ item: ActionSessionFeedbackDocument.Item) {
        var updated = feedbackDocument
        updated.items.removeAll { $0.id == item.id }

        do {
            try model.saveFeedback(updated, for: session)
            feedbackDocument = model.loadFeedback(for: session)
            feedbackStatus = "Deleted feedback item"
        } catch {
            feedbackStatus = "Delete failed: \(error.localizedDescription)"
        }
    }

    private func reloadSession() {
        playback.load(url: session.videoURL)
        feedbackDocument = model.loadFeedback(for: session)
        draftInstruction = ""
        clearDraftAnchors()
        feedbackStatus = feedbackDocument.items.isEmpty ? "No agent feedback yet" : "Loaded feedback.json"
    }

    private func regionDragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard isSelectingRegion else {
                    return
                }
                if dragStartPoint == nil {
                    dragStartPoint = value.startLocation
                }
                dragCurrentPoint = value.location
            }
            .onEnded { value in
                guard isSelectingRegion else {
                    return
                }
                draftRegion = normalizedRegion(from: value.startLocation, to: value.location, in: size)
                dragStartPoint = nil
                dragCurrentPoint = nil
                isSelectingRegion = false
                feedbackStatus = draftRegion == nil ? "Region too small" : "Marked region"
            }
    }

    private func previewDragRect(in size: CGSize) -> CGRect? {
        guard let dragStartPoint, let dragCurrentPoint else {
            return nil
        }
        return normalizeRect(CGRect(
            x: min(dragStartPoint.x, dragCurrentPoint.x),
            y: min(dragStartPoint.y, dragCurrentPoint.y),
            width: abs(dragCurrentPoint.x - dragStartPoint.x),
            height: abs(dragCurrentPoint.y - dragStartPoint.y)
        ), in: size)
    }

    private func normalizedRegion(from start: CGPoint, to end: CGPoint, in size: CGSize) -> ActionSessionFeedbackDocument.Region? {
        let rect = normalizeRect(CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        ), in: size)

        guard rect.width >= 12, rect.height >= 12, size.width > 0, size.height > 0 else {
            return nil
        }

        return ActionSessionFeedbackDocument.Region(
            x: Double(rect.minX / size.width),
            y: Double(rect.minY / size.height),
            width: Double(rect.width / size.width),
            height: Double(rect.height / size.height)
        )
    }

    private func normalizeRect(_ rect: CGRect, in size: CGSize) -> CGRect {
        let originX = max(0, min(rect.minX, size.width))
        let originY = max(0, min(rect.minY, size.height))
        let maxWidth = max(0, size.width - originX)
        let maxHeight = max(0, size.height - originY)
        return CGRect(
            x: originX,
            y: originY,
            width: min(rect.width, maxWidth),
            height: min(rect.height, maxHeight)
        )
    }

    private func denormalize(_ region: ActionSessionFeedbackDocument.Region, in size: CGSize) -> CGRect {
        CGRect(
            x: Double(size.width) * region.x,
            y: Double(size.height) * region.y,
            width: Double(size.width) * region.width,
            height: Double(size.height) * region.height
        )
    }

    private func feedbackItemSummary(_ item: ActionSessionFeedbackDocument.Item) -> String {
        var parts = [formattedTime(item.startTimeSeconds)]
        if let endTimeSeconds = item.endTimeSeconds {
            parts[0] += "-\(formattedTime(endTimeSeconds))"
        }
        if let region = item.region {
            parts.append("region \(Int(region.x * 100))%,\(Int(region.y * 100))% \(Int(region.width * 100))x\(Int(region.height * 100))")
        }
        return parts.joined(separator: " • ")
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
