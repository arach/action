import Foundation
import Darwin

struct ActionSupervisionRegistration: Codable {
    let id: String
    let title: String
    let detail: String?
    let controlFile: String?
    let stopFile: String?
    let ownsVisibleControls: Bool?
    let updatedAt: String
}

enum ActionSupervisionRegistry {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static var baseDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Action/runtime/supervision", isDirectory: true)
    }

    static var registrationsDirectoryURL: URL {
        baseDirectoryURL.appendingPathComponent("registrations", isDirectory: true)
    }

    static var overlayPIDURL: URL {
        baseDirectoryURL.appendingPathComponent("overlay.pid")
    }

    static var overlayStopSignalURL: URL {
        baseDirectoryURL.appendingPathComponent("overlay.stop")
    }

    static func register(
        id: String,
        title: String,
        detail: String?,
        controlFile: String?,
        stopFile: String?,
        ownsVisibleControls: Bool = false
    ) throws {
        let registration = ActionSupervisionRegistration(
            id: id,
            title: title,
            detail: detail,
            controlFile: controlFile,
            stopFile: stopFile,
            ownsVisibleControls: ownsVisibleControls,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        try FileManager.default.createDirectory(at: registrationsDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.removeItemIfExists(at: overlayStopSignalURL)
        let url = registrationURL(for: id)
        try encoder.encode(registration).write(to: url)
        try ActionSupervisionOverlayLauncher.ensureRunning()
    }

    static func unregister(id: String) {
        try? FileManager.default.removeItem(at: registrationURL(for: id))
        let remaining = activeRegistrations().count
        if remaining == 0 {
            stopOverlay()
        }
    }

    static func activeRegistrations() -> [ActionSupervisionRegistration] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: registrationsDirectoryURL,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        let decoder = JSONDecoder()
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else {
                    return nil
                }
                return try? decoder.decode(ActionSupervisionRegistration.self, from: data)
            }
            .sorted { $0.updatedAt < $1.updatedAt }
    }

    @discardableResult
    static func triggerStopAll() -> Int {
        let registrations = activeRegistrations()
        for registration in registrations {
            if let controlFile = registration.controlFile, !controlFile.isEmpty {
                appendControlCommands(to: controlFile)
            }
            if let stopFile = registration.stopFile, !stopFile.isEmpty {
                writeMarker(path: stopFile, contents: "stop\n")
            }
        }
        return registrations.count
    }

    static func recordOverlayPID(_ pid: pid_t) {
        do {
            try FileManager.default.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)
            try Data(String(pid).utf8).write(to: overlayPIDURL)
        } catch {}
    }

    static func clearOverlayPID(ifOwnedBy ownerPID: pid_t) {
        let existing = (try? String(contentsOf: overlayPIDURL, encoding: .utf8)) ?? "missing"
        let normalized = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized == String(ownerPID) else {
            return
        }
        try? FileManager.default.removeItem(at: overlayPIDURL)
    }

    static func overlayIsRunning() -> Bool {
        guard let raw = try? String(contentsOf: overlayPIDURL, encoding: .utf8),
              let pid = Int32(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }

        if kill(pid, 0) == 0 {
            return true
        }

        return errno != ESRCH
    }

    static func stopOverlay() {
        writeMarker(path: overlayStopSignalURL.path, contents: "stop\n")
    }

    private static func registrationURL(for id: String) -> URL {
        registrationsDirectoryURL.appendingPathComponent("\(sanitizedID(id)).json")
    }

    private static func sanitizedID(_ raw: String) -> String {
        raw.replacingOccurrences(of: #"[^A-Za-z0-9._-]+"#, with: "_", options: .regularExpression)
    }

    private static func appendControlCommands(to path: String) {
        let line = "stop\nquit\n"
        do {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: path) {
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(line.utf8))
                try handle.close()
            } else {
                try Data(line.utf8).write(to: url)
            }
        } catch {}
    }

    private static func writeMarker(path: String, contents: String) {
        let url = URL(fileURLWithPath: path)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: url)
        } catch {}
    }
}

enum ActionSupervisionOverlayLauncher {
    static func ensureRunning() throws {
        if ActionSupervisionRegistry.overlayIsRunning() {
            return
        }

        try FileManager.default.removeItemIfExists(at: ActionSupervisionRegistry.overlayStopSignalURL)
        let bundleURL = try resolveAppBundleURL()
        let replyFile = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("action-supervision-overlay-\(UUID().uuidString).json")

        defer {
            try? FileManager.default.removeItem(at: replyFile)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", bundleURL.path, "--args", "supervision-overlay", "--reply-file", replyFile.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()
        try waitForOverlayReply(at: replyFile)
    }

    private static func resolveAppBundleURL() throws -> URL {
        let bundleURL = Bundle.main.bundleURL
        var fallbackAppBundleURL: URL?

        func inspect(candidate: URL) -> URL? {
            guard candidate.pathExtension == "app" else {
                return nil
            }
            if fallbackAppBundleURL == nil {
                fallbackAppBundleURL = candidate
            }
            if candidate.lastPathComponent == "Action.app" {
                return candidate
            }
            return nil
        }

        if let resolved = inspect(candidate: bundleURL) {
            return resolved
        }

        if let executableURL = Bundle.main.executableURL {
            var candidate = executableURL.deletingLastPathComponent()
            while candidate.path != "/" {
                if let resolved = inspect(candidate: candidate) {
                    return resolved
                }
                candidate.deleteLastPathComponent()
            }
        }

        if let fallbackAppBundleURL {
            return fallbackAppBundleURL
        }

        throw NSError(
            domain: "ActionSupervisionOverlayLauncher",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unable to resolve Action.app bundle URL for supervision overlay"]
        )
    }

    private static func waitForOverlayReply(at replyFile: URL) throws {
        for _ in 0..<50 {
            if let data = try? Data(contentsOf: replyFile),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let status = object["status"] as? String,
               status == "supervision-overlay-running" {
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }

        throw NSError(
            domain: "ActionSupervisionOverlayLauncher",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Supervision overlay did not acknowledge launch"]
        )
    }
}

private extension FileManager {
    func removeItemIfExists(at url: URL) throws {
        guard fileExists(atPath: url.path) else {
            return
        }
        try removeItem(at: url)
    }
}
