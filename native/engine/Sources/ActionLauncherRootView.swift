import AppKit
import SwiftUI

struct ActionLauncherRootView: View {
    private enum LauncherSection: String, CaseIterable, Identifiable, Hashable {
        case home = "Home"
        case scenarios = "Scenarios"
        case runs = "Runs"
        case library = "Library"
        case settings = "Settings"

        var id: String { rawValue }

        var subtitle: String {
            switch self {
            case .home:
                return "Overview and shortcuts"
            case .scenarios:
                return "Plans you can run"
            case .runs:
                return "Everything that has run"
            case .library:
                return "Captured takes"
            case .settings:
                return "Permissions and preferences"
            }
        }
    }

    private enum RunKindFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case drive = "Drive"
        case inspection = "Inspect"
        case capture = "Capture"

        var id: String { rawValue }

        var kind: ActionRunKind? {
            switch self {
            case .all: return nil
            case .drive: return .drive
            case .inspection: return .inspection
            case .capture: return .capture
            }
        }

        /// The chip carries the same glyph the ledger row uses. That pairing is
        /// what lets the row drop the repeated "DRIVE"/"INSPECT" caption without
        /// the symbol becoming a riddle.
        var icon: String? { kind?.icon }
    }

    private enum RunOutcomeFilter: String, CaseIterable, Identifiable {
        case any = "Any outcome"
        case running = "Running"
        case unfinished = "Unfinished"
        case ok = "Done"
        case failed = "Failed"
        case stopped = "Stopped"

        var id: String { rawValue }

        var outcome: ActionRunOutcome? {
            switch self {
            case .any: return nil
            case .running: return .running
            case .unfinished: return .unfinished
            case .ok: return .ok
            case .failed: return .failed
            case .stopped: return .stopped
            }
        }
    }

    /// What a click on a run row will actually do. Rows are not uniform — a
    /// capture opens review, a drive with a snapshot opens the image, anything
    /// else can only be revealed on disk — so the row has to say which.
    private enum RunPrimaryAction {
        case review
        case snapshot
        case reveal

        var icon: String {
            switch self {
            case .review: return "play.rectangle"
            case .snapshot: return "photo"
            case .reveal: return "folder"
            }
        }

        /// Destination, not verb. Every row carries this at rest, so it has to be
        /// short enough to sit in the ledger without competing with the title.
        var shortLabel: String {
            switch self {
            case .review: return "Review"
            case .snapshot: return "Snapshot"
            case .reveal: return "Finder"
            }
        }

        var label: String {
            switch self {
            case .review: return "Open review"
            case .snapshot: return "Open snapshot"
            case .reveal: return "Show in Finder"
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
    @State private var selectedSection: LauncherSection? = .home
    @State private var librarySearch = ""
    @State private var runsSearch = ""
    @State private var runKindFilter: RunKindFilter = .all
    @State private var runOutcomeFilter: RunOutcomeFilter = .any
    @FocusState private var runsSearchFocused: Bool
    @State private var hoveredRunKindFilter: RunKindFilter?
    @State private var hoveredRunsReset = false
    @State private var hoveredRunsClear = false
    @State private var hoveredRunID: String?
    @State private var hoveredDestinationID: String?
    @State private var hoveredLibrarySessionID: String?
    @State private var sessionPendingDelete: ActionSessionSummary?
    @State private var showKeyboardCheatSheet = false
    @AppStorage("Action.LauncherSidebarIconsOnly") private var sidebarIconsOnly = false
    /// The rail's expanded width, remembered across launches and across a
    /// collapse, so re-expanding returns to the width the operator chose.
    @AppStorage("Action.LauncherSidebarLabelWidth") private var sidebarLabelWidth = 200.0
    /// Width to render mid-drag. Kept out of storage so an abandoned drag leaves
    /// nothing behind.
    @State private var sidebarPreviewWidth: CGFloat?
    @AppStorage("Action.LibraryLayout") private var libraryLayoutRaw = LibraryLayout.gallery.rawValue
    @AppStorage("Action.SettingsPane") private var settingsPaneRaw = SettingsPane.permissions.rawValue
    private let sessionDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    /// Collapsed rail width. Wide enough for a 34pt tap target plus its inset.
    private static let sidebarCompactWidth: CGFloat = 56

    private var sidebarWidth: CGFloat {
        // Mid-drag the preview wins outright: dragging left from an expanded
        // rail has to be able to travel below the minimum toward the collapse
        // threshold, which is the whole feel of the gesture.
        if let sidebarPreviewWidth {
            return max(Self.sidebarCompactWidth, sidebarPreviewWidth)
        }
        return sidebarIconsOnly
            ? Self.sidebarCompactWidth
            : ActionSidebarResizeGeometry.default.committedWidth(CGFloat(sidebarLabelWidth))
    }

    /// True while the rail is narrow enough that labels no longer fit — during a
    /// drag this follows the preview, so labels drop out as the edge crosses the
    /// threshold rather than snapping at the end.
    private var sidebarShowsIconsOnly: Bool {
        if let sidebarPreviewWidth {
            return sidebarPreviewWidth <= ActionSidebarResizeGeometry.default.collapseLabelWidth
        }
        return sidebarIconsOnly
    }

    private var activeSection: LauncherSection {
        selectedSection ?? .home
    }

    private var libraryLayout: LibraryLayout {
        get { LibraryLayout(rawValue: libraryLayoutRaw) ?? .gallery }
        nonmutating set { libraryLayoutRaw = newValue.rawValue }
    }

    private var settingsPane: SettingsPane {
        get { SettingsPane(rawValue: settingsPaneRaw) ?? .permissions }
        nonmutating set { settingsPaneRaw = newValue.rawValue }
    }

    private var librarySessions: [ActionSessionSummary] {
        model.recentSessions.filter(\.isCalculatorTake)
    }

    private var filteredLibrarySessions: [ActionSessionSummary] {
        let query = librarySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return librarySessions
        }
        return librarySessions.filter { session in
            session.displayTitle.localizedCaseInsensitiveContains(query)
                || session.subtitle.localizedCaseInsensitiveContains(query)
                || session.actualResult.localizedCaseInsensitiveContains(query)
                || session.sessionId.localizedCaseInsensitiveContains(query)
                || session.expression.localizedCaseInsensitiveContains(query)
        }
    }

    /// One filter, applied three constraints at a time. Every count the surface
    /// quotes — chip badges, header, the recovery offers in the no-match state —
    /// comes from here with one constraint swapped out, so no two of them can
    /// drift apart.
    private func runsMatching(
        kind: RunKindFilter,
        outcome: RunOutcomeFilter,
        query rawQuery: String
    ) -> [ActionSessionSummary] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.recentSessions.filter { session in
            if let kind = kind.kind, session.kind != kind {
                return false
            }
            if let outcome = outcome.outcome, session.outcome != outcome {
                return false
            }
            if query.isEmpty {
                return true
            }
            return session.displayTitle.localizedCaseInsensitiveContains(query)
                || session.subtitle.localizedCaseInsensitiveContains(query)
                || session.sessionId.localizedCaseInsensitiveContains(query)
                || session.state.localizedCaseInsensitiveContains(query)
                || session.agent.localizedCaseInsensitiveContains(query)
                || session.kind.rawValue.localizedCaseInsensitiveContains(query)
        }
    }

    private var filteredRuns: [ActionSessionSummary] {
        runsMatching(kind: runKindFilter, outcome: runOutcomeFilter, query: runsSearch)
    }

    /// Everything the strip has narrowed to *except* by kind. The kind segments
    /// count against this, so each segment answers "how many would I get if I
    /// clicked it" instead of advertising rows the search already excluded.
    private var runsKindCounts: [ActionRunKind: Int] {
        var counts: [ActionRunKind: Int] = [:]
        for session in runsMatching(kind: .all, outcome: runOutcomeFilter, query: runsSearch) {
            counts[session.kind, default: 0] += 1
        }
        return counts
    }

    private func runsKindCount(_ filter: RunKindFilter) -> Int {
        guard let kind = filter.kind else {
            return runsKindCounts.values.reduce(0, +)
        }
        return runsKindCounts[kind] ?? 0
    }

    private func clearRunsFilters() {
        runKindFilter = .all
        runOutcomeFilter = .any
        runsSearch = ""
    }

    private var runsSearchQuery: String {
        runsSearch.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var runsFiltersActive: Bool {
        runKindFilter != .all || runOutcomeFilter != .any || !runsSearchQuery.isEmpty
    }

    /// One active constraint, priced by what dropping it would restore. The
    /// no-match state is a dead end otherwise: the operator can see that nothing
    /// matched but not which of three narrowings is to blame.
    private struct RunFilterRelease: Identifiable {
        let id: String
        let name: String
        let restores: Int
        let apply: () -> Void
    }

    private var runsFilterReleases: [RunFilterRelease] {
        var releases: [RunFilterRelease] = []
        if !runsSearchQuery.isEmpty {
            releases.append(
                RunFilterRelease(
                    id: "search",
                    name: "“\(runsSearchQuery)”",
                    restores: runsMatching(kind: runKindFilter, outcome: runOutcomeFilter, query: "").count,
                    apply: { runsSearch = "" }
                )
            )
        }
        if runKindFilter != .all {
            releases.append(
                RunFilterRelease(
                    id: "kind",
                    name: runKindFilter.rawValue,
                    restores: runsMatching(kind: .all, outcome: runOutcomeFilter, query: runsSearch).count,
                    apply: { runKindFilter = .all }
                )
            )
        }
        if runOutcomeFilter != .any {
            releases.append(
                RunFilterRelease(
                    id: "outcome",
                    name: runOutcomeFilter.rawValue,
                    restores: runsMatching(kind: runKindFilter, outcome: .any, query: runsSearch).count,
                    apply: { runOutcomeFilter = .any }
                )
            )
        }
        return releases.filter { $0.restores > 0 }
    }

    /// Runs are already sorted newest-first, so day buckets fall out in order.
    /// Grouping is what keeps 260 rows from reading as one undifferentiated
    /// column of "10 hrs ago".
    private var runDayGroups: [(key: Date, runs: [ActionSessionSummary])] {
        let calendar = Calendar.current
        var order: [Date] = []
        var buckets: [Date: [ActionSessionSummary]] = [:]
        for session in filteredRuns {
            let day = session.ledgerDate.map { calendar.startOfDay(for: $0) } ?? Date.distantPast
            if buckets[day] == nil {
                order.append(day)
            }
            buckets[day, default: []].append(session)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    private func runDayLabel(_ day: Date) -> String {
        guard day != .distantPast else {
            return "Undated"
        }
        let calendar = Calendar.current
        if calendar.isDateInToday(day) {
            return "Today"
        }
        if calendar.isDateInYesterday(day) {
            return "Yesterday"
        }
        return Self.runDayFormatter.string(from: day)
    }

    private static let runDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return formatter
    }()

    private static let runClockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        return formatter
    }()

    private func runClockTime(_ session: ActionSessionSummary) -> String {
        guard let date = session.startedAt ?? session.finishedAt else {
            return "—"
        }
        return Self.runClockFormatter.string(from: date)
    }

    private func runPrimaryAction(_ session: ActionSessionSummary) -> RunPrimaryAction {
        if session.kind == .capture {
            return .review
        }
        if let shot = session.resultScreenshotURL ?? session.stageScreenshotURL,
           FileManager.default.fileExists(atPath: shot.path) {
            return .snapshot
        }
        return .reveal
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar

            HStack(spacing: 0) {
                sidebar

                Rectangle()
                    .fill(StageHUDTheme.cardBorder)
                    .frame(width: 1)
                    .overlay(
                        ActionSidebarEdgeHandle(
                            isCompact: $sidebarIconsOnly,
                            labelWidth: $sidebarLabelWidth,
                            previewWidth: $sidebarPreviewWidth
                        )
                    )

                mainPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            footerBar
        }
        .frame(minWidth: 1100, minHeight: 720)
        .background(StageHUDTheme.appBackground)
        // The title bar band already provides traffic-light clearance. Without
        // this the hidden title bar's safe area reserves a second empty strip of
        // the same height underneath it.
        .ignoresSafeArea(.container, edges: .top)
        // Suppress the macOS accent focus ring that otherwise outlines the first
        // focusable control — the collapse toggle — in blue on every appear.
        .focusEffectDisabled()
        .onChange(of: model.reviewSelectionRequestID) { _, _ in
            selectedSection = .scenarios
            if model.selectedScenario != nil {
                model.setFlowPhase(.review)
            }
        }
        .onChange(of: model.workspaceNavigationRequestID) { _, _ in
            selectedSection = .scenarios
        }
        .onChange(of: model.launcherDestinationRequestID) { _, _ in
            switch model.launcherDestination {
            case .home:
                selectedSection = .home
            case .scenarios:
                selectedSection = .scenarios
            case .runs:
                selectedSection = .runs
            case .library:
                selectedSection = .library
            case .settings:
                selectedSection = .settings
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .actionShowKeyboardCheatSheet)) { _ in
            showKeyboardCheatSheet = true
        }
        .sheet(isPresented: $showKeyboardCheatSheet) {
            ActionKeyboardCheatSheetView(
                onOpenDocs: openDocumentation,
                onClose: { showKeyboardCheatSheet = false }
            )
        }
        .background(
            Group {
                Button("") { selectedSection = .home }
                    .keyboardShortcut("1", modifiers: .command)
                    .opacity(0)
                    .frame(width: 0, height: 0)
                Button("") { selectedSection = .scenarios }
                    .keyboardShortcut("2", modifiers: .command)
                    .opacity(0)
                    .frame(width: 0, height: 0)
                Button("") { selectedSection = .runs }
                    .keyboardShortcut("3", modifiers: .command)
                    .opacity(0)
                    .frame(width: 0, height: 0)
                Button("") { selectedSection = .library }
                    .keyboardShortcut("4", modifiers: .command)
                    .opacity(0)
                    .frame(width: 0, height: 0)
                Button("") { selectedSection = .settings }
                    .keyboardShortcut("5", modifiers: .command)
                    .opacity(0)
                    .frame(width: 0, height: 0)
                Button("") { showKeyboardCheatSheet = true }
                    .keyboardShortcut("?", modifiers: [])
                    .opacity(0)
                    .frame(width: 0, height: 0)
                Button("") { showKeyboardCheatSheet = true }
                    .keyboardShortcut("/", modifiers: .command)
                    .opacity(0)
                    .frame(width: 0, height: 0)
            }
        )
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

    // MARK: - Title bar

    /// One connected band across the very top of the window.
    ///
    /// The wordmark and the collapse control live here rather than in the rail,
    /// which is the point of the arrangement: collapsing the sidebar then moves
    /// only the nav, while the identity and the control that acts on it stay
    /// put. Borrowed from Linea's top bar.
    private var titleBar: some View {
        HStack(spacing: 10) {
            ActionBrandLockup()

            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    sidebarIconsOnly.toggle()
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(StageHUDTheme.textMuted)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(sidebarIconsOnly ? "Expand sidebar" : "Collapse sidebar")

            Spacer(minLength: 0)
        }
        .padding(.leading, ActionWindowChrome.trafficLightInset)
        .padding(.trailing, 16)
        .frame(height: ActionWindowChrome.titleBarHeight)
        .frame(maxWidth: .infinity)
        .background(StageHUDTheme.railBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(StageHUDTheme.cardBorder)
                .frame(height: 1)
        }
        // The band is the window's drag handle now that the system title bar is
        // transparent and the rest of the surface is dense and clickable.
        .overlay(ActionWindowDragHandle())
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                ForEach([LauncherSection.home, .scenarios, .runs, .library], id: \.self) { section in
                    sidebarItem(section)
                }
            }
            .padding(.horizontal, sidebarShowsIconsOnly ? 8 : 10)
            .padding(.top, 12)

            Spacer(minLength: 0)

            if !sidebarShowsIconsOnly {
                MiraCompanionBadge()
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
            }

            sidebarItem(.settings)
                .padding(.horizontal, sidebarShowsIconsOnly ? 8 : 10)
                .padding(.bottom, 12)
        }
        .frame(width: sidebarWidth)
        .background(StageHUDTheme.railBackground)
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

                if !sidebarShowsIconsOnly {
                    Text(section.rawValue)
                        .font(.system(size: 13, weight: selected ? .semibold : .medium))
                    Spacer(minLength: 0)
                }
            }
            .foregroundStyle(selected ? StageHUDTheme.textPrimary : StageHUDTheme.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: sidebarShowsIconsOnly ? .center : .leading)
            .padding(.horizontal, sidebarShowsIconsOnly ? 0 : 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? StageHUDTheme.buttonSecondaryHover : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .help(sidebarShowsIconsOnly ? section.rawValue : "")
    }

    // MARK: - Main

    private var mainPane: some View {
        Group {
            if activeSection == .settings {
                settingsShell
            } else if activeSection == .runs {
                // Runs owns its own scroll so the control strip stays pinned
                // above a 260-row ledger instead of scrolling away with it.
                VStack(spacing: 0) {
                    pageHeader
                        .padding(.horizontal, 28)
                        .padding(.top, 20)
                        .padding(.bottom, 14)

                    runsSection
                }
            } else {
                VStack(spacing: 0) {
                    pageHeader
                        .padding(.horizontal, 28)
                        .padding(.top, 20)
                        .padding(.bottom, activeSection == .home ? 12 : 16)

                    if activeSection == .home {
                        // The rule is the masthead: it separates what this app is
                        // from what it is currently doing.
                        Rectangle()
                            .fill(StageHUDTheme.fieldRule)
                            .frame(height: 1)
                            .padding(.horizontal, 28)
                            .padding(.bottom, 16)
                    }

                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            switch activeSection {
                            case .home:
                                homeSection
                            case .scenarios:
                                ActionWorkspaceView(model: model, onOpenLibrary: {
                                    selectedSection = .library
                                })
                            case .runs:
                                EmptyView()
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
        .background(activeSection == .home ? StageHUDTheme.fieldCanvas : StageHUDTheme.appBackground)
    }

    private var pageHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: activeSection == .home ? 5 : 3) {
                if activeSection == .home {
                    // Home says what Action is before it says where you are: a
                    // computer-use surface for the Mac, of which recording is
                    // one capability rather than the premise.
                    Text("MACOS COMPUTER USE")
                        .font(ActionType.label)
                        .tracking(ActionType.eyebrowTracking)
                        .foregroundStyle(StageHUDTheme.fieldAccent)
                    Text(activeSection.rawValue)
                        .font(ActionType.pageTitle)
                        .foregroundStyle(StageHUDTheme.fieldInk)
                } else {
                    Text(activeSection.rawValue)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(StageHUDTheme.textPrimary)
                    Text(headerSubtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(StageHUDTheme.textSecondary)
                }
            }

            Spacer(minLength: 0)

            if activeSection == .library, !librarySessions.isEmpty {
                librarySearchField
                    .frame(maxWidth: 240)

                libraryLayoutPicker
            }

            if activeSection == .home || activeSection == .scenarios || activeSection == .library {
                launcherButton(
                    "New scenario",
                    tone: .primary,
                    action: {
                        model.startCalculatorScenario()
                        selectedSection = .scenarios
                    }
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
        case .home:
            return activeSection.subtitle
        case .scenarios:
            if let scenario = model.selectedScenario {
                return scenario.title
            }
            let n = model.scenarios.count
            return n == 0 ? "No scenarios yet" : "\(n) scenario\(n == 1 ? "" : "s")"
        case .runs:
            return runsHeaderSubtitle
        case .library:
            let total = librarySessions.count
            if total == 0 {
                return "No captured takes yet"
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

    // MARK: - Home

    private var homeSection: some View {
        ActionHomeView(
            model: model,
            onOpenRuns: { selectedSection = .runs },
            onOpenSession: { session in openSession(session) },
            onNewScenario: {
                model.startCalculatorScenario()
                selectedSection = .scenarios
            }
        )
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

            Button {
                showKeyboardCheatSheet = true
            } label: {
                Label("Keyboard", systemImage: "keyboard")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(StageHUDTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Keyboard shortcuts (⌘/)")

            Button {
                openDocumentation()
            } label: {
                Label("Docs", systemImage: "book")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(StageHUDTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .help(ActionDocs.siteHostLabel)
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

    private func openDocumentation() {
        NSWorkspace.shared.open(ActionDocs.siteURL)
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
                        .font(.system(size: 22, weight: .semibold, design: session.isCalculatorTake ? .monospaced : .default))
                        .foregroundStyle(StageHUDTheme.textPrimary)
                    if session.isCalculatorTake {
                        Text("= \(session.actualResult)")
                            .font(.system(size: 18, weight: .medium, design: .monospaced))
                            .foregroundStyle(StageHUDTheme.textSecondary)
                    } else if !session.subtitle.isEmpty {
                        Text(session.subtitle)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(StageHUDTheme.textSecondary)
                            .lineLimit(1)
                    }
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

    // MARK: - Runs

    /// The chips carry the per-kind counts, so the header answers a different
    /// question: what is this list, and how much of it am I looking at.
    private var runsHeaderSubtitle: String {
        let total = model.recentSessions.count
        if total == 0 {
            return "Nothing has run yet"
        }
        if runsFiltersActive {
            let shown = filteredRuns.count
            return "\(shown) of \(total) run\(total == 1 ? "" : "s")"
        }
        return "Every drive, inspection, and capture on this Mac"
    }

    private var runsSearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(runsSearchFocused ? StageHUDTheme.reviewAccent : StageHUDTheme.textMuted)
            TextField(runsSearchFieldPlaceholder, text: $runsSearch)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($runsSearchFocused)
            if !runsSearch.isEmpty {
                Button {
                    runsSearch = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(StageHUDTheme.textMuted)
                }
                .buttonStyle(.plain)
                .help("Clear the search")
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(StageHUDTheme.railBackground)
        )
        // The focus ring is drawn inside the field's own footprint so taking
        // focus cannot nudge the strip's layout by a hairline.
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(
                    runsSearchFocused ? StageHUDTheme.reviewAccent : StageHUDTheme.cardBorder,
                    lineWidth: 1
                )
        )
        .animation(.easeOut(duration: 0.12), value: runsSearchFocused)
        // Esc empties the field before it gives up focus, so the ledger comes
        // back without a reach for the mouse.
        .onExitCommand {
            if runsSearch.isEmpty {
                runsSearchFocused = false
            } else {
                runsSearch = ""
            }
        }
    }

    private var runsSection: some View {
        VStack(spacing: 0) {
            if !model.recentSessions.isEmpty {
                runsControlStrip
                    .padding(.horizontal, 28)
                    .padding(.bottom, 12)
            }

            if model.recentSessions.isEmpty {
                runsEmptyState
                    .padding(.horizontal, 28)
                Spacer(minLength: 0)
            } else if filteredRuns.isEmpty {
                runsNoMatchState
                    .padding(.horizontal, 28)
                Spacer(minLength: 0)
            } else {
                runsLedger
            }
        }
    }

    // MARK: Runs · control strip

    /// Chips, outcome picker, and search live in one enclosure so the whole
    /// filter model reads as a single control rather than three stray widgets.
    /// Geometry is shared on purpose: every control in the strip is one 24pt
    /// row at radius 6, inset a uniform 7 from a radius-13 enclosure. 6 + 7 = 13
    /// keeps the inner and outer curves concentric, which is what stops four
    /// buttons in a box from reading as four buttons in a box.
    private static let runStripInset: CGFloat = 7
    private static let runStripControlRadius: CGFloat = 6
    private static let runStripControlHeight: CGFloat = 24
    private static var runStripRadius: CGFloat { runStripControlRadius + runStripInset }

    private var runsControlStrip: some View {
        HStack(spacing: 8) {
            // Fixed so the search field's layout priority cannot squeeze the
            // chips: without it the first chip absorbs the whole compression
            // and renders as "All 2…".
            HStack(spacing: 3) {
                ForEach(RunKindFilter.allCases) { filter in
                    runFilterChip(filter)
                }
            }
            .fixedSize(horizontal: true, vertical: false)

            Rectangle()
                .fill(StageHUDTheme.cardBorder)
                .frame(width: 1, height: 18)
                .padding(.horizontal, 3)

            runOutcomeMenu

            Spacer(minLength: 12)

            if runsFiltersActive {
                runsClearButton
                    .transition(.opacity)
            }

            // Flexible rather than pinned at 210: the launcher window resizes,
            // and a fixed field is the first thing to push the strip off its
            // own edge. It takes what it needs, the spacer keeps the rest.
            runsSearchField
                .frame(minWidth: 150, maxWidth: 240)
                .layoutPriority(1)
        }
        .padding(Self.runStripInset)
        .background(
            RoundedRectangle(cornerRadius: Self.runStripRadius, style: .continuous)
                .fill(StageHUDTheme.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Self.runStripRadius, style: .continuous)
                .stroke(StageHUDTheme.cardBorder, lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.14), value: runsFiltersActive)
    }

    private var runsClearButton: some View {
        Button(action: clearRunsFilters) {
            Text("Clear")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(hoveredRunsClear ? StageHUDTheme.textPrimary : StageHUDTheme.textSecondary)
                .padding(.horizontal, 9)
                .frame(height: Self.runStripControlHeight)
                .background(
                    RoundedRectangle(cornerRadius: Self.runStripControlRadius, style: .continuous)
                        .fill(hoveredRunsClear ? StageHUDTheme.railBackground : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: Self.runStripControlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hoveredRunsClear = $0 }
        .help("Clear the kind, outcome, and search filters")
    }

    private func runFilterChip(_ filter: RunKindFilter) -> some View {
        let selected = runKindFilter == filter
        let count = runsKindCount(filter)
        // A chip that would land on nothing is not worth a click. Never dim the
        // chip you are standing on, though: in the no-match state that would
        // read as the app breaking rather than the filter being too narrow.
        let inert = count == 0 && filter != .all && !selected
        let hovered = hoveredRunKindFilter == filter && !inert && !selected
        return Button {
            runKindFilter = filter
        } label: {
            ZStack {
                // Reserve the selected weight's metrics. Without this the label
                // gains a few points when it becomes semibold and every chip to
                // its right slides — a shift you feel on each click.
                runFilterChipLabel(filter, count: count, selected: true, inert: false)
                    .hidden()
                runFilterChipLabel(filter, count: count, selected: selected, inert: inert)
            }
            .padding(.horizontal, 9)
            .frame(height: Self.runStripControlHeight)
            .background(
                RoundedRectangle(cornerRadius: Self.runStripControlRadius, style: .continuous)
                    .fill(runFilterChipFill(selected: selected, hovered: hovered))
            )
            // The selected chip is pressed into the strip rather than tinted.
            // That leaves the one accent in this surface to the search focus
            // ring and the outcome dot, where colour is carrying real meaning.
            .overlay(
                RoundedRectangle(cornerRadius: Self.runStripControlRadius, style: .continuous)
                    .stroke(selected ? StageHUDTheme.cardBorder : Color.clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Self.runStripControlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(inert)
        .onHover { hovering in
            if hovering {
                hoveredRunKindFilter = filter
            } else if hoveredRunKindFilter == filter {
                hoveredRunKindFilter = nil
            }
        }
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityLabel("\(filter.rawValue), \(count) run\(count == 1 ? "" : "s")")
        .help(
            count == 0
                ? "No \(filter.rawValue.lowercased()) runs in the current search"
                : "Show \(count) \(filter.rawValue.lowercased()) run\(count == 1 ? "" : "s")"
        )
    }

    private func runFilterChipFill(selected: Bool, hovered: Bool) -> Color {
        if selected {
            return StageHUDTheme.railBackground
        }
        return hovered ? StageHUDTheme.railBackground.opacity(0.6) : .clear
    }

    private func runFilterChipLabel(
        _ filter: RunKindFilter,
        count: Int,
        selected: Bool,
        inert: Bool
    ) -> some View {
        // Inert chips step down in colour, never in opacity: 40% on 11pt text
        // drops below the contrast floor, and a count of 0 already says it.
        let labelColor = inert
            ? StageHUDTheme.textMuted
            : (selected ? StageHUDTheme.textPrimary : StageHUDTheme.textSecondary)
        return HStack(spacing: 5) {
            if let icon = filter.icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(selected ? StageHUDTheme.textPrimary : StageHUDTheme.textMuted)
                    .frame(width: 13)
            }
            Text(filter.rawValue)
                .font(.system(size: 11, weight: selected ? .semibold : .medium))
                .foregroundStyle(labelColor)
            // Always present, even at 0, and given a two-digit slot: the count
            // is the chip's live reading, and a reading that disappears or
            // reflows while you type is worse than one that holds still.
            Text("\(count)")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(StageHUDTheme.textMuted)
                // `minWidth` reserves the two-digit slot but is also a floor the
                // layout will happily compress down to, which truncated the
                // three-digit All count to "2…". Fixed so the reading can only
                // grow past the slot, never shrink into it.
                .fixedSize()
                .frame(minWidth: 15, alignment: .trailing)
        }
    }

    private var runOutcomeMenu: some View {
        Menu {
            ForEach(RunOutcomeFilter.allCases) { option in
                Button {
                    runOutcomeFilter = option
                } label: {
                    // Counted against the kind chip and the search, like the
                    // chips are, so every number in the strip answers the same
                    // question: how many rows would this leave me.
                    let count = runsMatching(
                        kind: runKindFilter,
                        outcome: option,
                        query: runsSearch
                    ).count
                    if runOutcomeFilter == option {
                        Text("✓  \(option.rawValue) (\(count))")
                    } else {
                        Text("\(option.rawValue) (\(count))")
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                if let outcome = runOutcomeFilter.outcome {
                    runOutcomeDot(outcome)
                }
                Text(runOutcomeFilter.rawValue)
                    .font(.system(size: 11, weight: runOutcomeFilter == .any ? .medium : .semibold))
                    .foregroundStyle(
                        runOutcomeFilter == .any ? StageHUDTheme.textSecondary : StageHUDTheme.textPrimary
                    )
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(StageHUDTheme.textMuted)
            }
            .padding(.horizontal, 9)
            .frame(height: Self.runStripControlHeight)
            .background(
                RoundedRectangle(cornerRadius: Self.runStripControlRadius, style: .continuous)
                    .fill(runOutcomeFilter == .any ? Color.clear : StageHUDTheme.railBackground)
            )
            // Same pressed-in treatment as a selected chip, because it is the
            // same idea: a narrowing that is currently applied.
            .overlay(
                RoundedRectangle(cornerRadius: Self.runStripControlRadius, style: .continuous)
                    .stroke(runOutcomeFilter == .any ? Color.clear : StageHUDTheme.cardBorder, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Self.runStripControlRadius, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Filter runs by outcome")
    }

    private var runsSearchFieldPlaceholder: String {
        runKindFilter == .all ? "Search runs" : "Search \(runKindFilter.rawValue.lowercased()) runs"
    }

    // MARK: Runs · ledger

    private var runsLedger: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(runDayGroups, id: \.key) { group in
                    Section {
                        VStack(spacing: 0) {
                            ForEach(Array(group.runs.enumerated()), id: \.element.id) { index, session in
                                runRow(session, alternate: !index.isMultiple(of: 2))
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(StageHUDTheme.cardBorder, lineWidth: 1)
                        )
                        .padding(.bottom, 14)
                    } header: {
                        runDayHeader(day: group.key, count: group.runs.count)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.automatic)
    }

    private func runDayHeader(day: Date, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(runDayLabel(day).uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(StageHUDTheme.textSecondary)
            Text("\(count)")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(StageHUDTheme.textMuted)
            Rectangle()
                .fill(StageHUDTheme.cardBorder)
                .frame(height: 1)
        }
        .padding(.top, 6)
        .padding(.bottom, 7)
        .background(StageHUDTheme.appBackground)
    }

    private func runRow(_ session: ActionSessionSummary, alternate: Bool) -> some View {
        let selected = model.selectedSession?.id == session.id
        let hovered = hoveredRunID == session.id
        let action = runPrimaryAction(session)
        // Three clusters, deliberately unequal gaps: what it is and who ran it
        // (tight), how it ended (medium), when and where it opens (tight,
        // pinned right). The widest joint is the elastic one after the agent,
        // so the eye reads titles down the page and only then crosses to the
        // rail.
        return Group {
            HStack(spacing: 0) {
                // Flush to the table edge, full row height. The group's corner
                // radius rounds it on the first and last row, which is the
                // container's own curve rather than a clipped wedge.
                Rectangle()
                    .fill(selected ? StageHUDTheme.reviewAccent : Color.clear)
                    .frame(width: 3)

                HStack(spacing: 20) {
                    HStack(spacing: 8) {
                        Image(systemName: session.kind.icon)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(
                                selected ? StageHUDTheme.reviewAccent : StageHUDTheme.textMuted
                            )
                            .frame(width: 15)
                            .help(session.kind.title)

                        Text(session.displayTitle)
                            .font(.system(size: 12.5, weight: selected ? .semibold : .medium))
                            .foregroundStyle(StageHUDTheme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .layoutPriority(1)

                        // Who drove it, next to what it did. Apart, the two read
                        // as unrelated columns; together they say whether a run
                        // has real provenance or is an unidentified stray.
                        if !session.agent.isEmpty {
                            Text(session.agent)
                                .font(.system(size: 10.5))
                                .foregroundStyle(StageHUDTheme.textMuted)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: 190, alignment: .leading)
                        }

                        Spacer(minLength: 8)
                    }

                    runOutcomeBadge(session.outcome)
                        // Sized for "Unfinished", the longest outcome label.
                        .frame(width: 74, alignment: .leading)

                    HStack(spacing: 10) {
                        Text(runClockTime(session))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(StageHUDTheme.textMuted)
                            .frame(width: 56, alignment: .trailing)

                        // The only single-click that opens anything. The row
                        // itself just selects.
                        Button {
                            openRun(session)
                        } label: {
                            runDestinationCell(
                                action,
                                rowHovered: hovered,
                                targetHovered: hoveredDestinationID == session.id,
                                selected: selected
                            )
                        }
                        .buttonStyle(.plain)
                        .onHover { inside in
                            if inside {
                                hoveredDestinationID = session.id
                            } else if hoveredDestinationID == session.id {
                                hoveredDestinationID = nil
                            }
                        }
                        .help(action.label)
                        .accessibilityLabel(action.label)
                    }
                }
                .padding(.leading, 9)
                .padding(.trailing, 10)
            }
            .frame(height: 30)
            .background(runRowFill(selected: selected, hovered: hovered, alternate: alternate))
            .contentShape(Rectangle())
        }
        .onHover { inside in
            if inside {
                hoveredRunID = session.id
            } else if hoveredRunID == session.id {
                hoveredRunID = nil
            }
        }
        // Selecting is not opening. Double-click is the macOS way to open, and
        // the destination button on the right is the discoverable one.
        .onTapGesture(count: 2) { openRun(session) }
        .onTapGesture { model.selectSession(session) }
        .help(session.displayTitle)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(session.kind.title) run, \(session.displayTitle), \(session.outcome.title), \(runClockTime(session))"
        )
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityAction(named: Text(action.label)) { openRun(session) }
        .contextMenu {
            Button(action.label) { openRun(session) }
            Divider()
            Button("Show in Finder") { model.revealSession(session) }
            Button("Open Trace") { model.openSessionTrace(session) }
            Button("Copy run ID") { copyRunIdentifier(session) }
        }
    }

    /// Where this row's click lands, stated at rest. It is not decoration: it is
    /// the column that answers "which of these runs left something I can look
    /// at", and reading down it is how you find the drives that actually got a
    /// snapshot. Hover only promotes it from a column value to a target.
    private func runDestinationCell(
        _ action: RunPrimaryAction,
        rowHovered: Bool = false,
        targetHovered: Bool = false,
        selected: Bool = false
    ) -> some View {
        // Three steps, so the escalation tracks the pointer: at rest it is a
        // column value; approaching the row lifts it out of the muted rail;
        // landing on the cell itself makes it a target. Only the last step is
        // the thing you can click.
        let armed = targetHovered || selected
        let tint: Color = armed
            ? StageHUDTheme.reviewAccent
            : (rowHovered ? StageHUDTheme.textSecondary : StageHUDTheme.textMuted)
        return HStack(spacing: 5) {
            Image(systemName: action.icon)
                .font(.system(size: 10, weight: .medium))
            Text(action.shortLabel)
                .font(.system(size: 10, weight: armed ? .semibold : .regular))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        // Padding is unconditional so the chip appearing on hover cannot shift
        // the row; only the fill changes.
        .padding(.horizontal, 6)
        .frame(height: 19)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(targetHovered ? StageHUDTheme.runActionChip : Color.clear)
        )
        // Sized for the longest label at its heaviest weight, so promoting a row
        // to live never clips "Snapshot" and never re-flows the column.
        .frame(width: 90, alignment: .trailing)
        .animation(.easeOut(duration: 0.1), value: armed)
    }

    private func runRowFill(selected: Bool, hovered: Bool, alternate: Bool) -> Color {
        if selected {
            // Selected still has to answer the pointer, or hovering the row you
            // last opened reads as a dead cell.
            return hovered ? StageHUDTheme.runSelectionHover : StageHUDTheme.runSelection
        }
        if hovered {
            return StageHUDTheme.buttonSecondaryHover
        }
        return alternate ? StageHUDTheme.rowAlternate : StageHUDTheme.cardFill
    }

    /// The dot carries the colour on every row; only a failure earns tinted,
    /// heavier text. Tinting every non-`ok` outcome put 100+ amber labels in
    /// front of the 14 red ones that actually need an operator.
    private func runOutcomeBadge(_ outcome: ActionRunOutcome) -> some View {
        HStack(spacing: 5) {
            runOutcomeDot(outcome)
            Text(outcome.title)
                .font(.system(size: 10.5, weight: outcome == .failed ? .semibold : .regular))
                .foregroundStyle(outcome == .failed ? outcome.tint : StageHUDTheme.textMuted)
                .lineLimit(1)
        }
    }

    /// Filled when the run reached a state something actually recorded; an open
    /// ring when it never did. The distinction is carried by form so
    /// `unfinished` does not have to spend a colour the ledger already spent.
    private func runOutcomeDot(_ outcome: ActionRunOutcome) -> some View {
        Group {
            if outcome.isSettled {
                Circle().fill(outcome.tint)
            } else {
                Circle().strokeBorder(outcome.tint, lineWidth: 1.25)
            }
        }
        .frame(width: 6, height: 6)
    }

    // MARK: Runs · states

    /// The three run kinds, each paired with the destination its rows usually
    /// open. An empty ledger is the only moment there is room to say what the
    /// glyphs mean and where a click goes, so it says both.
    private static let runsLegend: [(kind: ActionRunKind, blurb: String, destination: RunPrimaryAction)] = [
        (
            .drive,
            "An agent took the pointer and acted on a real window.",
            .reveal
        ),
        (
            .inspection,
            "A surface was read: screenshot, accessibility tree, on-screen text.",
            .snapshot
        ),
        (
            .capture,
            "A recorded take, ready to play back and annotate.",
            .review
        )
    ]

    private var runsEmptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(StageHUDTheme.textMuted)
                    .padding(.bottom, 2)
                Text("No runs yet")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(StageHUDTheme.textPrimary)
                Text("Every drive, inspection, and capture lands here the moment it starts — including the ones an agent kicks off while you are elsewhere. A row opens whatever that run left behind.")
                    .font(.system(size: 13))
                    .foregroundStyle(StageHUDTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 460, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(Self.runsLegend.enumerated()), id: \.element.kind) { index, entry in
                    if index > 0 {
                        Rectangle()
                            .fill(StageHUDTheme.cardBorder)
                            .frame(height: 1)
                    }
                    runsLegendRow(entry)
                }
            }
            .frame(maxWidth: 560, alignment: .leading)

            launcherButton(
                model.isRunningGuidedDemo ? "Recording…" : "Run a capture",
                tone: .primary,
                action: model.runGuidedCalculatorDemo
            )
            .disabled(model.isRunningGuidedDemo)
            .padding(.top, 2)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func runsLegendRow(
        _ entry: (kind: ActionRunKind, blurb: String, destination: RunPrimaryAction)
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.kind.icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(StageHUDTheme.textMuted)
                .frame(width: 15)

            Text(entry.kind.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(StageHUDTheme.textPrimary)
                .frame(width: 58, alignment: .leading)

            Text(entry.blurb)
                .font(.system(size: 12))
                .foregroundStyle(StageHUDTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 12)

            // The same cell the ledger row ends with, at rest. Recognising it
            // later is the whole point of showing it here.
            runDestinationCell(entry.destination)
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.kind.title). \(entry.blurb) Opens \(entry.destination.shortLabel).")
    }

    private var runsNoMatchState: some View {
        let releases = runsFilterReleases
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(StageHUDTheme.textMuted)
                    .padding(.bottom, 2)
                Text("No runs match")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(StageHUDTheme.textPrimary)
                Text(runsNoMatchDetail)
                    .font(.system(size: 13))
                    .foregroundStyle(StageHUDTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 480, alignment: .leading)
            }

            // Which of the three narrowings is to blame, priced. Without this
            // the operator can only see that nothing matched and has to guess
            // which filter to undo.
            if !releases.isEmpty {
                HStack(spacing: 8) {
                    ForEach(releases) { release in
                        Button {
                            release.apply()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(StageHUDTheme.textMuted)
                                Text(release.name)
                                Text("\(release.restores)")
                                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(StageHUDTheme.reviewAccent)
                            }
                        }
                        .buttonStyle(ActionSettingsPillButtonStyle())
                        .help("Drop \(release.name) to see \(release.restores) run\(release.restores == 1 ? "" : "s")")
                    }
                }
                .padding(.top, 2)
            }

            // When a targeted release is on offer, the blunt reset drops to a
            // quiet text button so the two are not equal-weight twins.
            if releases.isEmpty {
                Button("Clear filters") { clearRunsFilters() }
                    .buttonStyle(ActionSettingsPillButtonStyle(primary: true))
            } else {
                Button {
                    clearRunsFilters()
                } label: {
                    Text("Clear all filters")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(
                            hoveredRunsReset ? StageHUDTheme.textPrimary : StageHUDTheme.textMuted
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hoveredRunsReset = $0 }
                .padding(.top, 2)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var runsNoMatchDetail: String {
        // Verb-first clauses so the sentence reads as one condition the runs
        // failed, rather than three labels bolted onto a noun.
        var clauses: [String] = []
        if !runsSearchQuery.isEmpty {
            clauses.append("match “\(runsSearchQuery)”")
        }
        if runKindFilter != .all {
            clauses.append("are \(runKindFilter.rawValue) runs")
        }
        if runOutcomeFilter != .any {
            clauses.append("ended \(runOutcomeFilter.rawValue)")
        }
        let total = model.recentSessions.count
        guard !clauses.isEmpty else {
            return "None of the \(total) runs matched."
        }
        let head = "None of the \(total) runs \(Self.joinClauses(clauses))."
        return runsFilterReleases.isEmpty
            ? "\(head) Each of those narrowings is empty on its own too."
            : "\(head) Drop one to get back to something:"
    }

    private static func joinClauses(_ clauses: [String]) -> String {
        switch clauses.count {
        case 0: return ""
        case 1: return clauses[0]
        case 2: return "\(clauses[0]) and \(clauses[1])"
        default: return "\(clauses.dropLast().joined(separator: ", ")), and \(clauses[clauses.count - 1])"
        }
    }

    private func copyRunIdentifier(_ session: ActionSessionSummary) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(session.sessionId, forType: .string)
    }

    private func openRun(_ session: ActionSessionSummary) {
        model.selectSession(session)
        if session.kind == .capture {
            openSession(session)
            return
        }
        if let shot = session.resultScreenshotURL ?? session.stageScreenshotURL,
           FileManager.default.fileExists(atPath: shot.path) {
            NSWorkspace.shared.open(shot)
            return
        }
        model.revealSession(session)
    }

    // MARK: - Library

    private var librarySection: some View {
        Group {
            if librarySessions.isEmpty {
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
                        .font(.system(size: 13, weight: .semibold, design: session.isCalculatorTake ? .monospaced : .default))
                        .foregroundStyle(StageHUDTheme.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(session.isCalculatorTake ? "= \(session.actualResult)" : session.subtitle)
                            .font(.system(size: 12, design: session.isCalculatorTake ? .monospaced : .default))
                            .foregroundStyle(StageHUDTheme.textSecondary)
                            .lineLimit(1)
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
                        .font(.system(size: 14, weight: .semibold, design: session.isCalculatorTake ? .monospaced : .default))
                        .foregroundStyle(StageHUDTheme.textPrimary)
                        .lineLimit(1)

                    Text(session.isCalculatorTake ? "Result \(session.actualResult)" : session.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(StageHUDTheme.textSecondary)
                        .lineLimit(1)

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
        selectedSection = .scenarios
        if let scenario = model.scenarios.first(where: {
            $0.latestSessionId == session.sessionId
                || $0.sessionIds.contains(session.sessionId)
                || $0.latestSessionId == session.id
                || $0.sessionIds.contains(session.id)
        }) {
            model.selectScenario(scenario)
            model.setFlowPhase(.review)
        }
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

            ActionSettingsSection(title: "Help") {
                ActionSettingsRow(
                    icon: "book",
                    iconColor: StageHUDTheme.reviewAccent,
                    title: "Documentation",
                    subtitle: ActionDocs.siteHostLabel,
                    onTap: openDocumentation
                )

                ActionSettingsDivider()

                ActionSettingsRow(
                    icon: "keyboard",
                    title: "Keyboard shortcuts",
                    subtitle: "App navigation, library, and Takes review.",
                    onTap: { showKeyboardCheatSheet = true }
                )
            }
        }
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
        case .home:
            return "house"
        case .scenarios:
            return "list.bullet.rectangle"
        case .runs:
            return "clock.arrow.circlepath"
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
