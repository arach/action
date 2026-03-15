import ActionCore
import Foundation
import OSLog

@MainActor
final class ActionAgentProcessController {
    private let logger = Logger(subsystem: "dev.action.Action", category: "AgentProcess")
    private let port: UInt16
    private var process: Process?

    init(port: UInt16 = ActionAgentDefaults.port) {
        self.port = port
    }

    func startIfNeeded() throws {
        if let process, process.isRunning {
            return
        }

        let executableURL = try resolveAgentExecutableURL()
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["agent", "--port", String(port), "--parent-pid", String(ProcessInfo.processInfo.processIdentifier)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.standardError
        try process.run()
        self.process = process
        logger.notice("Started ActionAgent at \(executableURL.path(percentEncoded: false), privacy: .public) on port \(self.port, privacy: .public)")
    }

    func stopIfNeeded() {
        guard let process else {
            return
        }
        if process.isRunning {
            process.terminate()
        }
        self.process = nil
    }

    private func resolveAgentExecutableURL() throws -> URL {
        if let mainExecutableURL = Bundle.main.executableURL,
           FileManager.default.isExecutableFile(atPath: mainExecutableURL.path(percentEncoded: false)) {
            return mainExecutableURL
        }

        let helperExecutable = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/ActionAgent.app", isDirectory: true)
            .appendingPathComponent("Contents/MacOS/ActionAgent", isDirectory: false)
        if FileManager.default.isExecutableFile(atPath: helperExecutable.path(percentEncoded: false)) {
            return helperExecutable
        }

        if let resourceURL = Bundle.main.resourceURL {
            let bundled = resourceURL.appendingPathComponent("ActionAgent", isDirectory: false)
            if FileManager.default.isExecutableFile(atPath: bundled.path(percentEncoded: false)) {
                return bundled
            }
        }

        let sibling = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("ActionAgent", isDirectory: false)
        if FileManager.default.isExecutableFile(atPath: sibling.path(percentEncoded: false)) {
            return sibling
        }

        throw NSError(
            domain: "ActionAgentProcessController",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unable to locate bundled ActionAgent executable"]
        )
    }
}
