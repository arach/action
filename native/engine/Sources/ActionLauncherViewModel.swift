import AppKit
import ActionCore
import Foundation
import OSLog

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

    @Published var agentStatus: String = "Offline"
    @Published var accessibilityStatus: String = "Unknown"
    @Published var screenRecordingStatus: String = "Unknown"
    @Published var notes: [String] = []
    @Published var consoleURL: URL
    @Published var consoleStatus: String = "Local console ready"
    @Published var guidedDemoStatus: String = "Ready"
    @Published var recentSessions: [ActionSessionSummary] = []
    @Published var isRunningGuidedDemo: Bool = false
    @Published var selectedSessionID: String?

    init() {
        self.consoleURL = localConsoleURL
        refreshSessions()
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
        if let localConsoleProcess, localConsoleProcess.isRunning {
            consoleStatus = "Local console already running on \(localConsoleURL.absoluteString)"
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["bun", "run", "hud"]
        process.currentDirectoryURL = repositoryRootURL()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                guard let self else { return }
                self.localConsoleProcess = nil
                self.consoleStatus = "Local console exited (\(proc.terminationStatus))"
            }
        }

        do {
            try process.run()
            localConsoleProcess = process
            consoleStatus = "Starting local console on \(localConsoleURL.absoluteString)…"
            logger.notice("Started local console process (pid=\(process.processIdentifier, privacy: .public))")
        } catch {
            consoleStatus = "Failed to start local console: \(error.localizedDescription)"
            logger.error("Failed to start local console: \(error.localizedDescription, privacy: .public)")
        }
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
    }

    func setConsoleStatus(_ status: String) {
        consoleStatus = status
    }

    func openBrowserWindow() {
        logger.notice("openBrowserWindow called with URL: \(self.consoleURL.absoluteString, privacy: .public)")
        browserController().show(url: self.consoleURL)
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
        if let localConsoleProcess, localConsoleProcess.isRunning {
            localConsoleProcess.terminate()
            self.localConsoleProcess = nil
        }
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
            guard let self else {
                return
            }
            switch command {
            case .startLocalConsole:
                self.startLocalConsole()
            }
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
        refreshSessions()
    }

    private func loadRecentSessions(limit: Int = 8) -> [ActionSessionSummary] {
        let sessionsURL = sessionsDirectoryURL()
        let isoFormatter = ISO8601DateFormatter()

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

        return sortedURLs.prefix(limit).compactMap { sessionURL in
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
