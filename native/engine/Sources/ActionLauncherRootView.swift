import AppKit
import SwiftUI

struct ActionLauncherRootView: View {
    private enum LauncherSection: String, CaseIterable, Identifiable, Hashable {
        case takes = "Takes"
        case library = "Library"
        case settings = "Settings"

        var id: String { rawValue }

        var subtitle: String {
            switch self {
            case .takes:
                return "Latest session"
            case .library:
                return "All sessions"
            case .settings:
                return "Permissions and preferences"
            }
        }
    }

    private enum LibraryLayout: String {
        case gallery
        case list
    }

    private enum SettingsPane: String, CaseIterable, Identifiable {
        case permissions
        case appearance
        case agent
        case advanced
        case about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .permissions: return "Permissions"
            case .appearance: return "Appearance"
            case .agent: return "Agent"
            case .advanced: return "Advanced"
            case .about: return "About"
            }
        }

        var icon: String {
            switch self {
            case .permissions: return "lock.shield"
            case .appearance: return "paintpalette"
            case .agent: return "cpu"
            case .advanced: return "wrench.and.screwdriver"
            case .about: return "info.circle"
            }
        }

        var subtitle: String {
            switch self {
            case .permissions:
                return "macOS access Action needs for capture and automation."
            case .appearance:
                return "Theme and how the app looks on this Mac."
            case .agent:
                return "Local automation runtime that drives capture."
            case .advanced:
                return "Optional diagnostics and developer tools."
            case .about:
                return "Build details for this install."
            }
        }
    }

    @ObservedObject var model: ActionLauncherViewModel
    @State private var selectedSection: LauncherSection? = .takes
    @State private var librarySearch = ""
    @State private var hoveredLibrarySessionID: String?
    @State private var sessionPendingDelete: ActionSessionSummary?
    @AppStorage("Action.LauncherSidebarIconsOnly") private var sidebarIconsOnly = false
    @AppStorage("Action.LibraryLayout") private var libraryLayoutRaw = LibraryLayout.gallery.rawValue
    @AppStorage("Action.SettingsPane") private var settingsPaneRaw = SettingsPane.permissions.rawValue
    @StateObject private var consoleBridge = ActionEmbeddedWebConsoleBridge()
    private let sessionDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private var sidebarWidth: CGFloat {
        sidebarIconsOnly ? 56 : 200
    }

    private var activeSection: LauncherSection {
        selectedSection ?? .takes
    }

    private var libraryLayout: LibraryLayout {
        get { LibraryLayout(rawValue: libraryLayoutRaw) ?? .gallery }
        nonmutating set { libraryLayoutRaw = newValue.rawValue }
    }

    private var settingsPane: SettingsPane {
        get { SettingsPane(rawValue: settingsPaneRaw) ?? .permissions }
        nonmutating set { settingsPaneRaw = newValue.rawValue }
    }

    private var filteredLibrarySessions: [ActionSessionSummary] {
        let query = librarySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return model.recentSessions
        }
        return model.recentSessions.filter { session in
            session.displayTitle.localizedCaseInsensitiveContains(query)
                || session.actualResult.localizedCaseInsensitiveContains(query)
                || session.sessionId.localizedCaseInsensitiveContains(query)
                || session.expression.localizedCaseInsensitiveContains(query)
        }
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
            }

            footerBar
        }
        .frame(minWidth: 1100, minHeight: 720)
        .background(StageHUDTheme.appBackground)
        .onChange(of: model.reviewSelectionRequestID) { _, _ in
            selectedSection = .takes
        }
        .confirmationDialog(
            "Delete this take?",
            isPresented: Binding(
                get: { sessionPendingDelete != nil },
                set: { if !$0 { sessionPendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: sessionPendingDelete
        ) { session in
            Button("Delete", role: .destructive) {
                try? model.deleteSession(session)
                sessionPendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                sessionPendingDelete = nil
            }
        } message: { session in
            Text("“\(session.displayTitle)” and its files will be removed from disk. This cannot be undone.")
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            sidebarHeader

            VStack(spacing: 2) {
                ForEach([LauncherSection.takes, .library], id: \.self) { section in
                    sidebarItem(section)
                }
            }
            .padding(.horizontal, sidebarIconsOnly ? 8 : 10)
            .padding(.top, 8)

            Spacer(minLength: 0)

            if !sidebarIconsOnly {
                MiraCompanionBadge()
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
            }

            sidebarItem(.settings)
                .padding(.horizontal, sidebarIconsOnly ? 8 : 10)
                .padding(.bottom, 12)
        }
        .frame(width: sidebarWidth)
        .background(StageHUDTheme.railBackground)
    }

    private var sidebarHeader: some View {
        HStack(spacing: 8) {
            if sidebarIconsOnly {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        sidebarIconsOnly = false
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(StageHUDTheme.textSecondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .help("Expand Sidebar")
            } else {
                ActionBrandLockup()

                Spacer(minLength: 0)

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        sidebarIconsOnly = true
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(StageHUDTheme.textMuted)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Collapse Sidebar")
            }
        }
        .padding(.horizontal, sidebarIconsOnly ? 12 : 14)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private func sidebarItem(_ section: LauncherSection) -> some View {
        let selected = activeSection == section
        return Button {
            selectedSection = section
        } label: {
            HStack(spacing: 10) {
                Image(systemName: iconName(for: section))
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)

                if !sidebarIconsOnly {
                    Text(section.rawValue)
                        .font(.system(size: 13, weight: selected ? .semibold : .medium))
                    Spacer(minLength: 0)
                }
            }
            .foregroundStyle(selected ? StageHUDTheme.textPrimary : StageHUDTheme.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: sidebarIconsOnly ? .center : .leading)
            .padding(.horizontal, sidebarIconsOnly ? 0 : 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? StageHUDTheme.buttonSecondaryHover : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .help(sidebarIconsOnly ? section.rawValue : "")
    }

    // MARK: - Main

    private var mainPane: some View {
        Group {
            if activeSection == .settings {
                settingsShell
            } else {
                VStack(spacing: 0) {
                    pageHeader
                        .padding(.horizontal, 28)
                        .padding(.top, 20)
                        .padding(.bottom, 16)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            switch activeSection {
                            case .takes:
                                takesSection
                            case .library:
                                librarySection
                            case .settings:
                                EmptyView()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 28)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        .background(StageHUDTheme.appBackground)
    }

    private var pageHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(activeSection.rawValue)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(StageHUDTheme.textPrimary)
                Text(headerSubtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(StageHUDTheme.textSecondary)
            }

            Spacer(minLength: 0)

            if activeSection == .library, !model.recentSessions.isEmpty {
                librarySearchField
                    .frame(maxWidth: 240)

                libraryLayoutPicker
            }

            if activeSection == .takes || activeSection == .library {
                launcherButton(
                    model.isRunningGuidedDemo ? "Recording…" : "New take",
                    tone: .primary,
                    action: model.runGuidedCalculatorDemo
                )
                .disabled(model.isRunningGuidedDemo)
            }
        }
    }

    private var librarySearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(StageHUDTheme.textMuted)
            TextField("Search takes", text: $librarySearch)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !librarySearch.isEmpty {
                Button {
                    librarySearch = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(StageHUDTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(StageHUDTheme.buttonSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(StageHUDTheme.cardBorder, lineWidth: 1)
        )
    }

    private var libraryLayoutPicker: some View {
        HStack(spacing: 0) {
            layoutToggle(icon: "square.grid.2x2", layout: .gallery, help: "Gallery")
            layoutToggle(icon: "list.bullet", layout: .list, help: "List")
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(StageHUDTheme.buttonSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(StageHUDTheme.cardBorder, lineWidth: 1)
        )
    }

    private func layoutToggle(icon: String, layout: LibraryLayout, help: String) -> some View {
        let selected = libraryLayout == layout
        return Button {
            libraryLayout = layout
        } label: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(selected ? StageHUDTheme.textPrimary : StageHUDTheme.textMuted)
                .frame(width: 30, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selected ? StageHUDTheme.buttonSecondaryHover : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var headerSubtitle: String {
        switch activeSection {
        case .takes:
            if model.selectedSession != nil {
                return "Playback and notes"
            }
            return "Record a demo, then review it here"
        case .library:
            let total = model.recentSessions.count
            if total == 0 {
                return "No sessions yet"
            }
            let shown = filteredLibrarySessions.count
            if !librarySearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "\(shown) of \(total) take\(total == 1 ? "" : "s")"
            }
            return "\(total) take\(total == 1 ? "" : "s")"
        case .settings:
            return activeSection.subtitle
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack(spacing: 16) {
            footerChip(
                label: "Agent",
                value: humanAgentStatus,
                ok: agentIsHealthy
            )
            footerChip(
                label: "Permissions",
                value: permissionSummary,
                ok: permissionsReady
            )

            if model.isRunningGuidedDemo {
                footerChip(label: "Capture", value: "Running", ok: true)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(height: 36)
        .background(StageHUDTheme.footerBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(StageHUDTheme.cardBorder)
                .frame(height: 1)
        }
    }

    private func footerChip(label: String, value: String, ok: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(ok ? Color(nsColor: NSColor.systemGreen) : StageHUDTheme.textMuted.opacity(0.5))
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(StageHUDTheme.textMuted)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(StageHUDTheme.textPrimary)
        }
    }

    private var agentIsHealthy: Bool {
        model.agentStatus.lowercased() == "connected"
    }

    private var humanAgentStatus: String {
        switch model.agentStatus.lowercased() {
        case "connected":
            return "Connected"
        case "offline", "disconnected":
            return "Offline"
        default:
            return model.agentStatus
        }
    }

    private var permissionsReady: Bool {
        model.accessibilityStatus.lowercased() == "granted"
            && model.screenRecordingStatus.lowercased() == "granted"
    }

    private var permissionSummary: String {
        if permissionsReady {
            return "Ready"
        }
        return "AX \(shortPermission(model.accessibilityStatus)) · Screen \(shortPermission(model.screenRecordingStatus))"
    }

    // MARK: - Takes

    private var takesSection: some View {
        Group {
            if let session = model.selectedSession {
                VStack(alignment: .leading, spacing: 14) {
                    takeBanner(for: session)
                    takeStage(for: session)
                }
            } else {
                takesEmptyState
            }
        }
    }

    private var takesEmptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("No takes yet")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(StageHUDTheme.textPrimary)

            Text("Run a short Calculator capture. When it finishes, the take opens here for playback and notes.")
                .font(.system(size: 13))
                .foregroundStyle(StageHUDTheme.textSecondary)
                .frame(maxWidth: 420, alignment: .leading)

            launcherButton(
                model.isRunningGuidedDemo ? "Recording…" : "New take",
                tone: .primary,
                action: model.runGuidedCalculatorDemo
            )
            .disabled(model.isRunningGuidedDemo)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func takeBanner(for session: ActionSessionSummary) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(sessionTimestamp(session))
                        .font(.system(size: 12))
                        .foregroundStyle(StageHUDTheme.textMuted)
                    if let duration = session.formattedDuration {
                        Text("·")
                            .foregroundStyle(StageHUDTheme.textMuted)
                        Text(duration)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(StageHUDTheme.textMuted)
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(session.displayTitle)
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .foregroundStyle(StageHUDTheme.textPrimary)
                    Text("= \(session.actualResult)")
                        .font(.system(size: 18, weight: .medium, design: .monospaced))
                        .foregroundStyle(StageHUDTheme.textSecondary)
                }

                Text("\(session.feedbackCount) note\(session.feedbackCount == 1 ? "" : "s")  ·  N note · 1/2/3 anchors · ⌘↩ save")
                    .font(.system(size: 11))
                    .foregroundStyle(StageHUDTheme.textMuted)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                launcherButton("Show in Finder", action: { model.revealSession(session) })
                launcherButton("Trace", action: { model.openSessionTrace(session) })
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private func takeStage(for session: ActionSessionSummary) -> some View {
        ActionSessionPreviewView(session: session, model: model)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(StageHUDTheme.cardBorder, lineWidth: 1)
            )
    }

    // MARK: - Library

    private var librarySection: some View {
        Group {
            if model.recentSessions.isEmpty {
                libraryEmptyState
            } else if filteredLibrarySessions.isEmpty {
                libraryNoResultsState
            } else if libraryLayout == .gallery {
                libraryGallery
            } else {
                libraryList
            }
        }
    }

    private var libraryEmptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No sessions yet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(StageHUDTheme.textPrimary)
            Text("New takes appear here after you record them.")
                .font(.system(size: 13))
                .foregroundStyle(StageHUDTheme.textSecondary)
            launcherButton(
                model.isRunningGuidedDemo ? "Recording…" : "New take",
                tone: .primary,
                action: model.runGuidedCalculatorDemo
            )
            .disabled(model.isRunningGuidedDemo)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var libraryNoResultsState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No matches")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(StageHUDTheme.textPrimary)
            Text("Nothing matched “\(librarySearch)”.")
                .font(.system(size: 13))
                .foregroundStyle(StageHUDTheme.textSecondary)
            Button("Clear search") { librarySearch = "" }
                .buttonStyle(ActionSettingsPillButtonStyle())
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var libraryGallery: some View {
        let columns = [
            GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 14, alignment: .top),
        ]

        return LazyVGrid(columns: columns, spacing: 14) {
            ForEach(filteredLibrarySessions) { session in
                libraryGalleryCard(session)
            }
        }
    }

    private func libraryGalleryCard(_ session: ActionSessionSummary) -> some View {
        let selected = model.selectedSession?.id == session.id
        let hovered = hoveredLibrarySessionID == session.id

        return Button {
            openSession(session)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    ActionSessionThumbnailView(
                        session: session,
                        width: nil,
                        height: 132,
                        showCaption: false,
                        showDuration: true,
                        showNoteCount: true,
                        cornerRadius: 0,
                        showBorder: false
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 132)
                    .clipped()

                    if hovered {
                        HStack(spacing: 6) {
                            libraryHoverChip("Open") { openSession(session) }
                            libraryHoverChip("Replay") { model.replaySession(session) }
                            libraryHoverChip("Finder") { model.revealSession(session) }
                        }
                        .padding(8)
                        .transition(.opacity)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.displayTitle)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(StageHUDTheme.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text("= \(session.actualResult)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(StageHUDTheme.textSecondary)
                        Text("·")
                            .foregroundStyle(StageHUDTheme.textMuted)
                        Text(sessionTimestamp(session))
                            .font(.system(size: 12))
                            .foregroundStyle(StageHUDTheme.textMuted)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(StageHUDTheme.cardFill)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        selected ? StageHUDTheme.reviewAccent.opacity(0.55) : StageHUDTheme.cardBorder,
                        lineWidth: selected ? 1.5 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredLibrarySessionID = hovering ? session.id : (hoveredLibrarySessionID == session.id ? nil : hoveredLibrarySessionID)
        }
        .contextMenu {
            sessionContextMenu(session)
        }
    }

    private func libraryHoverChip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.62), in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var libraryList: some View {
        VStack(spacing: 6) {
            ForEach(filteredLibrarySessions) { session in
                libraryListRow(session)
            }
        }
    }

    private func libraryListRow(_ session: ActionSessionSummary) -> some View {
        let selected = model.selectedSession?.id == session.id
        let hovered = hoveredLibrarySessionID == session.id

        return Button {
            openSession(session)
        } label: {
            HStack(spacing: 14) {
                ActionSessionThumbnailView(
                    session: session,
                    width: 112,
                    height: 70,
                    showCaption: false,
                    showDuration: true,
                    showNoteCount: false,
                    cornerRadius: 8
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.displayTitle)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(StageHUDTheme.textPrimary)
                        .lineLimit(1)

                    Text("Result \(session.actualResult)")
                        .font(.system(size: 12))
                        .foregroundStyle(StageHUDTheme.textSecondary)

                    HStack(spacing: 8) {
                        Text(sessionTimestamp(session))
                            .font(.system(size: 11))
                            .foregroundStyle(StageHUDTheme.textMuted)
                        if let duration = session.formattedDuration {
                            Text(duration)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(StageHUDTheme.textMuted)
                        }
                        if session.feedbackCount > 0 {
                            Text("\(session.feedbackCount) note\(session.feedbackCount == 1 ? "" : "s")")
                                .font(.system(size: 11))
                                .foregroundStyle(StageHUDTheme.textMuted)
                        }
                    }
                }

                Spacer(minLength: 0)

                if hovered {
                    HStack(spacing: 6) {
                        launcherButton("Replay", action: { model.replaySession(session) })
                        launcherButton("Delete", tone: .destructive, action: { sessionPendingDelete = session })
                    }
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(StageHUDTheme.textMuted)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected || hovered ? StageHUDTheme.buttonSecondaryHover : StageHUDTheme.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        selected ? StageHUDTheme.reviewAccent.opacity(0.45) : StageHUDTheme.cardBorder,
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredLibrarySessionID = hovering ? session.id : (hoveredLibrarySessionID == session.id ? nil : hoveredLibrarySessionID)
        }
        .contextMenu {
            sessionContextMenu(session)
        }
    }

    @ViewBuilder
    private func sessionContextMenu(_ session: ActionSessionSummary) -> some View {
        Button("Open") { openSession(session) }
        Button("Replay") { model.replaySession(session) }
        Divider()
        Button("Show in Finder") { model.revealSession(session) }
        Button("Open Trace") { model.openSessionTrace(session) }
        Button("Open Notes") { model.openSessionFeedback(session) }
        Divider()
        Button("Delete…", role: .destructive) {
            sessionPendingDelete = session
        }
    }

    private func openSession(_ session: ActionSessionSummary) {
        model.selectSession(session)
        selectedSection = .takes
    }

    // MARK: - Settings

    private var settingsShell: some View {
        HStack(spacing: 0) {
            settingsSubnav
                .frame(width: 200)

            Rectangle()
                .fill(StageHUDTheme.cardBorder)
                .frame(width: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ActionSettingsPageHeader(
                        icon: settingsPane.icon,
                        title: settingsPane.title,
                        subtitle: settingsPane.subtitle
                    )

                    settingsPaneContent
                }
                .frame(maxWidth: 720, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var settingsSubnav: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(StageHUDTheme.textPrimary)
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 12)

            VStack(spacing: 2) {
                ForEach(SettingsPane.allCases) { pane in
                    settingsSubnavItem(pane)
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(StageHUDTheme.railBackground.opacity(0.55))
    }

    private func settingsSubnavItem(_ pane: SettingsPane) -> some View {
        let selected = settingsPane == pane
        return Button {
            settingsPane = pane
        } label: {
            HStack(spacing: 10) {
                Image(systemName: pane.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selected ? StageHUDTheme.reviewAccent : StageHUDTheme.textMuted)
                    .frame(width: 18)
                Text(pane.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? StageHUDTheme.textPrimary : StageHUDTheme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? StageHUDTheme.buttonSecondaryHover : Color.clear)
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(selected ? StageHUDTheme.reviewAccent : Color.clear)
                    .frame(width: 3)
                    .padding(.vertical, 8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(pane.title)
    }

    @ViewBuilder
    private var settingsPaneContent: some View {
        switch settingsPane {
        case .permissions:
            settingsPermissionsPage
        case .appearance:
            settingsAppearancePage
        case .agent:
            settingsAgentPage
        case .advanced:
            settingsAdvancedPage
        case .about:
            settingsAboutPage
        }
    }

    private var settingsPermissionsPage: some View {
        let axGranted = model.accessibilityStatus.lowercased() == "granted"
        let screenGranted = model.screenRecordingStatus.lowercased() == "granted"

        return VStack(alignment: .leading, spacing: 18) {
            if !permissionsReady {
                ActionSettingsSection(title: "Needs attention") {
                    ActionSettingsRow(
                        icon: "exclamationmark.triangle.fill",
                        iconColor: Color(nsColor: .systemOrange),
                        title: "Some permissions are missing",
                        subtitle: "Capture and automation will be limited until both Accessibility and Screen Recording are granted."
                    ) {
                        Button("Request access") {
                            model.requestPermissions()
                        }
                        .buttonStyle(ActionSettingsPillButtonStyle(primary: true))
                    }
                }
            }

            ActionSettingsSection(title: "macOS privacy") {
                ActionSettingsPermissionRow(
                    title: "Accessibility",
                    detail: "Required to focus apps, click, type, and read UI structure.",
                    granted: axGranted,
                    statusLabel: permissionStatusLabel(model.accessibilityStatus),
                    primaryActionTitle: "Grant",
                    onPrimary: model.requestPermissions,
                    onOpenSettings: model.openAccessibilitySettings
                )

                ActionSettingsDivider()

                ActionSettingsPermissionRow(
                    title: "Screen Recording",
                    detail: "Required for screenshots and ScreenCaptureKit recording.",
                    granted: screenGranted,
                    statusLabel: permissionStatusLabel(model.screenRecordingStatus),
                    primaryActionTitle: "Grant",
                    onPrimary: model.requestPermissions,
                    onOpenSettings: model.openScreenRecordingSettings
                )
            }

            HStack(spacing: 8) {
                Button("Check again", action: model.refreshPermissions)
                    .buttonStyle(ActionSettingsPillButtonStyle())
                if !permissionsReady {
                    Button("Request all", action: model.requestPermissions)
                        .buttonStyle(ActionSettingsPillButtonStyle(primary: true))
                }
            }
        }
    }

    private var settingsAppearancePage: some View {
        ActionSettingsSection(title: "Theme") {
            ActionSettingsControlRow(
                title: "Appearance",
                subtitle: "System follows macOS. Light and Dark force the theme.",
                icon: "circle.lefthalf.filled"
            ) {
                Picker("Appearance", selection: Binding(
                    get: { model.appearanceMode },
                    set: { model.setAppearanceMode($0) }
                )) {
                    ForEach(ActionAppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
            }
        }
    }

    private var settingsAgentPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            ActionSettingsSection(title: "Runtime") {
                ActionSettingsRow(
                    icon: "cpu",
                    iconColor: agentIsHealthy ? Color(nsColor: .systemGreen) : StageHUDTheme.textMuted,
                    title: "Local agent",
                    subtitle: "Handles automation methods and capture orchestration over a local WebSocket."
                ) {
                    ActionSettingsStatusBadge(
                        text: humanAgentStatus,
                        kind: agentIsHealthy ? .ok : .offline
                    )
                }

                ActionSettingsDivider()

                ActionSettingsRow(
                    icon: "network",
                    title: "Endpoint",
                    subtitle: "ws://127.0.0.1:4319"
                ) {
                    EmptyView()
                }
            }

            Text("The agent starts with Action. If it shows Offline, restart the app.")
                .font(.system(size: 12))
                .foregroundStyle(StageHUDTheme.textMuted)
        }
    }

    private var settingsAdvancedPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            ActionSettingsSection(title: "Local HUD") {
                ActionSettingsRow(
                    icon: "safari",
                    title: "Web diagnostics",
                    subtitle: "Optional local page for deeper operator tools. Day-to-day work stays in Takes."
                ) {
                    ActionSettingsStatusBadge(
                        text: humanConsoleStatus,
                        kind: model.consoleIsReachable ? .ok : .neutral
                    )
                }

                ActionSettingsDivider()

                ActionSettingsControlRow(
                    title: "Controls",
                    subtitle: model.consoleURL.absoluteString,
                    icon: "slider.horizontal.3"
                ) {
                    HStack(spacing: 8) {
                        Button(model.consoleIsReachable ? "Open" : "Start") {
                            if model.consoleIsReachable {
                                model.openWebConsoleInBrowser()
                            } else {
                                model.startLocalConsole()
                            }
                        }
                        .buttonStyle(ActionSettingsPillButtonStyle(primary: true))

                        if model.consoleIsReachable {
                            Button("Restart", action: model.restartLocalConsole)
                                .buttonStyle(ActionSettingsPillButtonStyle())
                            Button("Stop", action: model.stopLocalConsole)
                                .buttonStyle(ActionSettingsPillButtonStyle())
                        }

                        Button("Pop out", action: model.openEmbeddedConsole)
                            .buttonStyle(ActionSettingsPillButtonStyle())
                    }
                }

                if model.consoleIsReachable {
                    ActionSettingsDivider()

                    DisclosureGroup("Embedded preview") {
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
                        .frame(minHeight: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(StageHUDTheme.cardBorder, lineWidth: 1)
                        )
                        .padding(.top, 10)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 14)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(StageHUDTheme.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }

            ActionSettingsSection(title: "Files") {
                ActionSettingsRow(
                    icon: "folder",
                    title: "Scenarios folder",
                    subtitle: "Open the on-disk scenarios directory.",
                    onTap: model.openScenariosFolder
                )
            }
        }
    }

    private var settingsAboutPage: some View {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        let bundleId = Bundle.main.bundleIdentifier ?? "dev.action.Action"

        return VStack(alignment: .leading, spacing: 18) {
            ActionSettingsSection(title: "Action") {
                ActionSettingsRow(
                    icon: "play.fill",
                    iconColor: StageHUDTheme.reviewAccent,
                    title: "Action",
                    subtitle: "Native-first capture workstation for macOS."
                ) {
                    EmptyView()
                }

                ActionSettingsDivider()

                ActionSettingsRow(
                    icon: "number",
                    title: "Version",
                    subtitle: "\(version) (\(build))"
                ) {
                    EmptyView()
                }

                ActionSettingsDivider()

                ActionSettingsRow(
                    icon: "app.badge",
                    title: "Bundle ID",
                    subtitle: bundleId
                ) {
                    EmptyView()
                }
            }
        }
    }

    private var humanConsoleStatus: String {
        if model.consoleIsReachable {
            return "Ready"
        }
        if model.consoleAutoEnsureEnabled {
            return "Starting…"
        }
        return "Off"
    }

    private func permissionStatusLabel(_ status: String) -> String {
        switch status.lowercased() {
        case "granted":
            return "Granted"
        case "denied":
            return "Denied"
        case "unknown":
            return "Unknown"
        default:
            return status.capitalized
        }
    }

    // MARK: - Shared

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(StageHUDTheme.cardFill)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(StageHUDTheme.cardBorder, lineWidth: 1)
            )
    }

    private func iconName(for section: LauncherSection) -> String {
        switch section {
        case .takes:
            return "play.rectangle"
        case .library:
            return "square.stack"
        case .settings:
            return "gearshape"
        }
    }

    private func shortPermission(_ status: String) -> String {
        switch status.lowercased() {
        case "granted":
            return "OK"
        case "denied":
            return "Denied"
        case "unknown":
            return "Unknown"
        default:
            return status
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
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(foreground(configuration: configuration))
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(fill(configuration: configuration))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(border(configuration: configuration), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.88 : 1)
    }

    private func fill(configuration: Configuration) -> Color {
        switch tone {
        case .primary:
            return configuration.isPressed
                ? StageHUDTheme.buttonPrimaryBottom
                : StageHUDTheme.buttonPrimaryTop
        case .secondary:
            return configuration.isPressed
                ? StageHUDTheme.buttonSecondaryHover
                : StageHUDTheme.buttonSecondary
        case .destructive:
            return StageHUDTheme.accentRecording.opacity(configuration.isPressed ? 0.75 : 0.9)
        }
    }

    private func foreground(configuration: Configuration) -> Color {
        switch tone {
        case .primary:
            return StageHUDTheme.buttonPrimaryText
        case .secondary, .destructive:
            return StageHUDTheme.textPrimary.opacity(configuration.isPressed ? 0.85 : 1)
        }
    }

    private func border(configuration: Configuration) -> Color {
        switch tone {
        case .primary:
            return Color.clear
        case .secondary, .destructive:
            return StageHUDTheme.cardBorder
        }
    }
}
