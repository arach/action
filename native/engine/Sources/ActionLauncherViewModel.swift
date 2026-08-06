import AppKit
import ActionCore
import AVFoundation
import Foundation
import OSLog

@MainActor
final class ActionAppearanceStore: ObservableObject {
    static let shared = ActionAppearanceStore()

    @Published var mode: ActionAppearanceMode {
        didSet {
            mode.persist()
            NSApplication.shared.appearance = mode.appearance
            for window in NSApplication.shared.windows {
                window.appearance = mode.appearance
            }
        }
    }

    private init() {
        self.mode = .load()
    }
}

struct ActionSessionSummary: Identifiable {
    let id: String
    let sessionId: String
    let artifactDirectoryURL: URL
    let videoURL: URL
    let traceURL: URL
    let feedbackURL: URL
    let stageScreenshotURL: URL?
    let resultScreenshotURL: URL?
    let expression: String
    let expectedResult: String
    let actualResult: String
    let startedAt: Date?
    let finishedAt: Date?
    let feedbackCount: Int
    /// Best-effort media duration in seconds (video first, wall-clock fallback).
    let durationSeconds: Double?

    var agentFeedbackMarkdownURL: URL {
        artifactDirectoryURL.appendingPathComponent("agent-feedback.md")
    }

    var agentFeedbackJSONURL: URL {
        artifactDirectoryURL.appendingPathComponent("agent-feedback.json")
    }

    var displayTitle: String {
        let compact = expression.replacingOccurrences(of: " ", with: "")
        return compact.isEmpty ? sessionId : compact
    }

    var formattedDuration: String? {
        guard let durationSeconds, durationSeconds.isFinite, durationSeconds > 0 else {
            return nil
        }
        if durationSeconds < 60 {
            return String(format: "%.0fs", durationSeconds.rounded())
        }
        let total = Int(durationSeconds.rounded())
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct ActionSessionTrace: Decodable {
    let sessionId: String
    let startedAt: String
    let finishedAt: String
    let expression: String
    let expectedResult: String
    let actualResult: String
    let videoPath: String
    let screenshots: [String]
}

private struct GuidedCaptureLauncherResult: Decodable {
    let sessionId: String
    let artifactDirectory: String
    let videoPath: String
    let tracePath: String
    let expectedResult: String
    let actualResult: String
    let expression: String
}

@MainActor
final class ActionLauncherViewModel: ObservableObject {
    private let logger = Logger(subsystem: "dev.action.Action", category: "Launcher")
    private let demoSiteURL = URL(string: "https://example.com")!
    private let localConsoleURL = URL(string: "http://127.0.0.1:4318/")!
    private let agentProcess = ActionAgentProcessController()
    private let agentClient = ActionAgentClient()
    private var browserWindowController: ActionBrowserWindowController?
    private var localConsoleProcess: Process?
    private var consoleReachabilityTask: Task<Void, Never>?
    private var consoleWatchdogTask: Task<Void, Never>?

    @Published var agentStatus: String = "Offline"
    @Published var accessibilityStatus: String = "Unknown"
    @Published var screenRecordingStatus: String = "Unknown"
    @Published var notes: [String] = []
    @Published var consoleURL: URL
    @Published var consoleStatus: String = "Ready"
    @Published var consoleDetail: String = "Optional local HUD for diagnostics."
    @Published var consoleIsReachable: Bool = false
    @Published var consoleIsManagedByAction: Bool = false
    @Published var consoleAutoEnsureEnabled: Bool = true
    @Published var guidedDemoStatus: String = "Ready"
    @Published var recentSessions: [ActionSessionSummary] = []
    @Published var isRunningGuidedDemo: Bool = false
    @Published var selectedSessionID: String?
    @Published var focusedFeedbackItemID: String?
    @Published var appearanceMode: ActionAppearanceMode
    @Published private(set) var reviewSelectionRequestID = UUID()

    /// Scenarios under Start → Edit → Review (the flow is inherent, not a named “loop”).
    @Published var scenarios: [ActionScenarioDocument] = []
    @Published var selectedScenarioID: String?
    @Published var selectedScenarioStepID: String?
    @Published var scenarioDraftGoal: String = "Show a short Calculator demo with keyboard and click input"
    @Published var scenarioStepFeedbackDraft: String = ""
    @Published private(set) var workspaceNavigationRequestID = UUID()

    var selectedScenario: ActionScenarioDocument? {
        if let selectedScenarioID,
           let scenario = scenarios.first(where: { $0.id == selectedScenarioID }) {
            return scenario
        }
        return scenarios.first
    }

    var selectedScenarioStep: ActionScenarioStep? {
        guard let scenario = selectedScenario else { return nil }
        if let selectedScenarioStepID,
           let step = scenario.steps.first(where: { $0.id == selectedScenarioStepID }) {
            return step
        }
        return scenario.steps.first
    }

    init() {
        self.consoleURL = localConsoleURL
        self.appearanceMode = ActionAppearanceStore.shared.mode
        refreshSessions()
        refreshScenarios()
        refreshConsoleState()
        startConsoleWatchdog()
    }

    func refreshPermissions() {
        Task {
            await refreshPermissionsViaAgent()
        }
    }

    func requestPermissions() {
        Task {
            await requestPermissionsViaAgent()
        }
    }

    func openAccessibilitySettings() {
        Task {
            await openSettingsViaAgent(.openAccessibilitySettings)
        }
    }

    func openScreenRecordingSettings() {
        Task {
            await openSettingsViaAgent(.openScreenRecordingSettings)
        }
    }

    func openWebConsoleInBrowser() {
        NSWorkspace.shared.open(consoleURL)
    }

    func openEmbeddedConsole() {
        consoleURL = localConsoleURL
        openBrowserWindow()
    }

    func startLocalConsole() {
        consoleAutoEnsureEnabled = true

        if consoleIsReachable && localConsoleProcess == nil {
            consoleStatus = "Ready"
            consoleDetail = localConsoleURL.absoluteString
            return
        }

        if let localConsoleProcess, localConsoleProcess.isRunning {
            consoleStatus = "Ready"
            consoleDetail = localConsoleURL.absoluteString
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["bun", "run", "hud"]
        process.currentDirectoryURL = repositoryRootURL()
        let logURL = consoleLogURL()
        FileManager.default.createFile(atPath: logURL.path, contents: Data())
        let logHandle = try? FileHandle(forWritingTo: logURL)
        process.standardOutput = logHandle
        process.standardError = logHandle
        process.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                guard let self else { return }
                self.localConsoleProcess = nil
                self.consoleIsManagedByAction = false
                self.consoleStatus = "Off"
                self.consoleDetail = "HUD stopped."
                self.refreshConsoleState()
            }
        }

        do {
            try process.run()
            localConsoleProcess = process
            consoleIsManagedByAction = true
            consoleStatus = "Starting…"
            consoleDetail = "Opening the local HUD."
            logger.notice("Started local console process (pid=\(process.processIdentifier, privacy: .public))")
            scheduleConsoleProbeBurst()
        } catch {
            consoleStatus = "Failed"
            consoleDetail = error.localizedDescription
            logger.error("Failed to start local console: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stopLocalConsole() {
        consoleAutoEnsureEnabled = false

        guard let localConsoleProcess, localConsoleProcess.isRunning else {
            if consoleIsReachable {
                consoleStatus = "Ready"
                consoleDetail = "HUD is running outside Action. Auto-start is off."
            } else {
                consoleStatus = "Off"
                consoleDetail = "HUD is stopped."
            }
            return
        }

        localConsoleProcess.terminate()
        self.localConsoleProcess = nil
        consoleIsManagedByAction = false
        consoleStatus = "Stopping…"
        consoleDetail = "HUD is shutting down."
        scheduleConsoleProbeBurst()
    }

    func restartLocalConsole() {
        consoleAutoEnsureEnabled = true
        if let localConsoleProcess, localConsoleProcess.isRunning {
            localConsoleProcess.terminate()
            self.localConsoleProcess = nil
        }
        consoleIsManagedByAction = false
        consoleStatus = "Restarting…"
        consoleDetail = "Restarting the local HUD."
        startLocalConsole()
    }

    func refreshConsoleState() {
        consoleReachabilityTask?.cancel()
        consoleReachabilityTask = Task { @MainActor in
            await self.updateConsoleReachability()
        }
    }

    func copyLocalConsoleCommand() {
        let command = "cd \(repositoryRootURL().path.quotedForShell()) && bun run hud"
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(command, forType: .string)
        consoleStatus = "Ready"
        consoleDetail = "Copied launch command."
    }

    func openConsoleLog() {
        let logURL = consoleLogURL()
        guard FileManager.default.fileExists(atPath: logURL.path) else {
            consoleStatus = "Off"
            consoleDetail = "No HUD log yet."
            return
        }
        NSWorkspace.shared.open(logURL)
    }

    func showDemoSite() {
        consoleURL = demoSiteURL
        openBrowserWindow()
    }

    func showLocalConsole() {
        consoleURL = localConsoleURL
        openBrowserWindow()
    }

    func reloadConsole() {
        browserController().reload()
        refreshConsoleState()
    }

    func setConsoleStatus(_ status: String) {
        consoleStatus = status
    }

    func handleWebViewCommand(_ command: ActionWebViewCommand) {
        switch command {
        case .startLocalConsole:
            startLocalConsole()
        case .copyText(let value):
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(value, forType: .string)
            consoleStatus = "Copied to clipboard"
            consoleDetail = value
        }
    }

    func openBrowserWindow() {
        logger.notice("openBrowserWindow called with URL: \(self.consoleURL.absoluteString, privacy: .public)")
        browserController().show(url: self.consoleURL)
        refreshConsoleState()
    }

    func showWebInspector() {
        browserController().showInspector()
    }

    func openScenariosFolder() {
        let scenariosURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("scenarios", isDirectory: true)
        NSWorkspace.shared.open(scenariosURL)
    }

    func runGuidedCalculatorDemo() {
        runGuidedCalculatorDemo(forScenarioID: nil)
    }

    /// Draft a Calculator scenario and open Edit.
    func startCalculatorScenario(goal: String? = nil) {
        let scenario = ActionScenarioPresets.makeCalculatorScenario(goal: goal ?? scenarioDraftGoal)
        do {
            try ActionScenarioStore.shared.save(scenario)
            refreshScenarios()
            selectedScenarioID = scenario.id
            selectedScenarioStepID = scenario.steps.first?.id
            setFlowPhase(.edit)
            workspaceNavigationRequestID = UUID()
            guidedDemoStatus = "Scenario drafted — review steps, then run"
        } catch {
            guidedDemoStatus = "Failed to create scenario: \(error.localizedDescription)"
            logger.error("Create scenario failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func selectScenario(_ scenario: ActionScenarioDocument) {
        selectedScenarioID = scenario.id
        selectedScenarioStepID = scenario.steps.first?.id
        if let latest = scenario.latestSessionId {
            selectedSessionID = latest
        }
    }

    func setFlowPhase(_ phase: ActionFlowPhase) {
        guard var scenario = selectedScenario else { return }
        scenario.phase = phase
        persistScenario(scenario)

        if phase == .review, let sessionId = scenario.latestSessionId {
            selectedSessionID = sessionId
            reviewSelectionRequestID = UUID()
        }
    }

    func selectScenarioStep(_ step: ActionScenarioStep) {
        selectedScenarioStepID = step.id
    }

    func toggleSkipScenarioStep(_ stepID: String) {
        guard var scenario = selectedScenario,
              let index = scenario.steps.firstIndex(where: { $0.id == stepID }) else { return }
        let current = scenario.steps[index].status
        scenario.steps[index].status = current == "skipped" ? "pending" : "skipped"
        persistScenario(scenario)
    }

    func addFeedbackToSelectedScenarioStep() {
        let text = scenarioStepFeedbackDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              var scenario = selectedScenario,
              let stepID = selectedScenarioStepID,
              let index = scenario.steps.firstIndex(where: { $0.id == stepID }) else { return }

        let item = ActionScenarioStepFeedback(
            id: UUID().uuidString,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            instruction: text
        )
        scenario.steps[index].feedback.append(item)
        if scenario.steps[index].status == "pending" {
            scenario.steps[index].status = "flagged"
        }
        scenarioStepFeedbackDraft = ""
        persistScenario(scenario)
        guidedDemoStatus = "Feedback saved on step \(scenario.steps[index].index)"
    }

    func approveAndRunSelectedScenario() {
        guard let scenario = selectedScenario else {
            runGuidedCalculatorDemo(forScenarioID: nil)
            return
        }
        setFlowPhase(.edit)
        runGuidedCalculatorDemo(forScenarioID: scenario.id)
    }

    func refreshScenarios() {
        scenarios = ActionScenarioStore.shared.loadAll()
        if let selectedScenarioID, scenarios.contains(where: { $0.id == selectedScenarioID }) {
            self.selectedScenarioID = selectedScenarioID
        } else {
            self.selectedScenarioID = scenarios.first?.id
        }
        if let scenario = selectedScenario {
            if let selectedScenarioStepID, scenario.steps.contains(where: { $0.id == selectedScenarioStepID }) {
                self.selectedScenarioStepID = selectedScenarioStepID
            } else {
                selectedScenarioStepID = scenario.steps.first?.id
            }
        } else {
            selectedScenarioStepID = nil
        }
    }

    func deleteSelectedScenario() {
        guard let id = selectedScenarioID else { return }
        try? ActionScenarioStore.shared.delete(id: id)
        if selectedScenarioID == id {
            selectedScenarioID = nil
        }
        refreshScenarios()
    }

    private func persistScenario(_ scenario: ActionScenarioDocument) {
        do {
            try ActionScenarioStore.shared.save(scenario)
            if let index = scenarios.firstIndex(where: { $0.id == scenario.id }) {
                scenarios[index] = scenario
            } else {
                scenarios.insert(scenario, at: 0)
            }
            selectedScenarioID = scenario.id
        } catch {
            guidedDemoStatus = "Failed to save scenario: \(error.localizedDescription)"
            logger.error("Save scenario failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func runGuidedCalculatorDemo(forScenarioID scenarioID: String?) {
        guard !isRunningGuidedDemo else {
            return
        }

        isRunningGuidedDemo = true
        guidedDemoStatus = "Running guided capture…"

        Task {
            do {
                if let result = try await launchGuidedDemo() {
                    guidedDemoStatus = "Completed \(result.expression) = \(result.actualResult)"
                    refreshSessions()
                    selectedSessionID = result.sessionId

                    if let scenarioID,
                       var scenario = scenarios.first(where: { $0.id == scenarioID })
                        ?? ActionScenarioStore.shared.loadAll().first(where: { $0.id == scenarioID }) {
                        if !scenario.sessionIds.contains(result.sessionId) {
                            scenario.sessionIds.insert(result.sessionId, at: 0)
                        }
                        scenario.latestSessionId = result.sessionId
                        scenario.lastRunStatus = "completed"
                        scenario.phase = .review
                        scenario.title = "Calculator · \(result.expression)"
                        persistScenario(scenario)
                        selectedScenarioID = scenario.id
                        workspaceNavigationRequestID = UUID()
                        reviewSelectionRequestID = UUID()
                    }
                } else {
                    guidedDemoStatus = "Cancelled"
                    if let scenarioID, var scenario = scenarios.first(where: { $0.id == scenarioID }) {
                        scenario.lastRunStatus = "cancelled"
                        persistScenario(scenario)
                    }
                }
            } catch {
                guidedDemoStatus = "Failed: \(error.localizedDescription)"
                logger.error("Guided calculator demo failed: \(error.localizedDescription, privacy: .public)")
                if let scenarioID, var scenario = scenarios.first(where: { $0.id == scenarioID }) {
                    scenario.lastRunStatus = "failed"
                    persistScenario(scenario)
                }
            }
            isRunningGuidedDemo = false
            refreshScenarios()
        }
    }

    func refreshSessions() {
        recentSessions = loadRecentSessions()
        if let selectedSessionID, recentSessions.contains(where: { $0.id == selectedSessionID }) {
            self.selectedSessionID = selectedSessionID
        } else {
            self.selectedSessionID = recentSessions.first?.id
        }
        if recentSessions.isEmpty {
            guidedDemoStatus = isRunningGuidedDemo ? guidedDemoStatus : "No recorded sessions yet"
        }
    }

    func selectSession(_ session: ActionSessionSummary) {
        selectedSessionID = session.id
        focusedFeedbackItemID = nil
    }

    func replaySession(_ session: ActionSessionSummary) {
        NSWorkspace.shared.open(session.videoURL)
    }

    func revealSession(_ session: ActionSessionSummary) {
        NSWorkspace.shared.activateFileViewerSelecting([session.artifactDirectoryURL])
    }

    func openSessionTrace(_ session: ActionSessionSummary) {
        NSWorkspace.shared.open(session.traceURL)
    }

    func openSessionFeedback(_ session: ActionSessionSummary) {
        guard FileManager.default.fileExists(atPath: session.feedbackURL.path) else {
            return
        }
        NSWorkspace.shared.open(session.feedbackURL)
    }

    func openAgentFeedbackMarkdown(_ session: ActionSessionSummary) throws {
        try writeAgentFeedbackArtifacts(for: session)
        NSWorkspace.shared.open(session.agentFeedbackMarkdownURL)
    }

    func openAgentFeedbackJSON(_ session: ActionSessionSummary) throws {
        try writeAgentFeedbackArtifacts(for: session)
        NSWorkspace.shared.open(session.agentFeedbackJSONURL)
    }

    func copyAgentFeedbackMarkdown(_ session: ActionSessionSummary) throws {
        try writeAgentFeedbackArtifacts(for: session)
        let value = try String(contentsOf: session.agentFeedbackMarkdownURL, encoding: .utf8)
        copyToPasteboard(value)
    }

    func copyAgentFeedbackJSON(_ session: ActionSessionSummary) throws {
        try writeAgentFeedbackArtifacts(for: session)
        let value = try String(contentsOf: session.agentFeedbackJSONURL, encoding: .utf8)
        copyToPasteboard(value)
    }

    func copyAgentFeedbackLink(_ session: ActionSessionSummary, feedbackItemId: String? = nil) throws {
        let token = try ActionSessionLinkStore.shared.register(session: session, feedbackItemId: feedbackItemId)
        copyToPasteboard("action://r/\(token)")
    }

    func handleIncomingDeepLink(_ url: URL) {
        guard url.scheme?.lowercased() == "action" else {
            return
        }

        let token: String
        if url.host()?.lowercased() == "r" {
            token = url.pathComponents.dropFirst().first ?? ""
        } else {
            token = url.host() ?? ""
        }

        guard !token.isEmpty else {
            return
        }

        do {
            guard let target = try ActionSessionLinkStore.shared.resolve(token: token),
                  let session = try loadSession(at: URL(fileURLWithPath: target.artifactDirectoryPath, isDirectory: true)) else {
                notes.append("deepLinkMissing=\(token)")
                return
            }

            if !recentSessions.contains(where: { $0.id == session.id }) {
                recentSessions.insert(session, at: 0)
            }
            selectedSessionID = session.id
            focusedFeedbackItemID = target.feedbackItemId
            reviewSelectionRequestID = UUID()
        } catch {
            notes.append("deepLinkError=\(error.localizedDescription)")
        }
    }

    func openSessionScreenshot(_ session: ActionSessionSummary) {
        if let resultScreenshotURL = session.resultScreenshotURL {
            NSWorkspace.shared.open(resultScreenshotURL)
        } else if let stageScreenshotURL = session.stageScreenshotURL {
            NSWorkspace.shared.open(stageScreenshotURL)
        }
    }

    /// Permanently removes a session's artifact directory from disk.
    func deleteSession(_ session: ActionSessionSummary) throws {
        try FileManager.default.removeItem(at: session.artifactDirectoryURL)
        if selectedSessionID == session.id {
            selectedSessionID = nil
            focusedFeedbackItemID = nil
        }
        refreshSessions()
        logger.notice("Deleted session \(session.sessionId, privacy: .public)")
    }

    var selectedSession: ActionSessionSummary? {
        if let selectedSessionID,
           let selected = recentSessions.first(where: { $0.id == selectedSessionID }) {
            return selected
        }
        return recentSessions.first
    }

    func startAgent() {
        do {
            try agentProcess.startIfNeeded()
            Task {
                await refreshAgentStatus()
                await refreshPermissionsViaAgent()
            }
        } catch {
            agentStatus = "Failed to start agent"
            notes = ["agentError=\(error.localizedDescription)"]
        }
    }

    func stopAgent() {
        agentProcess.stopIfNeeded()
        consoleReachabilityTask?.cancel()
        consoleWatchdogTask?.cancel()
        if let localConsoleProcess, localConsoleProcess.isRunning {
            localConsoleProcess.terminate()
            self.localConsoleProcess = nil
            consoleIsManagedByAction = false
        }
    }

    func setAppearanceMode(_ mode: ActionAppearanceMode) {
        appearanceMode = mode
        ActionAppearanceStore.shared.mode = mode
    }

    private func browserController() -> ActionBrowserWindowController {
        if let browserWindowController {
            return browserWindowController
        }
        let controller = ActionBrowserWindowController()
        controller.onStatusChange = { [weak self] text in
            self?.consoleStatus = text
        }
        controller.onCommand = { [weak self] command in
            self?.handleWebViewCommand(command)
        }
        browserWindowController = controller
        return controller
    }

    private func repositoryRootURL() -> URL {
        let bundleCandidate = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: bundleCandidate.appendingPathComponent("package.json").path) {
            return bundleCandidate
        }

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        if FileManager.default.fileExists(atPath: cwd.appendingPathComponent("package.json").path) {
            return cwd
        }

        return FileManager.default.homeDirectoryForCurrentUser
    }

    private func consoleLogURL() -> URL {
        let directory = sessionsDirectoryURL().deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("console.log")
    }

    private func scheduleConsoleProbeBurst() {
        consoleReachabilityTask?.cancel()
        consoleReachabilityTask = Task { @MainActor in
            for index in 0..<8 {
                await updateConsoleReachability()
                if Task.isCancelled {
                    return
                }
                if consoleIsReachable && index >= 1 {
                    return
                }
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    private func updateConsoleReachability() async {
        let reachable = await probeConsoleReachability()
        consoleIsReachable = reachable

        if reachable {
            if let localConsoleProcess, localConsoleProcess.isRunning {
                consoleStatus = "Ready"
                consoleDetail = localConsoleURL.absoluteString
                consoleIsManagedByAction = true
            } else {
                consoleStatus = "Ready"
                consoleDetail = localConsoleURL.absoluteString
            }
        } else if let localConsoleProcess, localConsoleProcess.isRunning {
            consoleStatus = "Starting…"
            consoleDetail = "Waiting for the HUD to answer."
            consoleIsManagedByAction = true
        } else if !consoleAutoEnsureEnabled {
            consoleStatus = "Off"
            consoleDetail = "HUD is stopped."
            consoleIsManagedByAction = false
        } else {
            consoleStatus = "Off"
            consoleDetail = "Start the HUD when you need diagnostics."
            consoleIsManagedByAction = false
        }
    }

    private func startConsoleWatchdog() {
        consoleWatchdogTask?.cancel()
        consoleWatchdogTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))

            while !Task.isCancelled {
                let reachable = await probeConsoleReachability()
                self.consoleIsReachable = reachable

                if !reachable, self.consoleAutoEnsureEnabled, (self.localConsoleProcess?.isRunning != true) {
                    self.consoleStatus = "Starting…"
                    self.consoleDetail = "Opening the local HUD."
                    self.startLocalConsole()
                } else {
                    await self.updateConsoleReachability()
                }

                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func probeConsoleReachability() async -> Bool {
        var request = URLRequest(url: localConsoleURL)
        request.timeoutInterval = 1.0
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                return (200..<500).contains(httpResponse.statusCode)
            }
            return true
        } catch {
            return false
        }
    }

    private func refreshAgentStatus() async {
        do {
            let response = try await agentClient.send(method: .status)
            if response.ok {
                agentStatus = "Connected"
                if let result = response.result {
                    var updatedNotes = notes.filter { !$0.hasPrefix("agent") }
                    updatedNotes.append("agentPid=\(result["pid"] ?? "unknown")")
                    updatedNotes.append("agentMethods=\(result["methods"] ?? "")")
                    notes = updatedNotes
                }
            } else {
                agentStatus = response.error ?? "Agent error"
            }
        } catch {
            agentStatus = "Disconnected"
            logger.error("Agent status failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func refreshPermissionsViaAgent() async {
        await updatePermissions(using: .permissionsSnapshot)
    }

    private func requestPermissionsViaAgent() async {
        await updatePermissions(using: .permissionsRequest)
    }

    private func updatePermissions(using method: ActionAgentMethod) async {
        do {
            let response = try await agentClient.send(method: method)
            if let result = response.result {
                accessibilityStatus = (result["accessibility"] ?? "unknown").capitalized
                screenRecordingStatus = (result["screenRecording"] ?? "unknown").capitalized
                var updatedNotes = notes.filter { !$0.hasPrefix("agentBundlePath=") }
                if let bundlePath = result["bundlePath"] {
                    updatedNotes.append("agentBundlePath=\(bundlePath)")
                }
                notes = updatedNotes
                agentStatus = "Connected"
            } else {
                agentStatus = response.error ?? "Agent error"
            }
        } catch {
            agentStatus = "Disconnected"
            logger.error("Agent permissions call failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func openSettingsViaAgent(_ method: ActionAgentMethod) async {
        do {
            _ = try await agentClient.send(method: method)
            agentStatus = "Connected"
        } catch {
            agentStatus = "Disconnected"
            logger.error("Agent settings call failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func sessionsDirectoryURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Action/sessions", isDirectory: true)
    }

    func loadFeedback(for session: ActionSessionSummary) -> ActionSessionFeedbackDocument {
        let feedbackURL = session.feedbackURL
        guard let data = try? Data(contentsOf: feedbackURL),
              let document = try? JSONDecoder().decode(ActionSessionFeedbackDocument.self, from: data) else {
            return .empty(for: session.sessionId)
        }
        return document
    }

    func saveFeedback(_ document: ActionSessionFeedbackDocument, for session: ActionSessionSummary) throws {
        var updatedDocument = document
        updatedDocument.updatedAt = ISO8601DateFormatter().string(from: Date())
        let data = try JSONEncoder.pretty.encode(updatedDocument)
        try data.write(to: session.feedbackURL, options: .atomic)
        try writeAgentFeedbackArtifacts(updatedDocument, for: session)
        refreshSessions()
    }

    private func writeAgentFeedbackArtifacts(for session: ActionSessionSummary) throws {
        try writeAgentFeedbackArtifacts(loadFeedback(for: session), for: session)
    }

    private func writeAgentFeedbackArtifacts(_ document: ActionSessionFeedbackDocument, for session: ActionSessionSummary) throws {
        let export = document.agentExport(for: session)
        let exportData = try JSONEncoder.pretty.encode(export)
        try exportData.write(to: session.agentFeedbackJSONURL, options: .atomic)
        try document.agentMarkdown(for: session).write(to: session.agentFeedbackMarkdownURL, atomically: true, encoding: .utf8)
    }

    private func copyToPasteboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    private func loadRecentSessions(limit: Int = 48) -> [ActionSessionSummary] {
        let sessionsURL = sessionsDirectoryURL()

        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: sessionsURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let sortedURLs = urls.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return lhsDate > rhsDate
        }

        return sortedURLs.prefix(limit).compactMap { try? loadSession(at: $0) }
    }

    private func loadSession(at sessionURL: URL) throws -> ActionSessionSummary? {
        let isoFormatter = ISO8601DateFormatter()
        let traceURL = sessionURL.appendingPathComponent("trace.json")
        let feedbackURL = sessionURL.appendingPathComponent("feedback.json")
        guard let data = try? Data(contentsOf: traceURL),
              let trace = try? JSONDecoder().decode(ActionSessionTrace.self, from: data) else {
            return nil
        }

        let screenshots = trace.screenshots.map(URL.init(fileURLWithPath:))
        let stageScreenshotURL = screenshots.first(where: { $0.lastPathComponent == "stage.png" }) ?? screenshots.first
        let resultScreenshotURL = screenshots.first(where: { $0.lastPathComponent == "result.png" })
        let feedbackCount = ((try? Data(contentsOf: feedbackURL))
            .flatMap { try? JSONDecoder().decode(ActionSessionFeedbackDocument.self, from: $0) })?.items.count ?? 0
        let startedAt = isoFormatter.date(from: trace.startedAt)
        let finishedAt = isoFormatter.date(from: trace.finishedAt)
        let videoURL = URL(fileURLWithPath: trace.videoPath)
        let durationSeconds = Self.resolveDurationSeconds(
            videoURL: videoURL,
            startedAt: startedAt,
            finishedAt: finishedAt
        )

        return ActionSessionSummary(
            id: trace.sessionId,
            sessionId: trace.sessionId,
            artifactDirectoryURL: sessionURL,
            videoURL: videoURL,
            traceURL: traceURL,
            feedbackURL: feedbackURL,
            stageScreenshotURL: stageScreenshotURL,
            resultScreenshotURL: resultScreenshotURL,
            expression: trace.expression,
            expectedResult: trace.expectedResult,
            actualResult: trace.actualResult,
            startedAt: startedAt,
            finishedAt: finishedAt,
            feedbackCount: feedbackCount,
            durationSeconds: durationSeconds
        )
    }

    private static func resolveDurationSeconds(
        videoURL: URL,
        startedAt: Date?,
        finishedAt: Date?
    ) -> Double? {
        if FileManager.default.fileExists(atPath: videoURL.path) {
            let asset = AVURLAsset(url: videoURL)
            let seconds = CMTimeGetSeconds(asset.duration)
            if seconds.isFinite, seconds > 0 {
                return seconds
            }
        }
        if let startedAt, let finishedAt {
            let wall = finishedAt.timeIntervalSince(startedAt)
            if wall.isFinite, wall > 0 {
                return wall
            }
        }
        return nil
    }

    private func launchGuidedDemo() async throws -> GuidedCaptureLauncherResult? {
        let replyURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("action-guided-demo-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: replyURL) }

        let bundlePath = Bundle.main.bundleURL.path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [
            "-n", bundlePath,
            "--args",
            "guided-calculator-demo",
            "--reply-file", replyURL.path,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw NSError(
                domain: "ActionLauncher",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "Failed to launch guided calculator demo"]
            )
        }

        for _ in 0..<300 {
            if let data = try? Data(contentsOf: replyURL), !data.isEmpty {
                if let response = try? JSONDecoder().decode(ActionHostResponse.self, from: data) {
                    if response.status == "cancelled" {
                        return nil
                    }
                    if response.status == "error" {
                        throw NSError(
                            domain: "ActionLauncher",
                            code: 2,
                            userInfo: [NSLocalizedDescriptionKey: response.detail ?? "Guided demo failed"]
                        )
                    }
                }

                return try JSONDecoder().decode(GuidedCaptureLauncherResult.self, from: data)
            }
            try await Task.sleep(for: .milliseconds(200))
        }

        throw NSError(
            domain: "ActionLauncher",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Guided demo did not write a reply file"]
        )
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension String {
    func quotedForShell() -> String {
        "'" + self.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
