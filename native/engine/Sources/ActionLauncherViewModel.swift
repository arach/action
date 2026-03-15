import AppKit
import ActionCore
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

    var agentFeedbackMarkdownURL: URL {
        artifactDirectoryURL.appendingPathComponent("agent-feedback.md")
    }

    var agentFeedbackJSONURL: URL {
        artifactDirectoryURL.appendingPathComponent("agent-feedback.json")
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
    @Published var consoleStatus: String = "Local console ready"
    @Published var consoleDetail: String = "Use the local HUD console without leaving Action."
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

    init() {
        self.consoleURL = localConsoleURL
        self.appearanceMode = ActionAppearanceStore.shared.mode
        refreshSessions()
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
            consoleStatus = "Local console already running"
            consoleDetail = localConsoleURL.absoluteString
            return
        }

        if let localConsoleProcess, localConsoleProcess.isRunning {
            consoleStatus = "Local console already running on \(localConsoleURL.absoluteString)"
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
                self.consoleStatus = "Local console exited (\(proc.terminationStatus))"
                self.consoleDetail = "Inspect logs if it exited unexpectedly."
                self.refreshConsoleState()
            }
        }

        do {
            try process.run()
            localConsoleProcess = process
            consoleIsManagedByAction = true
            consoleStatus = "Starting local console…"
            consoleDetail = "Launching `bun run hud` and waiting for \(localConsoleURL.absoluteString)"
            logger.notice("Started local console process (pid=\(process.processIdentifier, privacy: .public))")
            scheduleConsoleProbeBurst()
        } catch {
            consoleStatus = "Failed to start local console: \(error.localizedDescription)"
            consoleDetail = "Could not spawn the local HUD process."
            logger.error("Failed to start local console: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stopLocalConsole() {
        consoleAutoEnsureEnabled = false

        guard let localConsoleProcess, localConsoleProcess.isRunning else {
            if consoleIsReachable {
                consoleStatus = "Auto-start paused"
                consoleDetail = "The console is reachable from another process. Action will not auto-start it until you start or restart it here."
            } else {
                consoleStatus = "Auto-start paused"
                consoleDetail = "The local console will stay offline until you start it again."
            }
            return
        }

        localConsoleProcess.terminate()
        self.localConsoleProcess = nil
        consoleIsManagedByAction = false
        consoleStatus = "Stopping local console…"
        consoleDetail = "Auto-start is paused until you start or restart the console again."
        scheduleConsoleProbeBurst()
    }

    func restartLocalConsole() {
        consoleAutoEnsureEnabled = true
        if let localConsoleProcess, localConsoleProcess.isRunning {
            localConsoleProcess.terminate()
            self.localConsoleProcess = nil
        }
        consoleIsManagedByAction = false
        consoleStatus = "Restarting local console…"
        consoleDetail = "Re-launching `bun run hud`."
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
        consoleStatus = "Copied console launch command"
        consoleDetail = command
    }

    func openConsoleLog() {
        let logURL = consoleLogURL()
        guard FileManager.default.fileExists(atPath: logURL.path) else {
            consoleStatus = "No console log yet"
            consoleDetail = "Start the console from Action to generate a log."
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
        guard !isRunningGuidedDemo else {
            return
        }

        isRunningGuidedDemo = true
        guidedDemoStatus = "Running guided capture…"

        Task {
            do {
                let result = try await launchGuidedDemo()
                guidedDemoStatus = "Completed \(result.expression) = \(result.actualResult)"
                refreshSessions()
            } catch {
                guidedDemoStatus = "Failed: \(error.localizedDescription)"
                logger.error("Guided calculator demo failed: \(error.localizedDescription, privacy: .public)")
            }
            isRunningGuidedDemo = false
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
                consoleStatus = "Local console running"
                consoleDetail = "Managed by Action at \(localConsoleURL.absoluteString)"
                consoleIsManagedByAction = true
            } else {
                consoleStatus = "Local console reachable"
                consoleDetail = "Another process is already serving \(localConsoleURL.absoluteString)"
            }
        } else if let localConsoleProcess, localConsoleProcess.isRunning {
            consoleStatus = "Waiting for local console…"
            consoleDetail = "The process is running, but the web surface has not responded yet."
            consoleIsManagedByAction = true
        } else if !consoleAutoEnsureEnabled {
            consoleStatus = "Auto-start paused"
            consoleDetail = "The local console is offline and Action is not auto-starting it right now."
            consoleIsManagedByAction = false
        } else {
            consoleStatus = "Local console offline"
            consoleDetail = "Start it here, then open it embedded or in your browser."
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
                    self.consoleStatus = "Bootstrapping local console…"
                    self.consoleDetail = "Action is starting the HUD automatically because it was not reachable."
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

    private func loadRecentSessions(limit: Int = 8) -> [ActionSessionSummary] {
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

        return ActionSessionSummary(
            id: trace.sessionId,
            sessionId: trace.sessionId,
            artifactDirectoryURL: sessionURL,
            videoURL: URL(fileURLWithPath: trace.videoPath),
            traceURL: traceURL,
            feedbackURL: feedbackURL,
            stageScreenshotURL: stageScreenshotURL,
            resultScreenshotURL: resultScreenshotURL,
            expression: trace.expression,
            expectedResult: trace.expectedResult,
            actualResult: trace.actualResult,
            startedAt: isoFormatter.date(from: trace.startedAt),
            finishedAt: isoFormatter.date(from: trace.finishedAt),
            feedbackCount: feedbackCount
        )
    }

    private func launchGuidedDemo() async throws -> GuidedCaptureLauncherResult {
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
                if let errorResponse = try? JSONDecoder().decode(ActionHostResponse.self, from: data),
                   errorResponse.status == "error" {
                    throw NSError(
                        domain: "ActionLauncher",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: errorResponse.detail ?? "Guided demo failed"]
                    )
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
