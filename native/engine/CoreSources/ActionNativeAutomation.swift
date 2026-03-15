import AppKit
@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation

public struct ActionCalculatorButtonSnapshot: Codable, Sendable {
    public let role: String
    public let title: String?
    public let detail: String?
    public let value: String?
    public let identifier: String?

    public init(role: String, title: String?, detail: String?, value: String?, identifier: String?) {
        self.role = role
        self.title = title
        self.detail = detail
        self.value = value
        self.identifier = identifier
    }
}

public struct ActionAccessibilityNodeSnapshot: Codable, Sendable {
    public let role: String
    public let title: String?
    public let detail: String?
    public let value: String?
    public let identifier: String?
    public let depth: Int

    public init(role: String, title: String?, detail: String?, value: String?, identifier: String?, depth: Int) {
        self.role = role
        self.title = title
        self.detail = detail
        self.value = value
        self.identifier = identifier
        self.depth = depth
    }
}

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
    @MainActor
    public static func launchApplication(bundleId: String) throws {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            throw ActionNativeAutomationError.applicationNotRunning(bundleId)
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    public static func activateApplication(bundleId: String) throws {
        let app = try runningApplication(bundleId: bundleId)
        app.activate(options: [.activateAllWindows])
    }

    public static func typeText(_ text: String) throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw ActionNativeAutomationError.accessibilityActionFailed("Unable to create event source")
        }

        for scalar in text.utf16 {
            var unicode = [scalar]
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                throw ActionNativeAutomationError.accessibilityActionFailed("Unable to create keyboard events")
            }

            keyDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unicode)
            keyUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unicode)
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
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

    public static func calculatorButtons() throws -> [ActionCalculatorButtonSnapshot] {
        let window = try firstWindowElement(for: "com.apple.calculator")
        var queue = [window]
        var result: [ActionCalculatorButtonSnapshot] = []

        while let current = queue.first {
            queue.removeFirst()

            let role = axValue(current, attribute: kAXRoleAttribute) as? String ?? ""
            let title = axValue(current, attribute: kAXTitleAttribute) as? String
            let detail = axValue(current, attribute: kAXDescriptionAttribute) as? String
            let value = axValue(current, attribute: kAXValueAttribute) as? String
            let identifier = axValue(current, attribute: kAXIdentifierAttribute) as? String

            if role == kAXButtonRole as String {
                result.append(
                    ActionCalculatorButtonSnapshot(
                        role: role,
                        title: title,
                        detail: detail,
                        value: value,
                        identifier: identifier
                    )
                )
            }

            queue.append(contentsOf: axChildren(of: current))
        }

        return result
    }

    public static func clickCalculatorButton(label: String) throws {
        let window = try firstWindowElement(for: "com.apple.calculator")
        guard let button = findButton(in: window, label: label) else {
            throw ActionNativeAutomationError.accessibilityLookupFailed("Could not find Calculator button \(label)")
        }

        let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
        guard result == .success else {
            throw ActionNativeAutomationError.accessibilityActionFailed("Accessibility press failed for Calculator button \(label): \(result.rawValue)")
        }
    }

    public static func calculatorDisplayValue() throws -> String {
        let window = try firstWindowElement(for: "com.apple.calculator")
        var queue = [window]
        var candidates: [String] = []

        while let current = queue.first {
            queue.removeFirst()

            let role = axValue(current, attribute: kAXRoleAttribute) as? String ?? ""
            let title = sanitizedCalculatorString(stringValue(axValue(current, attribute: kAXTitleAttribute)))
            let value = sanitizedCalculatorString(stringValue(axValue(current, attribute: kAXValueAttribute)))
            let description = sanitizedCalculatorString(stringValue(axValue(current, attribute: kAXDescriptionAttribute)))

            if role != kAXButtonRole as String {
                for candidate in [value, title, description].compactMap({ $0 }) {
                    if isCalculatorDisplayCandidate(candidate, role: role) {
                        candidates.append(candidate)
                    }
                }
            }

            queue.append(contentsOf: axChildren(of: current))
        }

        guard !candidates.isEmpty else {
            throw ActionNativeAutomationError.accessibilityLookupFailed("Could not find Calculator display value")
        }

        if let resolved = candidates.last(where: looksLikeResolvedCalculatorResult(_:)) {
            return resolved
        }

        return candidates.last!
    }

    public static func calculatorAccessibilityNodes() throws -> [ActionAccessibilityNodeSnapshot] {
        let window = try firstWindowElement(for: "com.apple.calculator")
        var queue: [(AXUIElement, Int)] = [(window, 0)]
        var result: [ActionAccessibilityNodeSnapshot] = []

        while let (current, depth) = queue.first {
            queue.removeFirst()

            result.append(
                ActionAccessibilityNodeSnapshot(
                    role: axValue(current, attribute: kAXRoleAttribute) as? String ?? "",
                    title: stringValue(axValue(current, attribute: kAXTitleAttribute)),
                    detail: stringValue(axValue(current, attribute: kAXDescriptionAttribute)),
                    value: stringValue(axValue(current, attribute: kAXValueAttribute)),
                    identifier: stringValue(axValue(current, attribute: kAXIdentifierAttribute)),
                    depth: depth
                )
            )

            queue.append(contentsOf: axChildren(of: current).map { ($0, depth + 1) })
        }

        return result
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

private func axChildren(of element: AXUIElement) -> [AXUIElement] {
    if let direct = axValue(element, attribute: kAXChildrenAttribute) as? [AXUIElement] {
        return direct
    }

    return []
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

private func findButton(in root: AXUIElement, label: String) -> AXUIElement? {
    var queue = [root]

    while let current = queue.first {
        queue.removeFirst()

        let role = axValue(current, attribute: kAXRoleAttribute) as? String
        let title = axValue(current, attribute: kAXTitleAttribute) as? String
        let description = axValue(current, attribute: kAXDescriptionAttribute) as? String
        let value = axValue(current, attribute: kAXValueAttribute) as? String
        let identifier = axValue(current, attribute: kAXIdentifierAttribute) as? String

        if role == kAXButtonRole as String, [title, description, value, identifier].contains(label) {
            return current
        }

        queue.append(contentsOf: axChildren(of: current))
    }

    return nil
}

private func isCalculatorDisplayCandidate(_ string: String) -> Bool {
    isCalculatorDisplayCandidate(string, role: nil)
}

private func isCalculatorDisplayCandidate(_ string: String, role: String?) -> Bool {
    guard !string.isEmpty else { return false }
    let allowed = CharacterSet(charactersIn: "0123456789.,+-−×÷*/=()% ")
    let trimmed = sanitizedCalculatorString(string) ?? ""
    guard trimmed.unicodeScalars.contains(where: CharacterSet.decimalDigits.contains(_:)) else {
        return false
    }
    guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
        return false
    }
    if let role {
        return role == kAXStaticTextRole as String || role == kAXTextFieldRole as String || role == kAXGroupRole as String
    }
    return true
}

private func looksLikeResolvedCalculatorResult(_ string: String) -> Bool {
    guard let first = string.unicodeScalars.first, CharacterSet.decimalDigits.contains(first) || first == "-" else {
        return false
    }
    let disallowed = CharacterSet(charactersIn: "+×÷*/=%()")
    return string.unicodeScalars.allSatisfy { !disallowed.contains($0) }
}

private func stringValue(_ value: AnyObject?) -> String? {
    switch value {
    case let string as String:
        return string
    case let number as NSNumber:
        return number.stringValue
    case let attributed as NSAttributedString:
        return attributed.string
    default:
        return value.map { "\($0)" }
    }
}

private func sanitizedCalculatorString(_ string: String?) -> String? {
    guard let string else {
        return nil
    }

    let filteredScalars = string.unicodeScalars.filter { scalar in
        switch scalar.properties.generalCategory {
        case .format, .control:
            return false
        default:
            return true
        }
    }

    let sanitized = String(String.UnicodeScalarView(filteredScalars)).trimmingCharacters(in: .whitespacesAndNewlines)
    return sanitized.isEmpty ? nil : sanitized
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
