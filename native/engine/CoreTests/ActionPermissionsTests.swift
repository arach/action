@testable import ActionCore
import XCTest

final class ActionPermissionsTests: XCTestCase {
    func testParsePermissionKindAliases() {
        XCTAssertEqual(ActionPermissionKind.parse("ax"), .accessibility)
        XCTAssertEqual(ActionPermissionKind.parse("Accessibility"), .accessibility)
        XCTAssertEqual(ActionPermissionKind.parse("screen_recording"), .screenRecording)
        XCTAssertEqual(ActionPermissionKind.parse("screenshots"), .screenRecording)
        XCTAssertNil(ActionPermissionKind.parse("microphone"))
    }

    func testSettingsURLsPointAtThePrivacyPanes() {
        XCTAssertEqual(
            ActionPermissionKind.accessibility.settingsURL.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
        XCTAssertEqual(
            ActionPermissionKind.screenRecording.settingsURL.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        )
    }

    func testScreenRecordingRequiresRelaunchAndAccessibilityDoesNot() {
        XCTAssertTrue(ActionPermissionKind.screenRecording.requiresRelaunch)
        XCTAssertFalse(ActionPermissionKind.accessibility.requiresRelaunch)
    }

    func testProcessIdentityLabels() {
        XCTAssertEqual(ActionPermissionProcess.host.displayName, "Action")
        XCTAssertEqual(ActionPermissionProcess.agent.displayName, "ActionAgent")
        XCTAssertEqual(ActionPermissionProcess.host.bundleIdentifier, "dev.action.Action")
        XCTAssertEqual(ActionPermissionProcess.agent.bundleIdentifier, "dev.action.ActionAgent")
    }

    func testGrantStateWireValues() {
        XCTAssertEqual(ActionPermissionGrantState.granted.rawValue, "granted")
        XCTAssertEqual(ActionPermissionGrantState.denied.rawValue, "denied")
        XCTAssertEqual(ActionPermissionGrantState.unknown.rawValue, "unknown")
    }
}
