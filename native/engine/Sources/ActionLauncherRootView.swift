import AppKit
import SwiftUI

struct ActionLauncherRootView: View {
    private enum LauncherSection: String, CaseIterable, Identifiable, Hashable {
        case review = "Review"
        case library = "Library"
        case console = "Console"
        case settings = "Settings"

        var id: String { rawValue }

        var subtitle: String {
            switch self {
            case .review:
                return "Playback and feedback"
            case .library:
                return "Recorded sessions"
            case .console:
                return "Local web surface"
            case .settings:
                return "Environment and appearance"
            }
        }
    }

    @ObservedObject var model: ActionLauncherViewModel
    @State private var selectedSection: LauncherSection? = .review
    private let sessionDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                Section("Workspace") {
                    ForEach(LauncherSection.allCases) { section in
                        Label(section.rawValue, systemImage: iconName(for: section))
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(StageHUDTheme.textPrimary)
                            .tag(Optional(section))
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(StageHUDTheme.railBackground)
            .navigationSplitViewColumnWidth(min: 200, ideal: 216, max: 232)
        } detail: {
            mainPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(StageHUDTheme.appBackground)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 1180, minHeight: 760)
        .background(StageHUDTheme.appBackground)
    }

    private var mainPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                appHeader

                switch selectedSection ?? .review {
                case .review:
                    reviewSection
                case .library:
                    librarySection
                case .console:
                    consoleSection
                case .settings:
                    settingsSection
                }
            }
            .padding(30)
        }
        .scrollIndicators(.hidden)
    }

    private var appHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedSection?.rawValue ?? LauncherSection.review.rawValue)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(StageHUDTheme.textPrimary)
                Text(selectedSection?.subtitle ?? LauncherSection.review.subtitle)
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundStyle(StageHUDTheme.textMuted)
            }

            Spacer()

            HStack(spacing: 10) {
                if selectedSection == .review || selectedSection == nil, let session = model.selectedSession {
                    Text(session.expression)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(StageHUDTheme.textSecondary)
                }

                launcherButton(
                    model.isRunningGuidedDemo ? "Running Guided Demo..." : "Run Guided Demo",
                    tone: .primary,
                    action: model.runGuidedCalculatorDemo
                )
                .disabled(model.isRunningGuidedDemo)

                launcherButton("Start Console", action: model.startLocalConsole)
            }
        }
    }

    private var reviewSection: some View {
        Group {
            if let latest = model.selectedSession {
                VStack(alignment: .leading, spacing: 18) {
                    reviewSummary(for: latest)
                    ActionSessionPreviewView(session: latest, model: model)
                }
            } else {
                surfaceCard(title: "Active Review") {
                    Text("Run the guided calculator capture to seed the review loop.")
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .foregroundStyle(StageHUDTheme.textSecondary)
                }
            }
        }
    }

    private func reviewSummary(for session: ActionSessionSummary) -> some View {
        surfaceCard(title: "Active Review") {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(session.expression)
                            .font(.system(size: 34, weight: .bold, design: .monospaced))
                            .foregroundStyle(StageHUDTheme.textPrimary)
                        Text("Result \(session.actualResult) ready for playback and notes.")
                            .font(.system(size: 14, weight: .regular, design: .default))
                            .foregroundStyle(StageHUDTheme.textSecondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 10) {
                        metric(label: "Session", value: sessionTimestamp(session))
                        metric(label: "Expected", value: session.expectedResult)
                        metric(label: "Feedback", value: "\(session.feedbackCount)")
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
        }
    }

    private var librarySection: some View {
        surfaceCard(title: "Sessions") {
            if model.recentSessions.isEmpty {
                Text("Generated runs will appear here.")
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundStyle(StageHUDTheme.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(model.recentSessions) { session in
                        sessionRow(session)
                    }
                }
            }
        }
    }

    private var consoleSection: some View {
        surfaceCard(title: "Console") {
            VStack(alignment: .leading, spacing: 12) {
                Text(model.consoleURL.absoluteString)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(StageHUDTheme.textPrimary)
                    .textSelection(.enabled)

                Text(model.consoleStatus)
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundStyle(StageHUDTheme.textSecondary)

                HStack(spacing: 10) {
                    launcherButton("Load Local Console", tone: .primary, action: model.showLocalConsole)
                    launcherButton("Reload", action: model.reloadConsole)
                    launcherButton("Browser", action: model.openWebConsoleInBrowser)
                    launcherButton("Embedded", action: model.openEmbeddedConsole)
                }
            }
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            surfaceCard(title: "Appearance") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Appearance", selection: Binding(
                        get: { model.appearanceMode },
                        set: { model.setAppearanceMode($0) }
                    )) {
                        ForEach(ActionAppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("Switch between system, light, and dark.")
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .foregroundStyle(StageHUDTheme.textSecondary)
                }
            }

            surfaceCard(title: "Environment") {
                VStack(alignment: .leading, spacing: 12) {
                    statusRow(label: "Agent", value: model.agentStatus)
                    statusRow(label: "Accessibility", value: model.accessibilityStatus)
                    statusRow(label: "Screen Recording", value: model.screenRecordingStatus)
                }
            }

            surfaceCard(title: "Utilities") {
                VStack(spacing: 10) {
                    launcherButton("Refresh Permissions", action: model.refreshPermissions)
                    launcherButton("Request Permissions", action: model.requestPermissions)
                    launcherButton("Open Accessibility", action: model.openAccessibilitySettings)
                    launcherButton("Open Screen Recording", action: model.openScreenRecordingSettings)
                    launcherButton("Open Scenarios Folder", action: model.openScenariosFolder)
                }
            }

            if !model.notes.isEmpty {
                surfaceCard(title: "Notes") {
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
    }

    private func iconName(for section: LauncherSection) -> String {
        switch section {
        case .review:
            return "play.square"
        case .library:
            return "square.stack"
        case .console:
            return "terminal"
        case .settings:
            return "slider.horizontal.3"
        }
    }

    private func surfaceCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(StageHUDTheme.textMuted)
            content()
        }
        .padding(18)
        .background(
            ActionChamferedShape(cornerCut: 8)
                .fill(StageHUDTheme.cardFill)
        )
        .overlay(
            ActionChamferedShape(cornerCut: 8)
                .stroke(StageHUDTheme.cardBorder, lineWidth: 1)
        )
    }

    private func metric(label: String, value: String) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(StageHUDTheme.textMuted)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(StageHUDTheme.textPrimary)
        }
    }

    private func sessionRow(_ session: ActionSessionSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.expression)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(StageHUDTheme.textPrimary)
                    Text("Expected \(session.expectedResult)  Actual \(session.actualResult)")
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .foregroundStyle(StageHUDTheme.textSecondary)
                }
                Spacer()
                Text(sessionTimestamp(session))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(StageHUDTheme.textMuted)
            }

            HStack(spacing: 10) {
                launcherButton("Select", tone: .primary, action: { model.selectSession(session) })
                launcherButton("Replay", action: { model.replaySession(session) })
                launcherButton("Reveal", action: { model.revealSession(session) })
                launcherButton("Trace", action: { model.openSessionTrace(session) })
                launcherButton("Feedback", action: { model.openSessionFeedback(session) })
            }
        }
        .padding(14)
        .background(
            ActionChamferedShape(cornerCut: 6)
                .fill(model.selectedSession?.id == session.id ? StageHUDTheme.buttonSecondaryHover : StageHUDTheme.appBackground)
        )
        .overlay(
            ActionChamferedShape(cornerCut: 6)
                .stroke(model.selectedSession?.id == session.id ? StageHUDTheme.panelBorder : StageHUDTheme.cardBorder, lineWidth: 1)
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

    private func sessionTimestamp(_ session: ActionSessionSummary) -> String {
        guard let date = session.startedAt else {
            return session.sessionId
        }
        return sessionDateFormatter.localizedString(for: date, relativeTo: Date())
    }
}
