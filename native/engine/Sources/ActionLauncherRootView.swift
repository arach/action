import AppKit
import SwiftUI

struct ActionLauncherRootView: View {
    @ObservedObject var model: ActionLauncherViewModel
    private let sessionDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    var body: some View {
        HStack(spacing: 0) {
            utilityRail
                .frame(width: 320)
                .background(StageHUDTheme.railBackground)

            Divider()
                .overlay(StageHUDTheme.panelBorder)

            browserSummaryPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(StageHUDTheme.appBackground)
        }
        .frame(minWidth: 1180, minHeight: 760)
        .background(StageHUDTheme.appBackground)
    }

    private var utilityRail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                brandHeader

                utilityCard(title: "Primary Run") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .center) {
                            Text("calculator-demo")
                                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                .foregroundStyle(StageHUDTheme.textPrimary)
                            Spacer()
                            Text(model.guidedDemoStatus)
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundStyle(StageHUDTheme.textMuted)
                        }

                        Text("Generate a staged run, then move directly into playback, timeline review, and agent-ready notes.")
                            .font(.system(size: 12, weight: .regular, design: .default))
                            .foregroundStyle(StageHUDTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        launcherButton(
                            model.isRunningGuidedDemo ? "Running Guided Demo..." : "Run Guided Demo",
                            tone: .primary,
                            action: model.runGuidedCalculatorDemo
                        )
                        .disabled(model.isRunningGuidedDemo)

                        launcherButton("Open Scenarios Folder", action: model.openScenariosFolder)
                    }
                }

                utilityCard(title: "Environment") {
                    VStack(alignment: .leading, spacing: 12) {
                        statusRow(label: "Agent", value: model.agentStatus)
                        statusRow(label: "A11y", value: model.accessibilityStatus)
                        statusRow(label: "Screen", value: model.screenRecordingStatus)
                    }
                }

                utilityCard(title: "Appearance") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Appearance", selection: Binding(
                            get: { model.appearanceMode },
                            set: { model.setAppearanceMode($0) }
                        )) {
                            ForEach(ActionAppearanceMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text("System follows macOS. Light and dark behave like product modes, not debug skins.")
                            .font(.system(size: 12, weight: .regular, design: .default))
                            .foregroundStyle(StageHUDTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                utilityCard(title: "Recent Runs") {
                    if model.recentSessions.isEmpty {
                        Text("No guided captures yet. Run one and it will appear here for quick replay and selection.")
                            .font(.system(size: 12, weight: .regular, design: .default))
                            .foregroundStyle(StageHUDTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(model.recentSessions.prefix(4)) { session in
                                sessionRailRow(session)
                            }
                        }
                    }
                }

                utilityCard(title: "Utilities") {
                    VStack(spacing: 10) {
                        launcherButton("Refresh Permissions", action: model.refreshPermissions)
                        launcherButton("Request Permissions", action: model.requestPermissions)
                        launcherButton("Open Accessibility", action: model.openAccessibilitySettings)
                        launcherButton("Open Screen Recording", action: model.openScreenRecordingSettings)
                        launcherButton("Start Local Console", action: model.startLocalConsole)
                        launcherButton("Open Embedded Console", action: model.openEmbeddedConsole)
                    }
                }

                if !model.notes.isEmpty {
                    utilityCard(title: "Notes") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(model.notes, id: \.self) { note in
                                Text(note)
                                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                                    .foregroundStyle(StageHUDTheme.textMuted)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
    }

    private var browserSummaryPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                reviewHero

                if let latest = model.selectedSession {
                    reviewHeroSurface(for: latest)
                    ActionSessionPreviewView(session: latest, model: model)
                } else {
                    utilityCard(title: "Active Review") {
                        Text("Run the guided calculator capture to seed the review loop.")
                            .font(.system(size: 12, weight: .regular, design: .default))
                            .foregroundStyle(StageHUDTheme.textSecondary)
                    }
                }

                utilityCard(title: "Session Library") {
                    if model.recentSessions.isEmpty {
                        Text("Generated runs will appear here with replay and artifact actions.")
                            .font(.system(size: 12, weight: .regular, design: .default))
                            .foregroundStyle(StageHUDTheme.textSecondary)
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(model.recentSessions) { session in
                                sessionDetailRow(session)
                            }
                        }
                    }
                }

                utilityCard(title: "Console Surface") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(model.consoleURL.absoluteString)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(StageHUDTheme.textPrimary)
                            .textSelection(.enabled)

                        Text(model.consoleStatus)
                            .font(.system(size: 12, weight: .regular, design: .default))
                            .foregroundStyle(StageHUDTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 10) {
                            launcherButton("Load Local Console", action: model.showLocalConsole)
                            launcherButton("Reload", action: model.reloadConsole)
                            launcherButton("Browser", action: model.openWebConsoleInBrowser)
                        }
                    }
                }
            }
            .padding(30)
        }
        .scrollIndicators(.hidden)
    }

    private var brandHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Action")
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .foregroundStyle(StageHUDTheme.textPrimary)

            Text("Capture, review, and hand off screen actions with a surface built for operator flow rather than demo chrome.")
                .font(.system(size: 14, weight: .regular, design: .default))
                .foregroundStyle(StageHUDTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                railTag("Native")
                railTag("Replay")
                railTag("Agent")
            }
        }
    }

    private var reviewHero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Review Loop")
                .font(.system(size: 40, weight: .bold, design: .monospaced))
                .foregroundStyle(StageHUDTheme.textPrimary)

            Text("Validate captures, inspect playback quality, and leave machine-readable feedback without breaking concentration.")
                .font(.system(size: 15, weight: .regular, design: .default))
                .foregroundStyle(StageHUDTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func reviewHeroSurface(for session: ActionSessionSummary) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Active Review")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(StageHUDTheme.textMuted)
                    Text(session.expression)
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .foregroundStyle(StageHUDTheme.textPrimary)
                    Text("Result \(session.actualResult) is ready for playback, selection review, and post-edit handoff.")
                        .font(.system(size: 14, weight: .regular, design: .default))
                        .foregroundStyle(StageHUDTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 20)

                VStack(alignment: .trailing, spacing: 12) {
                    heroMetric(label: "Session", value: sessionTimestamp(session))
                    heroMetric(label: "Expected", value: session.expectedResult)
                    heroMetric(label: "Feedback", value: "\(session.feedbackCount)")
                }
            }

            HStack(spacing: 10) {
                launcherButton("Replay", tone: .primary, action: { model.replaySession(session) })
                launcherButton("Reveal", action: { model.revealSession(session) })
                launcherButton("Trace", action: { model.openSessionTrace(session) })
                launcherButton("Feedback", action: { model.openSessionFeedback(session) })
                launcherButton("Screenshot", action: { model.openSessionScreenshot(session) })
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(StageHUDTheme.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(StageHUDTheme.panelBorder, lineWidth: 1)
        )
    }

    private func utilityCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(StageHUDTheme.textMuted)

            content()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(StageHUDTheme.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(StageHUDTheme.cardBorder, lineWidth: 1)
        )
    }

    private func statusRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .regular, design: .default))
                .foregroundStyle(StageHUDTheme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(StageHUDTheme.textPrimary)
        }
    }

    private func launcherButton(
        _ title: String,
        tone: StageHUDViewModel.ButtonTone = .secondary,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .buttonStyle(StageHUDButtonStyle(tone: tone))
    }

    private func railTag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .regular, design: .monospaced))
            .foregroundStyle(StageHUDTheme.textMuted)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(StageHUDTheme.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(StageHUDTheme.cardBorder, lineWidth: 1)
            )
    }

    private func heroMetric(label: String, value: String) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(StageHUDTheme.textMuted)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(StageHUDTheme.textPrimary)
        }
    }

    private func sessionRailRow(_ session: ActionSessionSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.expression)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(StageHUDTheme.textPrimary)
                    Text("Result \(session.actualResult)")
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .foregroundStyle(StageHUDTheme.textSecondary)
                    if session.feedbackCount > 0 {
                        Text("\(session.feedbackCount) feedback")
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(StageHUDTheme.textMuted)
                    }
                }
                Spacer()
                Text(sessionTimestamp(session))
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(StageHUDTheme.textMuted)
            }

            HStack(spacing: 8) {
                compactSessionButton("Select") { model.selectSession(session) }
                compactSessionButton("Replay") { model.replaySession(session) }
                compactSessionButton("Reveal") { model.revealSession(session) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(model.selectedSession?.id == session.id ? StageHUDTheme.buttonSecondaryHover : StageHUDTheme.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(model.selectedSession?.id == session.id ? StageHUDTheme.panelBorder : StageHUDTheme.cardBorder, lineWidth: 1)
        )
    }

    private func sessionDetailRow(_ session: ActionSessionSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.expression)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(StageHUDTheme.textPrimary)
                    Text("Expected \(session.expectedResult)  Actual \(session.actualResult)")
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .foregroundStyle(StageHUDTheme.textSecondary)
                    if session.feedbackCount > 0 {
                        Text("\(session.feedbackCount) feedback item\(session.feedbackCount == 1 ? "" : "s")")
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(StageHUDTheme.textMuted)
                    }
                }
                Spacer()
                Text(sessionTimestamp(session))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(StageHUDTheme.textMuted)
            }

            HStack(spacing: 10) {
                launcherButton("Select", action: { model.selectSession(session) })
                launcherButton("Replay", action: { model.replaySession(session) })
                launcherButton("Reveal", action: { model.revealSession(session) })
                launcherButton("Trace", action: { model.openSessionTrace(session) })
                launcherButton("Feedback", action: { model.openSessionFeedback(session) })
                launcherButton("Screenshot", action: { model.openSessionScreenshot(session) })
            }
        }
        .padding(.vertical, 2)
    }

    private func compactSessionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(StageHUDButtonStyle(tone: .secondary))
            .controlSize(.small)
    }

    private func sessionTimestamp(_ session: ActionSessionSummary) -> String {
        guard let date = session.startedAt else {
            return session.sessionId
        }
        return sessionDateFormatter.localizedString(for: date, relativeTo: Date())
    }
}
