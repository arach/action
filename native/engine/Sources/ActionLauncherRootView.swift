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
    @AppStorage("Action.LauncherSidebarIconsOnly") private var sidebarIconsOnly = false
    @StateObject private var consoleBridge = ActionEmbeddedWebConsoleBridge()
    private let sessionDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private var sidebarWidth: (min: CGFloat, ideal: CGFloat, max: CGFloat) {
        if sidebarIconsOnly {
            return (52, 52, 52)
        }
        return (188, 208, 232)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar

                Rectangle()
                    .fill(StageHUDTheme.cardBorder)
                    .frame(width: 1)

                mainPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(StageHUDTheme.appBackground)
            }

            footerBar
        }
        .frame(minWidth: 1180, minHeight: 760)
        .background(StageHUDTheme.appBackground)
        .onChange(of: model.reviewSelectionRequestID) { _, _ in
            selectedSection = .review
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            sidebarHeader

            List(selection: $selectedSection) {
                Section(sidebarIconsOnly ? "" : "Workspace") {
                    ForEach([LauncherSection.review, .library, .console], id: \.self) { section in
                        sidebarRow(for: section)
                            .tag(Optional(section))
                    }
                }
            }
            .background(StageHUDTheme.railBackground)
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Spacer(minLength: 0)

            settingsRow
                .padding(.horizontal, sidebarIconsOnly ? 4 : 8)
                .padding(.bottom, 8)
        }
        .frame(width: sidebarWidth.ideal)
        .background(StageHUDTheme.railBackground)
    }

    private var sidebarHeader: some View {
        HStack(spacing: 8) {
            if sidebarIconsOnly {
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        sidebarIconsOnly = false
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(StageHUDTheme.textSecondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Expand Sidebar")
                .frame(width: 28, height: 28)

                Spacer(minLength: 0)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Action")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(StageHUDTheme.textPrimary)
                    Text("Capture workstation")
                        .font(.system(size: 11, weight: .regular, design: .default))
                        .foregroundStyle(StageHUDTheme.textMuted)
                }

                Spacer(minLength: 0)

                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        sidebarIconsOnly = true
                    }
                } label: {
                    Image(systemName: "sidebar.squares.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(StageHUDTheme.textSecondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Collapse Sidebar")
            }
        }
        .padding(.horizontal, sidebarIconsOnly ? 6 : 12)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var mainPane: some View {
        VStack(spacing: 0) {
            if (selectedSection ?? .review) != .review {
                appHeader
                    .padding(.horizontal, 30)
                    .padding(.top, 20)
                    .padding(.bottom, 12)
            } else {
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 18)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, (selectedSection ?? .review) == .review ? 18 : 30)
                .padding(.top, (selectedSection ?? .review) == .review ? 8 : 0)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
        .background(mainPaneBackground)
    }

    @ViewBuilder
    private var mainPaneBackground: some View {
        if (selectedSection ?? .review) == .review {
            LinearGradient(
                colors: [
                    StageHUDTheme.reviewCanvas,
                    StageHUDTheme.reviewPanel.opacity(0.92),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            StageHUDTheme.appBackground
        }
    }

    private var footerBar: some View {
        HStack(spacing: 16) {
            footerSlot(
                icon: model.consoleIsReachable ? "dot.radiowaves.left.and.right" : "bolt.slash",
                label: "Console",
                value: footerConsoleValue
            )

            footerDivider

            footerSlot(
                icon: "brain",
                label: "Agent",
                value: model.agentStatus
            )

            footerDivider

            footerSlot(
                icon: "hand.raised",
                label: "Permissions",
                value: permissionSummary
            )

            Spacer()

            footerSlot(
                icon: "rectangle.stack",
                label: "View",
                value: selectedSection?.rawValue ?? LauncherSection.review.rawValue
            )
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(StageHUDTheme.footerBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(StageHUDTheme.cardBorder)
                .frame(height: 1)
        }
    }

    private var appHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedSection?.rawValue ?? LauncherSection.review.rawValue)
                    .font(.system(size: 19, weight: .bold, design: .monospaced))
                    .foregroundStyle(StageHUDTheme.textPrimary)
                Text(selectedSection?.subtitle ?? LauncherSection.review.subtitle)
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundStyle(StageHUDTheme.textSecondary)
            }

            Spacer(minLength: 0)

            headerActions
        }
    }

    @ViewBuilder
    private var headerActions: some View {
        switch selectedSection ?? .review {
        case .review:
            HStack(spacing: 10) {
                if let session = model.selectedSession {
                    Text(session.expression.replacingOccurrences(of: " ", with: ""))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(StageHUDTheme.textSecondary)
                }

                launcherButton(
                    model.isRunningGuidedDemo ? "Running Guided Demo..." : "Run Guided Demo",
                    tone: .primary,
                    action: model.runGuidedCalculatorDemo
                )
                .disabled(model.isRunningGuidedDemo)
            }
        case .library:
            EmptyView()
        case .console:
            HStack(spacing: 10) {
                launcherButton("Restart Console", tone: .primary, action: model.restartLocalConsole)
                launcherButton("Browser", action: model.openWebConsoleInBrowser)
            }
        case .settings:
            HStack(spacing: 10) {
                launcherButton("Refresh Permissions", action: model.refreshPermissions)
            }
        }
    }

    @ViewBuilder
    private func sidebarRow(for section: LauncherSection) -> some View {
        if sidebarIconsOnly {
            Image(systemName: iconName(for: section))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(StageHUDTheme.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 30)
                .help(section.rawValue)
        } else {
            Label(section.rawValue, systemImage: iconName(for: section))
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(StageHUDTheme.textPrimary)
        }
    }

    private var settingsRow: some View {
        Button {
            selectedSection = .settings
        } label: {
            HStack(spacing: 10) {
                Image(systemName: iconName(for: .settings))
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: sidebarIconsOnly ? nil : 18)

                if !sidebarIconsOnly {
                    Text(LauncherSection.settings.rawValue)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                    Spacer()
                }
            }
            .foregroundStyle(selectedSection == .settings ? StageHUDTheme.textPrimary : StageHUDTheme.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: sidebarIconsOnly ? .center : .leading)
            .padding(.horizontal, sidebarIconsOnly ? 0 : 10)
            .background(selectedSection == .settings ? StageHUDTheme.buttonSecondaryHover : Color.clear)
            .clipShape(ActionChamferedShape(cornerCut: 4))
        }
        .buttonStyle(.plain)
        .help(sidebarIconsOnly ? LauncherSection.settings.rawValue : "")
    }

    private var footerConsoleValue: String {
        if model.consoleAutoEnsureEnabled {
            return model.consoleIsReachable ? "Watchdog online" : "Bootstrapping"
        }
        return model.consoleIsReachable ? "Manual online" : "Paused"
    }

    private var permissionSummary: String {
        "\(shortPermission(model.accessibilityStatus)) / \(shortPermission(model.screenRecordingStatus))"
    }

    private var reviewSection: some View {
        Group {
            if let latest = model.selectedSession {
                VStack(alignment: .leading, spacing: 12) {
                    reviewDeck(for: latest)
                    reviewStage(for: latest)
                }
            } else {
                surfaceCard(title: "Review") {
                    Text("Run the guided calculator capture to seed the review loop.")
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .foregroundStyle(StageHUDTheme.textSecondary)
                }
            }
        }
    }

    private func reviewDeck(for session: ActionSessionSummary) -> some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("REVIEW DECK")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.6))
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(session.expression.replacingOccurrences(of: " ", with: ""))
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white)
                    Text("=\(session.actualResult)")
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.72))
                }
                Text("Playback, annotate, and export from a single stage.")
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundStyle(Color.white.opacity(0.78))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 10) {
                HStack(spacing: 8) {
                    darkStatusBadge(sessionTimestamp(session))
                    darkStatusBadge("Feedback \(session.feedbackCount)")
                }
                HStack(spacing: 8) {
                    launcherButton("Replay", tone: .primary, action: { model.replaySession(session) })
                    launcherButton("Reveal", action: { model.revealSession(session) })
                    launcherButton("Trace", action: { model.openSessionTrace(session) })
                    launcherButton("Files", action: { model.openSessionFeedback(session) })
                }
            }
        }
        .padding(22)
        .background(reviewDeckBackground)
        .overlay(
            ActionChamferedShape(cornerCut: 7)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func reviewStage(for session: ActionSessionSummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ActionSessionPreviewView(session: session, model: model)
        }
        .padding(12)
        .background(
            ActionChamferedShape(cornerCut: 8)
                .fill(StageHUDTheme.reviewPanel.opacity(0.9))
        )
        .overlay(
            ActionChamferedShape(cornerCut: 8)
                .stroke(StageHUDTheme.reviewStrokeStrong, lineWidth: 1)
        )
        .shadow(color: StageHUDTheme.panelShadow.opacity(0.12), radius: 18, x: 0, y: 8)
    }

    private func statusBadge(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(StageHUDTheme.textMuted)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(StageHUDTheme.buttonSecondary)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(StageHUDTheme.cardBorder, lineWidth: 1)
            )
    }

    private func darkStatusBadge(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.82))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
    }

    private var reviewDeckBackground: some View {
        ActionChamferedShape(cornerCut: 7)
            .fill(
                LinearGradient(
                    colors: [
                        Color(nsColor: NSColor(calibratedWhite: 0.12, alpha: 1)),
                        Color(nsColor: NSColor(calibratedRed: 0.16, green: 0.18, blue: 0.22, alpha: 1)),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
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
        VStack(alignment: .leading, spacing: 18) {
            surfaceCard(title: "Runtime") {
                HStack(alignment: .center, spacing: 18) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(model.consoleIsReachable ? Color.green : Color.gray.opacity(0.6))
                            .frame(width: 8, height: 8)
                        Text(model.consoleStatus)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(StageHUDTheme.textPrimary)
                    }

                    Text(model.consoleDetail)
                        .font(.system(size: 11, weight: .regular, design: .default))
                        .foregroundStyle(StageHUDTheme.textSecondary)
                        .lineLimit(1)

                    Spacer()

                    metric(label: "Reachable", value: model.consoleIsReachable ? "Yes" : "No")
                    metric(label: "Managed", value: model.consoleIsManagedByAction ? "Action" : "External")
                }
            }

            surfaceCard(title: "Console Surface") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        launcherButton("Start", tone: .primary, action: model.startLocalConsole)
                        launcherButton("Stop", action: model.stopLocalConsole)
                        launcherButton("Restart", action: model.restartLocalConsole)
                        launcherButton("Reload", action: {
                            consoleBridge.reload()
                            model.refreshConsoleState()
                        })
                        launcherButton("Inspector", action: consoleBridge.showInspector)
                        Spacer()
                        launcherButton("Browser", action: model.openWebConsoleInBrowser)
                        launcherButton("Pop Out", action: model.openEmbeddedConsole)
                    }

                    ActionEmbeddedWebConsoleView(
                        url: model.consoleURL,
                        bridge: consoleBridge,
                        onStatusChange: { status in
                            model.setConsoleStatus(status)
                        },
                        onCommand: { command in
                            model.handleWebViewCommand(command)
                        }
                    )
                    .frame(minHeight: 540)
                    .clipShape(ActionChamferedShape(cornerCut: 6))
                    .overlay(
                        ActionChamferedShape(cornerCut: 6)
                            .stroke(StageHUDTheme.cardBorder, lineWidth: 1)
                    )

                    HStack(spacing: 10) {
                        Text(model.consoleURL.absoluteString)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(StageHUDTheme.textMuted)
                            .textSelection(.enabled)

                        Spacer()

                        launcherButton("Copy Launch Command", action: model.copyLocalConsoleCommand)
                        launcherButton("Open Log", action: model.openConsoleLog)
                    }
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

    private var footerDivider: some View {
        Rectangle()
            .fill(StageHUDTheme.cardBorder)
            .frame(width: 1, height: 14)
    }

    private func footerSlot(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(StageHUDTheme.textMuted)
                .frame(width: 12)

            Text(label)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(StageHUDTheme.textMuted)

            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(StageHUDTheme.textPrimary)
                .lineLimit(1)
        }
    }

    private func shortPermission(_ status: String) -> String {
        switch status.lowercased() {
        case "granted":
            return "Ready"
        case "denied":
            return "Denied"
        case "unknown":
            return "Unknown"
        default:
            return status
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
            ActionChamferedShape(cornerCut: 6)
                .fill(StageHUDTheme.cardFill)
        )
        .overlay(
            ActionChamferedShape(cornerCut: 6)
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
        HStack(alignment: .top, spacing: 16) {
            ActionSessionThumbnailView(session: session)

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
            .frame(maxWidth: .infinity, alignment: .leading)
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
            .buttonStyle(ActionLauncherButtonStyle(tone: tone))
    }

    private func sessionTimestamp(_ session: ActionSessionSummary) -> String {
        guard let date = session.startedAt else {
            return session.sessionId
        }
        return sessionDateFormatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct ActionLauncherButtonStyle: ButtonStyle {
    let tone: StageHUDViewModel.ButtonTone

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(foregroundColor(configuration: configuration))
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(background(configuration: configuration))
            .overlay(
                ActionChamferedShape(cornerCut: 5)
                    .stroke(borderColor(configuration: configuration), lineWidth: 1)
            )
            .clipShape(ActionChamferedShape(cornerCut: 5))
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private func background(configuration: Configuration) -> some View {
        Group {
            switch tone {
            case .primary:
                Color(configuration.isPressed ? StageHUDTheme.buttonPrimaryBottom : StageHUDTheme.buttonPrimaryTop)
            case .secondary:
                Color(configuration.isPressed ? StageHUDTheme.buttonSecondaryHover : StageHUDTheme.buttonSecondary)
            case .destructive:
                Color(StageHUDTheme.accentRecording.opacity(configuration.isPressed ? 0.76 : 0.86))
            }
        }
    }

    private func foregroundColor(configuration: Configuration) -> Color {
        switch tone {
        case .primary:
            return StageHUDTheme.buttonPrimaryText.opacity(configuration.isPressed ? 0.88 : 1)
        case .secondary, .destructive:
            return StageHUDTheme.textPrimary.opacity(configuration.isPressed ? 0.88 : 1)
        }
    }

    private func borderColor(configuration: Configuration) -> Color {
        switch tone {
        case .primary:
            return StageHUDTheme.panelBorder.opacity(configuration.isPressed ? 1 : 0.9)
        case .secondary, .destructive:
            return StageHUDTheme.cardBorder.opacity(configuration.isPressed ? 1 : 0.95)
        }
    }
}
