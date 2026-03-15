import AppKit
@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation

public enum ActionNativeAutomationError: LocalizedError {
    case applicationNotRunning(String)
    case accessibilityLookupFailed(String)
    case accessibilityActionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .applicationNotRunning(let bundleId):
            return "Application with bundle identifier \(bundleId) is not running"
        case .accessibilityLookupFailed(let detail):
            return detail
        case .accessibilityActionFailed(let detail):
            return detail
        }
    }
}

public enum ActionNativeAutomation {
    public static func activateApplication(bundleId: String) throws {
        let app = try runningApplication(bundleId: bundleId)
        app.activate(options: [.activateAllWindows])
    }

    public static func setWindowFrame(bundleId: String, rect: CGRect) throws {
        let window = try firstWindowElement(for: bundleId)

        let positionResult = AXUIElementSetAttributeValue(
            window,
            kAXPositionAttribute as CFString,
            pointValue(rect.origin)
        )
        guard positionResult == .success else {
            throw ActionNativeAutomationError.accessibilityActionFailed(
                "Failed to set window position for \(bundleId): \(positionResult.rawValue)"
            )
        }

        let sizeResult = AXUIElementSetAttributeValue(
            window,
            kAXSizeAttribute as CFString,
            sizeValue(rect.size)
        )
        _ = sizeResult
    }

    public static func getWindowFrame(bundleId: String) throws -> CGRect {
        let window = try firstWindowElement(for: bundleId)
        let position = point(from: axValue(window, attribute: kAXPositionAttribute))
        let size = size(from: axValue(window, attribute: kAXSizeAttribute))
        guard let position, let size else {
            throw ActionNativeAutomationError.accessibilityLookupFailed("Failed to read window frame for \(bundleId)")
        }
        return CGRect(origin: position, size: size)
    }

    public static func runningApplication(bundleId: String) throws -> NSRunningApplication {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else {
            throw ActionNativeAutomationError.applicationNotRunning(bundleId)
        }

        return app
    }
}

private func axValue(_ element: AXUIElement, attribute: String) -> AnyObject? {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard error == .success else {
        return nil
    }

    return value
}

private func firstWindowElement(for bundleId: String) throws -> AXUIElement {
    let app = try ActionNativeAutomation.runningApplication(bundleId: bundleId)
    let application = AXUIElementCreateApplication(app.processIdentifier)

    if let windows = axValue(application, attribute: kAXWindowsAttribute) as? [AXUIElement],
       let window = windows.first {
        return window
    }

    throw ActionNativeAutomationError.accessibilityLookupFailed("No accessibility window found for \(bundleId)")
}

private func pointValue(_ point: CGPoint) -> AXValue {
    var point = point
    return AXValueCreate(.cgPoint, &point)!
}

private func sizeValue(_ size: CGSize) -> AXValue {
    var size = size
    return AXValueCreate(.cgSize, &size)!
}

private func point(from value: AnyObject?) -> CGPoint? {
    guard let value else {
        return nil
    }
    guard CFGetTypeID(value) == AXValueGetTypeID() else {
        return nil
    }
    let ax = unsafeDowncast(value, to: AXValue.self)
    guard AXValueGetType(ax) == .cgPoint else {
        return nil
    }
    var point = CGPoint.zero
    guard AXValueGetValue(ax, .cgPoint, &point) else {
        return nil
    }
    return point
}

private func size(from value: AnyObject?) -> CGSize? {
    guard let value else {
        return nil
    }
    guard CFGetTypeID(value) == AXValueGetTypeID() else {
        return nil
    }
    let ax = unsafeDowncast(value, to: AXValue.self)
    guard AXValueGetType(ax) == .cgSize else {
        return nil
    }
    var size = CGSize.zero
    guard AXValueGetValue(ax, .cgSize, &size) else {
        return nil
    }
    return size
}
