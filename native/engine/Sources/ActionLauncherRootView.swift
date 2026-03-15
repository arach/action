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
                .background(railBackground)

            Divider()
                .overlay(Color.white.opacity(0.06))

            browserSummaryPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(consoleBackground)
        }
        .frame(minWidth: 1180, minHeight: 760)
        .background(Color(red: 0.04, green: 0.05, blue: 0.07))
    }

    private var utilityRail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Action")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(StageHUDTheme.textPrimary)

                    Text("Native launcher for staging, capture, replay, and quick access to the local console.")
                        .font(.system(size: 13, weight: .regular, design: .default))
                        .foregroundStyle(StageHUDTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Action is the native app. The embedded console is just a local WebKit surface inside it.")
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .foregroundStyle(StageHUDTheme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                utilityCard(title: "Utilities") {
                    VStack(spacing: 10) {
                        launcherButton("Refresh Permissions", action: model.refreshPermissions)
                        launcherButton("Request Permissions", action: model.requestPermissions)
                        launcherButton("Open Accessibility", action: model.openAccessibilitySettings)
                        launcherButton("Open Screen Recording", action: model.openScreenRecordingSettings)
                    }
                }

                utilityCard(title: "Runtime") {
                    VStack(alignment: .leading, spacing: 10) {
                        statusRow(label: "Agent", value: model.agentStatus)
                    }
                }

                utilityCard(title: "Scenes") {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("calculator-demo")
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundStyle(StageHUDTheme.textPrimary)
                            Text("Generate a staged run, then immediately review the resulting playback and trace artifacts.")
                                .font(.system(size: 12, weight: .regular, design: .default))
                                .foregroundStyle(StageHUDTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        launcherButton(model.isRunningGuidedDemo ? "Running Guided Demo…" : "Run Guided Demo", action: model.runGuidedCalculatorDemo)
                            .disabled(model.isRunningGuidedDemo)
                        Text(model.guidedDemoStatus)
                            .font(.system(size: 12, weight: .regular, design: .default))
                            .foregroundStyle(StageHUDTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        launcherButton("Open Scenarios Folder", action: model.openScenariosFolder)
                    }
                }

                utilityCard(title: "Recent Runs") {
                    if model.recentSessions.isEmpty {
                        Text("No guided captures yet. Run one and it will appear here for quick replay and handoff.")
                            .font(.system(size: 12, weight: .regular, design: .default))
                            .foregroundStyle(StageHUDTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(model.recentSessions.prefix(4)) { session in
                                sessionRailRow(session)
                            }
                        }
                    }
                }

                utilityCard(title: "Embedded Console") {
                    VStack(spacing: 10) {
                        launcherButton("Open Embedded Console", action: model.openEmbeddedConsole)
                        launcherButton("Load Local Console", action: model.showLocalConsole)
                        launcherButton("Load Demo Site", action: model.showDemoSite)
                        launcherButton("Reload Embedded Console", action: model.reloadConsole)
                        launcherButton("Open Current URL in Browser", action: model.openWebConsoleInBrowser)
                    }
                }

                utilityCard(title: "Permissions") {
                    VStack(alignment: .leading, spacing: 10) {
                        statusRow(label: "Accessibility", value: model.accessibilityStatus)
                        statusRow(label: "Screen Recording", value: model.screenRecordingStatus)

                        if !model.notes.isEmpty {
                            Divider()
                                .overlay(Color.white.opacity(0.06))

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
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Review Loop")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(StageHUDTheme.textPrimary)

                    Text("The launcher now keeps the latest generated sessions close at hand so you can replay a run, inspect the trace, and hand it off to the next editing tool.")
                        .font(.system(size: 14, weight: .regular, design: .default))
                        .foregroundStyle(StageHUDTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                utilityCard(title: "Latest Session") {
                    if let latest = model.selectedSession {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(latest.expression)
                                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(StageHUDTheme.textPrimary)

                                    Text("Result \(latest.actualResult)")
                                        .font(.system(size: 13, weight: .regular, design: .default))
                                        .foregroundStyle(StageHUDTheme.textSecondary)
                                }
                                Spacer()
                                Text(sessionTimestamp(latest))
                                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                                    .foregroundStyle(StageHUDTheme.textMuted)
                            }

                            Text("Next step: attach agent-readable feedback directly to this playback timeline or marked regions.")
                                .font(.system(size: 12, weight: .regular, design: .default))
                                .foregroundStyle(StageHUDTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)

                            ActionSessionPreviewView(videoURL: latest.videoURL)
                                .frame(minHeight: 280, maxHeight: 320)

                            HStack(spacing: 10) {
                                launcherButton("Replay", action: { model.replaySession(latest) })
                                launcherButton("Reveal", action: { model.revealSession(latest) })
                                launcherButton("Trace", action: { model.openSessionTrace(latest) })
                                launcherButton("Screenshot", action: { model.openSessionScreenshot(latest) })
                            }
                        }
                    } else {
                        Text("Run the guided calculator capture to seed the review loop.")
                            .font(.system(size: 12, weight: .regular, design: .default))
                            .foregroundStyle(StageHUDTheme.textSecondary)
                    }
                }

                utilityCard(title: "Recent Sessions") {
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

                VStack(alignment: .leading, spacing: 8) {
                    Text("Embedded Console")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(StageHUDTheme.textPrimary)

                    Text("This is a utility surface inside Action for local web tooling. It is not the main review experience.")
                        .font(.system(size: 14, weight: .regular, design: .default))
                        .foregroundStyle(StageHUDTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                utilityCard(title: "Current Target") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(model.consoleURL.absoluteString)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(StageHUDTheme.textPrimary)
                            .textSelection(.enabled)

                        Text(model.consoleStatus)
                            .font(.system(size: 12, weight: .regular, design: .default))
                            .foregroundStyle(StageHUDTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(28)
        }
    }

    private var railBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.09, green: 0.10, blue: 0.13),
                Color(red: 0.06, green: 0.07, blue: 0.09),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var consoleBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.06, blue: 0.08),
                Color(red: 0.04, green: 0.05, blue: 0.07),
            ],
            startPoint: .top,
            endPoint: .bottom
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
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
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

    private func launcherButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(StageHUDButtonStyle(tone: .secondary))
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
                }
                Spacer()
                Text(sessionTimestamp(session))
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(StageHUDTheme.textMuted)
            }

            HStack(spacing: 8) {
                compactSessionButton("Replay") { model.replaySession(session) }
                compactSessionButton("Reveal") { model.revealSession(session) }
            }
        }
        .contentShape(Rectangle())
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(model.selectedSession?.id == session.id ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(model.selectedSession?.id == session.id ? Color.white.opacity(0.16) : Color.white.opacity(0.06), lineWidth: 1)
        )
        .onTapGesture {
            model.selectSession(session)
        }
    }

    private func sessionDetailRow(_ session: ActionSessionSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.expression)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(StageHUDTheme.textPrimary)
                    Text("Expected \(session.expectedResult) • Actual \(session.actualResult)")
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .foregroundStyle(StageHUDTheme.textSecondary)
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
