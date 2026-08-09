import Darwin
import Foundation

enum ActionDriveLeaseError: LocalizedError {
    case invalidInput(String)
    case unknownLease(String)
    case leaseNotOwned(String)
    case leaseNotActive(String)
    case ambiguousLease

    var errorDescription: String? {
        switch self {
        case .invalidInput(let message):
            return message
        case .unknownLease(let leaseID):
            return "Unknown drive lease: \(leaseID)"
        case .leaseNotOwned(let leaseID):
            return "Drive lease \(leaseID) belongs to another client"
        case .leaseNotActive(let leaseID):
            return "Drive lease \(leaseID) is not active"
        case .ambiguousLease:
            return "Multiple drive leases are active for this client; pass leaseId explicitly"
        }
    }
}

struct ActionDriveLease: Codable, Equatable, Sendable {
    var leaseId: String
    var agent: String
    var task: String
    var mode: String
    var status: String
    var sessionId: String
    var startedAt: String
    var lastActAt: String
    var releasedAt: String?
    var outcome: String?
    var summary: String?
    var implicit: Bool?
    var stopFile: String
    var lastAxTier: String?
}

struct ActionDriveBeginResult: Sendable {
    let status: String
    let lease: ActionDriveLease
    let reason: String?
}

struct ActionDriveStatusSnapshot: Codable, Equatable, Sendable {
    let state: String
    let leases: [ActionDriveLease]
    let activeCount: Int
}

private struct ActionStoredDriveLease: Codable, Sendable {
    var ownerID: String
    var lease: ActionDriveLease
}

actor ActionDriveLeaseStore {
    static let idleExpiry: TimeInterval = 90
    static let maximumDuration: TimeInterval = 30 * 60
    static let terminalRetention: TimeInterval = 8

    private let rootURL: URL
    private let idleExpiry: TimeInterval
    private let maximumDuration: TimeInterval
    private let terminalRetention: TimeInterval
    private let now: @Sendable () -> Date
    private let publishesPresence: Bool
    private var records: [String: ActionStoredDriveLease]

    init(
        rootURL: URL = ActionDriveLeaseStore.defaultRootURL,
        idleExpiry: TimeInterval = ActionDriveLeaseStore.idleExpiry,
        maximumDuration: TimeInterval = ActionDriveLeaseStore.maximumDuration,
        terminalRetention: TimeInterval = ActionDriveLeaseStore.terminalRetention,
        publishesPresence: Bool = true,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.rootURL = rootURL
        self.idleExpiry = idleExpiry
        self.maximumDuration = maximumDuration
        self.terminalRetention = terminalRetention
        self.publishesPresence = publishesPresence
        self.now = now

        var loaded = Self.loadRecords(from: rootURL)
        let startupDate = now()
        for (leaseID, var record) in loaded where record.lease.status == "driving" {
            record.lease.status = "expired"
            record.lease.outcome = "expired"
            record.lease.releasedAt = actionDriveISO8601(startupDate)
            record.lease.summary = "Lease owner was disconnected when the Action agent restarted"
            loaded[leaseID] = record
            try? Self.persist(record, rootURL: rootURL)
            if publishesPresence {
                ActionDrivePresencePublisher.remove(leaseID: leaseID)
            }
        }
        records = loaded
    }

    func begin(
        ownerID: String,
        agent rawAgent: String,
        task rawTask: String,
        mode rawMode: String?,
        sessionID rawSessionID: String?,
        implicit: Bool
    ) throws -> ActionDriveBeginResult {
        let at = now()
        try sweep(at: at)

        let agent = rawAgent.trimmingCharacters(in: .whitespacesAndNewlines)
        let task = rawTask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !agent.isEmpty else {
            throw ActionDriveLeaseError.invalidInput("drive.begin requires agent")
        }
        guard !task.isEmpty else {
            throw ActionDriveLeaseError.invalidInput("drive.begin requires task")
        }

        let mode = rawMode == "attention" ? "attention" : "background"
        let leaseID = actionDriveLeaseID(at: at)
        let sessionID = rawSessionID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedSessionID = sessionID?.isEmpty == false ? sessionID! : "drive_\(leaseID)"
        let stopFile = rootURL.appendingPathComponent("\(actionDriveSanitize(leaseID)).stop").path
        try? FileManager.default.removeItem(atPath: stopFile)
        let atString = actionDriveISO8601(at)

        if mode == "attention" {
            let reason = "Attention mode requires operator approval, which is not available yet. Use background mode."
            let lease = ActionDriveLease(
                leaseId: leaseID,
                agent: agent,
                task: task,
                mode: mode,
                status: "denied",
                sessionId: resolvedSessionID,
                startedAt: atString,
                lastActAt: atString,
                releasedAt: atString,
                outcome: "cancelled",
                summary: reason,
                implicit: implicit ? true : nil,
                stopFile: stopFile,
                lastAxTier: nil
            )
            let record = ActionStoredDriveLease(ownerID: ownerID, lease: lease)
            records[leaseID] = record
            try persist(record)
            return ActionDriveBeginResult(status: "denied", lease: lease, reason: reason)
        }

        let lease = ActionDriveLease(
            leaseId: leaseID,
            agent: agent,
            task: task,
            mode: mode,
            status: "driving",
            sessionId: resolvedSessionID,
            startedAt: atString,
            lastActAt: atString,
            releasedAt: nil,
            outcome: nil,
            summary: nil,
            implicit: implicit ? true : nil,
            stopFile: stopFile,
            lastAxTier: nil
        )
        let record = ActionStoredDriveLease(ownerID: ownerID, lease: lease)
        records[leaseID] = record
        try persist(record)
        do {
            try publishPresence(for: lease, at: at)
        } catch {
            records.removeValue(forKey: leaseID)
            try? FileManager.default.removeItem(at: recordURL(for: leaseID))
            if publishesPresence {
                ActionDrivePresencePublisher.remove(leaseID: leaseID)
            }
            throw error
        }
        return ActionDriveBeginResult(status: "granted", lease: lease, reason: nil)
    }

    func touch(
        ownerID: String,
        leaseID: String?,
        axTier: String?
    ) throws -> ActionDriveLease? {
        let at = now()
        try sweep(at: at)
        guard var record = try resolveActiveRecord(ownerID: ownerID, leaseID: leaseID) else {
            return nil
        }

        record.lease.lastActAt = actionDriveISO8601(at)
        if let axTier, !axTier.isEmpty {
            record.lease.lastAxTier = axTier
        }
        records[record.lease.leaseId] = record
        try persist(record)
        do {
            try publishPresence(for: record.lease, at: at)
        } catch {
            record.lease.status = "cancelled"
            record.lease.outcome = "cancelled"
            record.lease.releasedAt = actionDriveISO8601(at)
            record.lease.summary = "Supervision presence became unavailable"
            records[record.lease.leaseId] = record
            try? persist(record)
            if publishesPresence {
                ActionDrivePresencePublisher.remove(leaseID: record.lease.leaseId)
            }
            throw error
        }
        return record.lease
    }

    func release(
        ownerID: String,
        leaseID: String,
        outcome rawOutcome: String?,
        summary: String?
    ) throws -> ActionDriveLease {
        let at = now()
        try sweep(at: at)
        guard var record = records[leaseID] else {
            throw ActionDriveLeaseError.unknownLease(leaseID)
        }
        guard record.ownerID == ownerID else {
            throw ActionDriveLeaseError.leaseNotOwned(leaseID)
        }
        guard record.lease.status == "driving" else {
            return record.lease
        }

        let outcome = ["done", "failed", "cancelled"].contains(rawOutcome ?? "")
            ? rawOutcome!
            : "cancelled"
        record.lease.status = outcome
        record.lease.outcome = outcome
        record.lease.releasedAt = actionDriveISO8601(at)
        record.lease.lastActAt = actionDriveISO8601(at)
        record.lease.summary = summary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? record.lease.summary
        records[leaseID] = record
        try persist(record)
        try publishPresence(for: record.lease, at: at)
        return record.lease
    }

    func releaseOwned(by ownerID: String, summary: String) {
        let at = now()
        for (leaseID, var record) in records
            where record.ownerID == ownerID && record.lease.status == "driving" {
            record.lease.status = "cancelled"
            record.lease.outcome = "cancelled"
            record.lease.releasedAt = actionDriveISO8601(at)
            record.lease.lastActAt = actionDriveISO8601(at)
            record.lease.summary = summary
            records[leaseID] = record
            try? persist(record)
            try? publishPresence(for: record.lease, at: at)
        }
    }

    func status() throws -> ActionDriveStatusSnapshot {
        try sweep(at: now())
        let leases = records.values
            .map(\.lease)
            .sorted { $0.lastActAt > $1.lastActAt }
        let activeCount = leases.filter { $0.status == "driving" }.count
        return ActionDriveStatusSnapshot(
            state: activeCount > 0 ? "driving" : "idle",
            leases: leases,
            activeCount: activeCount
        )
    }

    func sweep() throws {
        try sweep(at: now())
    }

    private func sweep(at: Date) throws {
        for (leaseID, var record) in records {
            if record.lease.status == "driving" {
                let stopRequested = FileManager.default.fileExists(atPath: record.lease.stopFile)
                let lastAct = actionDriveDate(record.lease.lastActAt) ?? at
                let started = actionDriveDate(record.lease.startedAt) ?? at
                let reason: String?
                if stopRequested {
                    reason = "stop-file"
                } else if at.timeIntervalSince(lastAct) >= idleExpiry {
                    reason = "idle"
                } else if at.timeIntervalSince(started) >= maximumDuration {
                    reason = "max-duration"
                } else {
                    reason = nil
                }

                if let reason {
                    let stopped = reason == "stop-file"
                    record.lease.status = stopped ? "cancelled" : "expired"
                    record.lease.outcome = stopped ? "cancelled" : "expired"
                    record.lease.releasedAt = actionDriveISO8601(at)
                    record.lease.summary = stopped
                        ? "Stopped by supervisor"
                        : (reason == "idle" ? "Lease expired after idle silence" : "Lease exceeded maximum duration")
                    records[leaseID] = record
                    try persist(record)
                    try publishPresence(for: record.lease, at: at)
                } else {
                    try publishPresence(for: record.lease, at: at)
                }
                continue
            }

            guard let releasedAt = record.lease.releasedAt.flatMap(actionDriveDate),
                  at.timeIntervalSince(releasedAt) >= terminalRetention else {
                continue
            }
            records.removeValue(forKey: leaseID)
            try? FileManager.default.removeItem(at: recordURL(for: leaseID))
            if publishesPresence {
                ActionDrivePresencePublisher.remove(leaseID: leaseID)
            }
        }
    }

    private func resolveActiveRecord(
        ownerID: String,
        leaseID: String?
    ) throws -> ActionStoredDriveLease? {
        if let leaseID, !leaseID.isEmpty {
            guard let record = records[leaseID] else {
                throw ActionDriveLeaseError.unknownLease(leaseID)
            }
            guard record.ownerID == ownerID else {
                throw ActionDriveLeaseError.leaseNotOwned(leaseID)
            }
            guard record.lease.status == "driving" else {
                throw ActionDriveLeaseError.leaseNotActive(leaseID)
            }
            return record
        }

        let active = records.values.filter {
            $0.ownerID == ownerID && $0.lease.status == "driving"
        }
        if active.count > 1 {
            throw ActionDriveLeaseError.ambiguousLease
        }
        return active.first
    }

    private func persist(_ record: ActionStoredDriveLease) throws {
        try Self.persist(record, rootURL: rootURL)
    }

    private static func persist(_ record: ActionStoredDriveLease, rootURL: URL) throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(record)
        let url = rootURL.appendingPathComponent("\(actionDriveSanitize(record.lease.leaseId)).json")
        try data.write(to: url, options: .atomic)
    }

    private func publishPresence(for lease: ActionDriveLease, at: Date) throws {
        guard publishesPresence else {
            return
        }
        try ActionDrivePresencePublisher.publish(
            lease: lease,
            at: at,
            activeTTL: 2.5,
            terminalTTL: terminalRetention
        )
    }

    private func recordURL(for leaseID: String) -> URL {
        rootURL.appendingPathComponent("\(actionDriveSanitize(leaseID)).json")
    }

    private static func loadRecords(from rootURL: URL) -> [String: ActionStoredDriveLease] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil
        ) else {
            return [:]
        }

        let decoder = JSONDecoder()
        var loaded: [String: ActionStoredDriveLease] = [:]
        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url) else {
                continue
            }
            if let record = try? decoder.decode(ActionStoredDriveLease.self, from: data) {
                loaded[record.lease.leaseId] = record
                continue
            }
            // Migrate records written by the earlier process-local implementation.
            if let lease = try? decoder.decode(ActionDriveLease.self, from: data) {
                loaded[lease.leaseId] = ActionStoredDriveLease(ownerID: "stale", lease: lease)
            }
        }
        return loaded
    }

    private static var defaultRootURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Action/runtime/drive/leases", isDirectory: true)
    }
}

private struct ActionDriveSupervisionRegistration: Codable {
    let id: String
    let title: String
    let detail: String?
    let controlFile: String?
    let stopFile: String?
    let ownsVisibleControls: Bool?
    let avoidedDisplayID: UInt32?
    let expiresAt: String?
    let updatedAt: String
}

private enum ActionDrivePresencePublisher {
    static func publish(
        lease: ActionDriveLease,
        at: Date,
        activeTTL: TimeInterval,
        terminalTTL: TimeInterval
    ) throws {
        let expirationBase = lease.status == "driving"
            ? at
            : (lease.releasedAt.flatMap(actionDriveDate) ?? at)
        let expiration = expirationBase.addingTimeInterval(
            lease.status == "driving" ? activeTTL : terminalTTL
        )
        let registration = ActionDriveSupervisionRegistration(
            id: lease.leaseId,
            title: "\(lease.agent) · \(lease.task)",
            detail: detail(for: lease),
            controlFile: nil,
            stopFile: lease.stopFile,
            ownsVisibleControls: false,
            avoidedDisplayID: nil,
            expiresAt: actionDriveISO8601(expiration),
            updatedAt: actionDriveISO8601(at)
        )

        try FileManager.default.createDirectory(at: registrationsURL, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: overlayStopURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(registration).write(
            to: registrationURL(leaseID: lease.leaseId),
            options: .atomic
        )
        try ensureOverlayRunning()
    }

    static func remove(leaseID: String) {
        try? FileManager.default.removeItem(at: registrationURL(leaseID: leaseID))
    }

    private static var baseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Action/runtime/supervision", isDirectory: true)
    }

    private static var registrationsURL: URL {
        baseURL.appendingPathComponent("registrations", isDirectory: true)
    }

    private static var overlayPIDURL: URL {
        baseURL.appendingPathComponent("overlay.pid")
    }

    private static var overlayStopURL: URL {
        baseURL.appendingPathComponent("overlay.stop")
    }

    private static func registrationURL(leaseID: String) -> URL {
        registrationsURL.appendingPathComponent("\(actionDriveSanitize(leaseID)).json")
    }

    private static func detail(for lease: ActionDriveLease) -> String {
        guard lease.status == "driving" else {
            let outcome = (lease.outcome ?? lease.status).uppercased()
            if let summary = lease.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
               !summary.isEmpty {
                return "\(outcome) · \(summary)"
            }
            return outcome
        }

        switch lease.lastAxTier {
        case "observe":
            return "Observing the current app"
        case "semantic":
            return "Using app controls in the background"
        case "target-focus":
            return "Changing focus in the target app"
        case "app-api":
            return "Using the app automation interface"
        case "attention":
            return "Using foreground keyboard or pointer control"
        default:
            return "Working in the background"
        }
    }

    private static func ensureOverlayRunning() throws {
        if let raw = try? String(contentsOf: overlayPIDURL, encoding: .utf8),
           let pid = Int32(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
           kill(pid, 0) == 0 {
            return
        }

        let bundleURL = try resolveActionAppURL()
        let replyURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("action-drive-overlay-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: replyURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [
            "-n",
            bundleURL.path,
            "--args",
            "supervision-overlay",
            "--reply-file",
            replyURL.path,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()

        for _ in 0..<50 {
            if let data = try? Data(contentsOf: replyURL),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               object["status"] as? String == "supervision-overlay-running" {
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw NSError(
            domain: "ActionDrivePresencePublisher",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Supervision overlay did not acknowledge launch"]
        )
    }

    private static func resolveActionAppURL() throws -> URL {
        var candidate = Bundle.main.bundleURL
        while candidate.path != "/" {
            if candidate.lastPathComponent == "Action.app" {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        throw NSError(
            domain: "ActionDrivePresencePublisher",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unable to resolve the containing Action.app bundle"]
        )
    }
}

private func actionDriveISO8601(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

private func actionDriveDate(_ raw: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: raw) {
        return date
    }
    return ISO8601DateFormatter().date(from: raw)
}

private func actionDriveLeaseID(at: Date) -> String {
    let stamp = actionDriveISO8601(at)
        .replacingOccurrences(of: "-", with: "")
        .replacingOccurrences(of: ":", with: "")
        .replacingOccurrences(of: ".", with: "")
        .replacingOccurrences(of: "T", with: "_")
        .replacingOccurrences(of: "Z", with: "")
    return "drive_\(stamp)_\(UUID().uuidString.lowercased().prefix(8))"
}

private func actionDriveSanitize(_ raw: String) -> String {
    raw.replacingOccurrences(
        of: #"[^A-Za-z0-9._-]+"#,
        with: "_",
        options: .regularExpression
    )
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
