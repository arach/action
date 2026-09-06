import AppKit
@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

public enum ActionPermissionKind: String, Codable, CaseIterable, Sendable {
    case accessibility
    case screenRecording = "screen-recording"

    public static func parse(_ raw: String) -> ActionPermissionKind? {
        switch raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        {
        case "accessibility", "ax":
            return .accessibility
        case "screen-recording", "screenrecording", "screen-capture", "screencapture", "screenshots", "screen":
            return .screenRecording
        default:
            return nil
        }
    }

    public var title: String {
        switch self {
        case .accessibility:
            return "Accessibility"
        case .screenRecording:
            return "Screen Recording"
        }
    }

    public var settingsAnchor: String {
        switch self {
        case .accessibility:
            return "Privacy_Accessibility"
        case .screenRecording:
            return "Privacy_ScreenCapture"
        }
    }

    public var settingsURL: URL {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?\(settingsAnchor)")!
    }

    public var iconName: String {
        switch self {
        case .accessibility:
            return "accessibility"
        case .screenRecording:
            return "rectangle.dashed.badge.record"
        }
    }

    /// Screen Recording often does not take effect in the already-running process.
    public var requiresRelaunch: Bool {
        self == .screenRecording
    }
}

public enum ActionPermissionGrantState: String, Codable, Equatable, Sendable {
    case granted
    case denied
    case unknown
}

public enum ActionPermissionProcess: String, Codable, CaseIterable, Sendable {
    case host
    case agent

    public var displayName: String {
        switch self {
        case .host:
            return "Action"
        case .agent:
            return "ActionAgent"
        }
    }

    public var subtitle: String {
        switch self {
        case .host:
            return "Main app"
        case .agent:
            return "Automation helper"
        }
    }

    public var bundleIdentifier: String {
        switch self {
        case .host:
            return "dev.action.Action"
        case .agent:
            return "dev.action.ActionAgent"
        }
    }
}

public func actionCurrentProcessDisplayName() -> String {
    if let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
       !displayName.isEmpty {
        return displayName
    }
    if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String,
       !name.isEmpty {
        return name
    }
    return ProcessInfo.processInfo.processName
}

public func actionCurrentProcessBundleIdentifier() -> String {
    Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
}

public func actionCurrentProcessBundleURL() -> URL {
    Bundle.main.bundleURL
}

public func actionCurrentProcessAccessibilityStatus(prompt: Bool = false) -> ActionPermissionGrantState {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
    return AXIsProcessTrustedWithOptions(options) ? .granted : .denied
}

public func actionCurrentProcessScreenRecordingStatus() -> ActionPermissionGrantState {
    CGPreflightScreenCaptureAccess() ? .granted : .denied
}

/// Registers this process with TCC and, on newer macOS, warms ScreenCaptureKit
/// because `CGRequestScreenCaptureAccess()` often no longer shows a prompt.
@discardableResult
public func actionRequestCurrentProcessScreenRecording() async -> ActionPermissionGrantState {
    if CGPreflightScreenCaptureAccess() {
        return .granted
    }

    let requested = CGRequestScreenCaptureAccess()
    if requested {
        return .granted
    }

    if #available(macOS 15.0, *) {
        await MainActor.run {
            NSApp.activate(ignoringOtherApps: true)
        }
        _ = await actionProbeScreenCaptureShareableContent()
        if CGPreflightScreenCaptureAccess() {
            return .granted
        }

        if #available(macOS 15.2, *) {
            _ = await actionProbeScreenCaptureScreenshot()
            if CGPreflightScreenCaptureAccess() {
                return .granted
            }
        }
    }

    return CGPreflightScreenCaptureAccess() ? .granted : .denied
}

public func actionOpenPrivacySettings(for kind: ActionPermissionKind) {
    let url = kind.settingsURL
    let open: @Sendable () -> Void = {
        if NSWorkspace.shared.open(url) {
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url.absoluteString]
        try? process.run()
    }
    if Thread.isMainThread {
        open()
    } else {
        DispatchQueue.main.async(execute: open)
    }
}

public func actionAgentHelperAppURL() -> URL? {
    let helper = Bundle.main.bundleURL
        .appendingPathComponent("Contents/Helpers/ActionAgent.app", isDirectory: true)
    if FileManager.default.fileExists(atPath: helper.path) {
        return helper
    }
    return nil
}

@available(macOS 15.0, *)
func actionProbeScreenCaptureShareableContent() async -> Bool {
    do {
        _ = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        return true
    } catch {
        return false
    }
}

@available(macOS 15.2, *)
func actionProbeScreenCaptureScreenshot() async -> Bool {
    let rect = CGRect(x: 0, y: 0, width: 1, height: 1)
    return await withCheckedContinuation { continuation in
        SCScreenshotManager.captureImage(in: rect) { _, error in
            continuation.resume(returning: error == nil)
        }
    }
}
