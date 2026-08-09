@testable import ActionCore
import Foundation
import XCTest

final class ActionDriveLeaseStoreTests: XCTestCase {
    func testBackgroundLeaseRequiresExplicitSelectionWhenClientOwnsSeveral() async throws {
        try await withStore { store, _ in
            let first = try await store.begin(
                ownerID: "client-a",
                agent: "Agent A",
                task: "First task",
                mode: "background",
                sessionID: nil,
                implicit: false
            )
            _ = try await store.begin(
                ownerID: "client-a",
                agent: "Agent A",
                task: "Second task",
                mode: "background",
                sessionID: nil,
                implicit: false
            )

            do {
                _ = try await store.touch(ownerID: "client-a", leaseID: nil, axTier: "observe")
                XCTFail("Expected an ambiguous lease error")
            } catch ActionDriveLeaseError.ambiguousLease {
                // Expected: callers must route heartbeats explicitly.
            }

            let touched = try await store.touch(
                ownerID: "client-a",
                leaseID: first.lease.leaseId,
                axTier: "semantic"
            )
            XCTAssertEqual(touched?.leaseId, first.lease.leaseId)
            XCTAssertEqual(touched?.lastAxTier, "semantic")
        }
    }

    func testLeaseCannotBeTouchedByAnotherConnection() async throws {
        try await withStore { store, _ in
            let begun = try await store.begin(
                ownerID: "client-a",
                agent: "Agent A",
                task: "Owned task",
                mode: "background",
                sessionID: nil,
                implicit: false
            )

            do {
                _ = try await store.touch(
                    ownerID: "client-b",
                    leaseID: begun.lease.leaseId,
                    axTier: "observe"
                )
                XCTFail("Expected an ownership error")
            } catch ActionDriveLeaseError.leaseNotOwned(let leaseID) {
                XCTAssertEqual(leaseID, begun.lease.leaseId)
            }
        }
    }

    func testBackgroundLeaseCannotAuthorizeAttentionTierActions() async throws {
        try await withStore { store, _ in
            let begun = try await store.begin(
                ownerID: "client-a",
                agent: "Agent A",
                task: "Background task",
                mode: "background",
                sessionID: nil,
                implicit: false
            )

            do {
                _ = try await store.touch(
                    ownerID: "client-a",
                    leaseID: begun.lease.leaseId,
                    axTier: "attention"
                )
                XCTFail("Expected attention approval to be required")
            } catch ActionDriveLeaseError.attentionApprovalRequired {
                // Expected: a background lease cannot authorize foreground HID control.
            }

            let snapshot = try await store.status()
            XCTAssertEqual(snapshot.activeCount, 1)
            XCTAssertNil(
                snapshot.leases.first { $0.leaseId == begun.lease.leaseId }?.lastAxTier
            )
        }
    }

    func testConnectionCloseCancelsOnlyOwnedLeases() async throws {
        try await withStore { store, _ in
            let first = try await store.begin(
                ownerID: "client-a",
                agent: "Agent A",
                task: "First task",
                mode: "background",
                sessionID: nil,
                implicit: false
            )
            let second = try await store.begin(
                ownerID: "client-b",
                agent: "Agent B",
                task: "Second task",
                mode: "background",
                sessionID: nil,
                implicit: false
            )

            await store.disconnectOwner(by: "client-a", summary: "Driving client disconnected")
            let snapshot = try await store.status()
            let firstLease = snapshot.leases.first { $0.leaseId == first.lease.leaseId }
            let secondLease = snapshot.leases.first { $0.leaseId == second.lease.leaseId }
            XCTAssertEqual(firstLease?.status, "cancelled")
            XCTAssertEqual(secondLease?.status, "driving")
            XCTAssertEqual(snapshot.activeCount, 1)
        }
    }

    func testLateBeginCannotCreateALeaseAfterConnectionClose() async throws {
        try await withStore { store, _ in
            await store.disconnectOwner(by: "client-a", summary: "Driving client disconnected")

            do {
                _ = try await store.begin(
                    ownerID: "client-a",
                    agent: "Agent A",
                    task: "Late task",
                    mode: "background",
                    sessionID: nil,
                    implicit: false
                )
                XCTFail("Expected a disconnected-owner error")
            } catch ActionDriveLeaseError.invalidInput(let message) {
                XCTAssertEqual(message, "Drive client disconnected before the lease began")
            }

            let snapshot = try await store.status()
            XCTAssertEqual(snapshot.activeCount, 0)
            XCTAssertTrue(snapshot.leases.isEmpty)
        }
    }

    func testIdleAndStopSignalsTerminateLeases() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_800_000_000))
        try await withStore(clock: clock, idleExpiry: 1) { store, _ in
            let idleLease = try await store.begin(
                ownerID: "client-a",
                agent: "Agent A",
                task: "Idle task",
                mode: "background",
                sessionID: nil,
                implicit: false
            )
            clock.advance(by: 2)
            try await store.sweep()
            var snapshot = try await store.status()
            XCTAssertEqual(
                snapshot.leases.first { $0.leaseId == idleLease.lease.leaseId }?.status,
                "expired"
            )

            let stoppedLease = try await store.begin(
                ownerID: "client-a",
                agent: "Agent A",
                task: "Stopped task",
                mode: "background",
                sessionID: nil,
                implicit: false
            )
            try Data("stop\n".utf8).write(to: URL(fileURLWithPath: stoppedLease.lease.stopFile))
            try await store.sweep()
            snapshot = try await store.status()
            XCTAssertEqual(
                snapshot.leases.first { $0.leaseId == stoppedLease.lease.leaseId }?.status,
                "cancelled"
            )
        }
    }

    func testRestartExpiresPreviouslyActiveRecords() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestClock(Date(timeIntervalSince1970: 1_800_000_000))
        let firstStore = ActionDriveLeaseStore(
            rootURL: directory,
            publishesPresence: false,
            now: clock.now
        )
        let begun = try await firstStore.begin(
            ownerID: "client-a",
            agent: "Agent A",
            task: "Interrupted task",
            mode: "background",
            sessionID: nil,
            implicit: false
        )

        let restartedStore = ActionDriveLeaseStore(
            rootURL: directory,
            publishesPresence: false,
            now: clock.now
        )
        let snapshot = try await restartedStore.status()
        XCTAssertEqual(
            snapshot.leases.first { $0.leaseId == begun.lease.leaseId }?.status,
            "expired"
        )
    }

    func testMaximumDurationExpiresALeaseThatKeepsHeartbeating() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_800_000_000))
        try await withStore(clock: clock, idleExpiry: 10, maximumDuration: 1) { store, _ in
            let begun = try await store.begin(
                ownerID: "client-a",
                agent: "Agent A",
                task: "Long task",
                mode: "background",
                sessionID: nil,
                implicit: false
            )
            clock.advance(by: 0.8)
            _ = try await store.touch(
                ownerID: "client-a",
                leaseID: begun.lease.leaseId,
                axTier: "observe"
            )
            clock.advance(by: 0.8)
            try await store.sweep()
            let snapshot = try await store.status()
            XCTAssertEqual(
                snapshot.leases.first { $0.leaseId == begun.lease.leaseId }?.status,
                "expired"
            )
        }
    }

    func testTerminalRecordsArePrunedAfterChipWindow() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_800_000_000))
        try await withStore(clock: clock, terminalRetention: 1) { store, _ in
            let begun = try await store.begin(
                ownerID: "client-a",
                agent: "Agent A",
                task: "Short task",
                mode: "background",
                sessionID: nil,
                implicit: false
            )
            try Data("stop\n".utf8).write(to: URL(fileURLWithPath: begun.lease.stopFile))
            _ = try await store.release(
                ownerID: "client-a",
                leaseID: begun.lease.leaseId,
                outcome: "done",
                summary: "Complete"
            )
            clock.advance(by: 2)
            let snapshot = try await store.status()
            XCTAssertFalse(snapshot.leases.contains { $0.leaseId == begun.lease.leaseId })
            XCTAssertFalse(FileManager.default.fileExists(atPath: begun.lease.stopFile))
        }
    }

    func testAttentionModeIsDenied() async throws {
        try await withStore { store, _ in
            let result = try await store.begin(
                ownerID: "client-a",
                agent: "Agent A",
                task: "Foreground task",
                mode: "attention",
                sessionID: nil,
                implicit: false
            )
            XCTAssertEqual(result.status, "denied")
            XCTAssertEqual(result.lease.status, "denied")
        }
    }

    private func withStore(
        clock: TestClock = TestClock(Date(timeIntervalSince1970: 1_800_000_000)),
        idleExpiry: TimeInterval = 90,
        maximumDuration: TimeInterval = 30 * 60,
        terminalRetention: TimeInterval = 8,
        operation: (ActionDriveLeaseStore, URL) async throws -> Void
    ) async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ActionDriveLeaseStore(
            rootURL: directory,
            idleExpiry: idleExpiry,
            maximumDuration: maximumDuration,
            terminalRetention: terminalRetention,
            publishesPresence: false,
            now: clock.now
        )
        try await operation(store, directory)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("action-drive-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(_ date: Date) {
        self.date = date
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return date
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        date = date.addingTimeInterval(interval)
        lock.unlock()
    }
}
