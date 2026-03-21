import AppKit
import ActionCore
@preconcurrency import ApplicationServices
import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ImageIO
@preconcurrency import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers

enum PermissionState: String, Encodable {
    case granted
    case denied
}

struct PermissionSnapshot: Encodable {
    let accessibility: PermissionState
    let screenRecording: PermissionState
    let notes: [String]?
}

struct ActionHostResponse: Codable {
    let status: String
    let outputPath: String?
    let detail: String?
}

enum ActionHostCommand: String {
    case agent
    case launcher
    case webkitSmoke = "webkit-smoke"
    case guidedCalculatorDemo = "guided-calculator-demo"
    case quitApp = "quit-app"
    case status
    case request
    case openAccessibilitySettings = "open-accessibility-settings"
    case openScreenRecordingSettings = "open-screen-recording-settings"
    case currentSurface = "current-surface"
    case panicOverlay = "panic-overlay"
    case panicStop = "panic-stop"
    case stageOverlay = "stage-overlay"
    case prepareNotesNote = "prepare-notes-note"
    case getCaptureWindowFrame = "get-capture-window-frame"
    case composeRoundedScreenshot = "compose-rounded-screenshot"
    case launchApp = "launch-app"
    case recordAppWindow = "record-app-window"
    case recordAppWindowLocal = "record-app-window-local"
    case screenshotAppWindow = "screenshot-app-window"
    case activateApp = "activate-app"
    case typeText = "type-text"
    case pressKey = "press-key"
    case clickPoint = "click-point"
    case drag
    case clickCalculatorButton = "click-calculator-button"
    case inspectCalculatorButtons = "inspect-calculator-buttons"
    case inspectCalculatorUI = "inspect-calculator-ui"
    case inspectAppUI = "inspect-app-ui"
    case getCalculatorDisplay = "get-calculator-display"
    case setWindowFrame = "set-window-frame"
    case getWindowFrame = "get-window-frame"
    case recordRegion = "record-region"
    case recordRegionLocal = "record-region-local"
    case recordingProbe = "recording-probe"
    case screenshotRegion = "screenshot-region"
    case screenshotScreen = "screenshot-screen"
}

enum ActionHostError: LocalizedError {
    case missingOption(String)
    case unsupportedOS(String)
    case windowNotFound(String)
    case unableToEncodeImage
    case missingOutputPath
    case missingStopSignalPath
    case captureFailed(String)
    case appleScriptFailed(String)
    case applicationNotRunning(String)
    case accessibilityLookupFailed(String)
    case accessibilityActionFailed(String)
    case fileNotFound(String)
    case invalidColor(String)

    var errorDescription: String? {
        switch self {
        case .missingOption(let option):
            return "Missing required option \(option)"
        case .unsupportedOS(let detail):
            return detail
        case .windowNotFound(let bundleId):
            return "Could not find an on-screen window for \(bundleId)"
        case .unableToEncodeImage:
            return "Unable to encode screenshot as PNG"
        case .missingOutputPath:
            return "Capture command did not receive an output path"
        case .missingStopSignalPath:
            return "Capture command did not receive a stop signal path"
        case .captureFailed(let detail):
            return detail
        case .appleScriptFailed(let detail):
            return detail
        case .applicationNotRunning(let bundleId):
            return "Application with bundle identifier \(bundleId) is not running"
        case .accessibilityLookupFailed(let detail):
            return detail
        case .accessibilityActionFailed(let detail):
            return detail
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .invalidColor(let color):
            return "Invalid color \(color)"
        }
    }
}

struct CommandOptions {
    let command: ActionHostCommand?
    let options: [String: String]

    init(arguments: [String]) {
        let commandName = arguments.dropFirst().first(where: { !$0.hasPrefix("-psn_") })
        if let commandName {
            self.command = ActionHostCommand(rawValue: commandName) ?? .status
        } else {
            self.command = nil
        }

        var parsed: [String: String] = [:]
        var iterator = arguments.dropFirst(2).makeIterator()
        while let key = iterator.next() {
            guard key.hasPrefix("--"), let value = iterator.next() else {
                continue
            }
            parsed[String(key.dropFirst(2))] = value
        }

        self.options = parsed
    }

    func required(_ key: String) throws -> String {
        guard let value = options[key], !value.isEmpty else {
            throw ActionHostError.missingOption("--\(key)")
        }
        return value
    }

    func double(_ key: String, default defaultValue: Double) -> Double {
        guard let value = options[key], let number = Double(value) else {
            return defaultValue
        }
        return number
    }
}

final class ResponseWriter {
    private let replyFile: String?

    init(replyFile: String?) {
        self.replyFile = replyFile
    }

    func write(_ value: some Encodable) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)

        if let replyFile {
            let url = URL(fileURLWithPath: replyFile)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url)
        } else {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data([0x0a]))
        }
    }
}

final class DebugLogger {
    private let path: String?

    init(path: String?) {
        self.path = path
    }

    func log(_ message: String) {
        guard let path else {
            return
        }

        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        let url = URL(fileURLWithPath: path)

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: path) {
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(line.utf8))
                try handle.close()
            } else {
                try Data(line.utf8).write(to: url)
            }
        } catch {
            FileHandle.standardError.write(Data("ActionHost debug log failed: \(error.localizedDescription)\n".utf8))
        }
    }
}

func accessibilityStatus(prompt: Bool) -> PermissionState {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
    return AXIsProcessTrustedWithOptions(options) ? .granted : .denied
}

func screenRecordingStatus() -> PermissionState {
    CGPreflightScreenCaptureAccess() ? .granted : .denied
}

@discardableResult
func requestScreenRecording() -> PermissionState {
    if CGPreflightScreenCaptureAccess() {
        return .granted
    }

    return CGRequestScreenCaptureAccess() ? .granted : .denied
}

func snapshot(promptAccessibility: Bool, requestScreenRecordingPermission: Bool) -> PermissionSnapshot {
    let accessibility = accessibilityStatus(prompt: promptAccessibility)
    let screenRecording = requestScreenRecordingPermission
        ? requestScreenRecording()
        : screenRecordingStatus()
    let bundleId = Bundle.main.bundleIdentifier ?? "unknown"
    let bundlePath = Bundle.main.bundlePath

    return PermissionSnapshot(
        accessibility: accessibility,
        screenRecording: screenRecording,
        notes: [
            "bundleId=\(bundleId)",
            "bundlePath=\(bundlePath)"
        ]
    )
}

func openSettingsPane(anchor: String) {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else {
        return
    }

    NSWorkspace.shared.open(url)
}

func runningApplication(bundleId: String) throws -> NSRunningApplication {
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else {
        throw ActionHostError.applicationNotRunning(bundleId)
    }

    return app
}

func activateApplication(bundleId: String) throws {
    let app = try runningApplication(bundleId: bundleId)
    app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
}

func runAppleScript(_ source: String) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", source]

    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    try process.run()
    process.waitUntilExit()

    let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if process.terminationStatus == 0 {
        return output
    }

    let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown AppleScript error"
    throw ActionHostError.appleScriptFailed(error)
}

func prepareNotesNote() throws -> String {
    let script = """
    tell application "Notes"
      activate
      set targetFolder to default folder of default account
      set newNote to make new note at targetFolder with properties {body:"<div><br></div>"}
      show newNote
      delay 0.35
      return name of newNote
    end tell
    """

    let noteName = try runAppleScript(script)
    try focusNotesEditor()
    return noteName
}

let keyCodes: [String: UInt16] = [
    "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07,
    "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10,
    "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "=": 0x18,
    "9": 0x19, "7": 0x1A, "-": 0x1B, "8": 0x1C, "0": 0x1D, "]": 0x1E, "o": 0x1F, "u": 0x20,
    "[": 0x21, "i": 0x22, "p": 0x23, "l": 0x25, "j": 0x26, "'": 0x27, "k": 0x28, ";": 0x29,
    "\\": 0x2A, ",": 0x2B, "/": 0x2C, "n": 0x2D, "m": 0x2E, ".": 0x2F, "`": 0x32,
    "return": 0x24, "enter": 0x24, "tab": 0x30, "space": 0x31, "delete": 0x33, "backspace": 0x33,
    "escape": 0x35, "esc": 0x35,
    "up": 0x7E, "down": 0x7D, "left": 0x7B, "right": 0x7C,
]

let keySymbols: [String: String] = [
    "cmd": "⌘", "command": "⌘",
    "shift": "⇧",
    "opt": "⌥", "option": "⌥", "alt": "⌥",
    "ctrl": "⌃", "control": "⌃",
    "fn": "fn",
    "return": "↵", "enter": "↵",
    "tab": "⇥",
    "space": "␣",
    "delete": "⌫", "backspace": "⌫",
    "escape": "⎋", "esc": "⎋",
    "up": "↑", "down": "↓", "left": "←", "right": "→",
]

func keyOverlayLabel(_ key: String) -> String {
    keySymbols[key.lowercased()] ?? key.uppercased()
}

func modifierFlags(for modifiers: [String]) -> CGEventFlags {
    modifiers.reduce(into: CGEventFlags()) { result, modifier in
        switch modifier.lowercased() {
        case "cmd", "command":
            result.insert(.maskCommand)
        case "shift":
            result.insert(.maskShift)
        case "opt", "option", "alt":
            result.insert(.maskAlternate)
        case "ctrl", "control":
            result.insert(.maskControl)
        default:
            break
        }
    }
}

func postKeyPress(_ key: String, modifiers: [String] = []) throws {
    guard let source = CGEventSource(stateID: .hidSystemState) else {
        throw ActionHostError.accessibilityActionFailed("Unable to create event source")
    }

    let normalized = key.lowercased()
    guard let keyCode = keyCodes[normalized] else {
        try postText(key, delayMs: nil)
        return
    }

    let flags = modifierFlags(for: modifiers)
    guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
          let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
        throw ActionHostError.accessibilityActionFailed("Unable to create keyboard events")
    }

    keyDown.flags = flags
    keyUp.flags = flags
    keyDown.post(tap: .cghidEventTap)
    usleep(50000)
    keyUp.post(tap: .cghidEventTap)
}

func clickPoint(_ point: CGPoint) throws {
    CGWarpMouseCursorPosition(point)
    usleep(10000)

    guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
          let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
        throw ActionHostError.accessibilityActionFailed("Unable to create mouse events")
    }

    down.post(tap: .cghidEventTap)
    usleep(30000)
    up.post(tap: .cghidEventTap)
}

func postText(_ text: String, delayMs: Int?) throws {
    guard let source = CGEventSource(stateID: .hidSystemState) else {
        throw ActionHostError.accessibilityActionFailed("Unable to create event source")
    }

    for scalar in text.utf16 {
        var unicode = [scalar]
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            throw ActionHostError.accessibilityActionFailed("Unable to create keyboard events")
        }

        keyDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unicode)
        keyUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unicode)
        keyDown.post(tap: .cghidEventTap)
        if let delayMs, delayMs > 0 {
            usleep(useconds_t(delayMs * 500))
        }
        keyUp.post(tap: .cghidEventTap)
        if let delayMs, delayMs > 0 {
            usleep(useconds_t(delayMs * 500))
        }
    }
}

func axValue(_ element: AXUIElement, attribute: String) -> AnyObject? {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard error == .success else {
        return nil
    }

    return value
}

func axChildren(of element: AXUIElement) -> [AXUIElement] {
    if let direct = axValue(element, attribute: kAXChildrenAttribute) as? [AXUIElement] {
        return direct
    }

    return []
}

func firstWindowElement(for bundleId: String) throws -> AXUIElement {
    let app = try runningApplication(bundleId: bundleId)
    let application = AXUIElementCreateApplication(app.processIdentifier)

    if let windows = axValue(application, attribute: kAXWindowsAttribute) as? [AXUIElement],
       let window = windows.first {
        return window
    }

    throw ActionHostError.accessibilityLookupFailed("No accessibility window found for \(bundleId)")
}

func pointValue(_ point: CGPoint) -> AXValue {
    var point = point
    return AXValueCreate(.cgPoint, &point)!
}

func sizeValue(_ size: CGSize) -> AXValue {
    var size = size
    return AXValueCreate(.cgSize, &size)!
}

func point(from value: AnyObject?) -> CGPoint? {
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

func size(from value: AnyObject?) -> CGSize? {
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

func setWindowFrame(bundleId: String, rect: CGRect) throws {
    let window = try firstWindowElement(for: bundleId)

    let positionResult = AXUIElementSetAttributeValue(
        window,
        kAXPositionAttribute as CFString,
        pointValue(rect.origin)
    )
    guard positionResult == .success else {
        throw ActionHostError.accessibilityActionFailed("Failed to set window position for \(bundleId): \(positionResult.rawValue)")
    }

    let sizeResult = AXUIElementSetAttributeValue(
        window,
        kAXSizeAttribute as CFString,
        sizeValue(rect.size)
    )
    // Some native apps expose a fixed or constrained window size. Positioning is
    // still useful for viewport capture, so size failure is best-effort only.
    _ = sizeResult
}

struct WindowFrameResponse: Encodable {
    let status: String
    let bundleId: String
    let frame: OverlayBounds
}

struct CurrentSurfaceResponse: Encodable {
    let status: String
    let bundleId: String
    let appName: String
    let frame: OverlayBounds?
}

func overlayBounds(from rect: CGRect) -> OverlayBounds {
    OverlayBounds(
        x: rect.origin.x,
        y: rect.origin.y,
        width: rect.size.width,
        height: rect.size.height
    )
}

func rect(from windowInfo: [String: Any]) -> CGRect? {
    guard let bounds = windowInfo[kCGWindowBounds as String] as? [String: Any] else {
        return nil
    }

    var rect = CGRect.zero
    guard CGRectMakeWithDictionaryRepresentation(bounds as CFDictionary, &rect) else {
        return nil
    }

    return rect
}

func currentSurface() throws -> CurrentSurfaceResponse {
    let selfBundleId = Bundle.main.bundleIdentifier
    let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []

    for windowInfo in windowList {
        let layer = windowInfo[kCGWindowLayer as String] as? Int ?? 0
        guard layer == 0 else {
            continue
        }

        let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t ?? 0
        guard ownerPID > 0,
              let app = NSRunningApplication(processIdentifier: ownerPID),
              let bundleId = app.bundleIdentifier,
              bundleId != selfBundleId else {
            continue
        }

        let appName = app.localizedName ?? bundleId
        let frame = (try? getWindowFrame(bundleId: bundleId))
            ?? rect(from: windowInfo)

        return CurrentSurfaceResponse(
            status: "current-surface",
            bundleId: bundleId,
            appName: appName,
            frame: frame.map(overlayBounds(from:))
        )
    }

    throw ActionHostError.windowNotFound("current-surface")
}

func getWindowFrame(bundleId: String) throws -> CGRect {
    let window = try firstWindowElement(for: bundleId)
    let position = point(from: axValue(window, attribute: kAXPositionAttribute))
    let size = size(from: axValue(window, attribute: kAXSizeAttribute))
    guard let position, let size else {
        throw ActionHostError.accessibilityLookupFailed("Failed to read window frame for \(bundleId)")
    }
    return CGRect(origin: position, size: size)
}

func findButton(in root: AXUIElement, label: String) -> AXUIElement? {
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

func matchesText(_ candidate: String?, expected: String) -> Bool {
    candidate?.trimmingCharacters(in: .whitespacesAndNewlines) == expected
}

func findElement(
    in root: AXUIElement,
    where predicate: (AXUIElement) -> Bool
) -> AXUIElement? {
    var queue = [root]

    while let current = queue.first {
        queue.removeFirst()

        if predicate(current) {
            return current
        }

        queue.append(contentsOf: axChildren(of: current))
    }

    return nil
}

func focusNotesEditor() throws {
    let window = try firstWindowElement(for: "com.apple.Notes")
    guard let editor = findElement(in: window, where: { element in
        let role = axValue(element, attribute: kAXRoleAttribute) as? String
        let identifier = axValue(element, attribute: kAXIdentifierAttribute) as? String
        let title = axValue(element, attribute: kAXTitleAttribute) as? String
        return role == kAXTextAreaRole as String
            && (matchesText(identifier, expected: "Note Body Text View")
                || matchesText(title, expected: "Note Body Text View"))
    }) else {
        throw ActionHostError.accessibilityLookupFailed("Could not find the Notes body text view")
    }

    let focusResult = AXUIElementSetAttributeValue(
        editor,
        kAXFocusedAttribute as CFString,
        kCFBooleanTrue
    )
    guard focusResult == .success else {
        throw ActionHostError.accessibilityActionFailed("Failed to focus Notes editor: \(focusResult.rawValue)")
    }
}

struct CalculatorButtonSnapshot: Encodable {
    let role: String
    let title: String?
    let detail: String?
    let value: String?
    let identifier: String?
}

func calculatorButtons() throws -> [CalculatorButtonSnapshot] {
    let window = try firstWindowElement(for: "com.apple.calculator")
    var queue = [window]
    var result: [CalculatorButtonSnapshot] = []

    while let current = queue.first {
        queue.removeFirst()

        let role = axValue(current, attribute: kAXRoleAttribute) as? String ?? ""
        let title = axValue(current, attribute: kAXTitleAttribute) as? String
        let detail = axValue(current, attribute: kAXDescriptionAttribute) as? String
        let value = axValue(current, attribute: kAXValueAttribute) as? String
        let identifier = axValue(current, attribute: kAXIdentifierAttribute) as? String

        if role == kAXButtonRole as String {
            result.append(
                CalculatorButtonSnapshot(
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

func clickCalculatorButton(label: String) throws {
    let window = try firstWindowElement(for: "com.apple.calculator")
    guard let button = findButton(in: window, label: label) else {
        throw ActionHostError.accessibilityLookupFailed("Could not find Calculator button \(label)")
    }

    let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
    guard result == .success else {
        throw ActionHostError.accessibilityActionFailed("Accessibility press failed for Calculator button \(label): \(result.rawValue)")
    }
}

func shareableContent() async throws -> SCShareableContent {
    guard screenRecordingStatus() == .granted else {
        throw ActionHostError.unsupportedOS("Screen Recording permission has not been granted yet.")
    }

    return try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
}

struct WindowSelection {
    let content: SCShareableContent
    let window: SCWindow
    let display: SCDisplay
}

struct RegionSelection {
    let display: SCDisplay
    let sourceRect: CGRect
}

func displayContaining(window: SCWindow, displays: [SCDisplay]) -> SCDisplay? {
    let center = CGPoint(
        x: window.frame.midX,
        y: window.frame.midY
    )

    return displays.first(where: { $0.frame.contains(center) }) ?? displays.first
}

func regionSelection(for rect: CGRect, displays: [SCDisplay]) -> RegionSelection? {
    let center = CGPoint(x: rect.midX, y: rect.midY)
    guard let display = displays.first(where: { $0.frame.contains(center) }) ?? displays.first else {
        return nil
    }

    let localRect = CGRect(
        x: rect.origin.x - display.frame.origin.x,
        y: rect.origin.y - display.frame.origin.y,
        width: rect.width,
        height: rect.height
    )

    return RegionSelection(display: display, sourceRect: localRect)
}

func rectArea(_ rect: CGRect) -> CGFloat {
    max(rect.width, 0) * max(rect.height, 0)
}

func overlapArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
    let intersection = lhs.intersection(rhs)
    if intersection.isNull || intersection.isEmpty {
        return 0
    }
    return rectArea(intersection)
}

func bestWindowSelection(for bundleId: String) async throws -> WindowSelection {
    let content = try await shareableContent()

    let candidates = content.windows.filter { window in
        window.owningApplication?.bundleIdentifier == bundleId && window.isOnScreen && window.windowLayer == 0
    }

    let sizableCandidates = candidates.filter { window in
        window.frame.width >= 400 && window.frame.height >= 300
    }
    let titledCandidates = sizableCandidates.filter { window in
        let title = window.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !title.isEmpty
    }
    let primaryCandidates = titledCandidates.isEmpty
        ? (sizableCandidates.isEmpty ? candidates : sizableCandidates)
        : titledCandidates

    let selectedWindow: SCWindow
    if let expectedFrame = try? getWindowFrame(bundleId: bundleId),
       let overlapping = primaryCandidates.max(by: { lhs, rhs in
           overlapArea(lhs.frame, expectedFrame) < overlapArea(rhs.frame, expectedFrame)
       }),
       overlapArea(overlapping.frame, expectedFrame) > 0 {
        selectedWindow = overlapping
    } else if let active = primaryCandidates.first(where: \.isActive) {
        selectedWindow = active
    } else if let largest = primaryCandidates.max(by: { lhs, rhs in
        rectArea(lhs.frame) < rectArea(rhs.frame)
    }) {
        selectedWindow = largest
    } else {
        throw ActionHostError.windowNotFound(bundleId)
    }

    guard let display = displayContaining(window: selectedWindow, displays: content.displays) else {
        throw ActionHostError.windowNotFound(bundleId)
    }

    return WindowSelection(content: content, window: selectedWindow, display: display)
}

func getCaptureWindowFrame(bundleId: String) async throws -> CGRect {
    let selection = try await bestWindowSelection(for: bundleId)
    return selection.window.frame
}

func pngData(from image: CGImage) -> Data? {
    let bitmap = NSBitmapImageRep(cgImage: image)
    return bitmap.representation(using: .png, properties: [:])
}

func colorFromHex(_ hex: String) throws -> NSColor {
    let normalized = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
    guard normalized.count == 6 || normalized.count == 8,
          let value = UInt64(normalized, radix: 16) else {
        throw ActionHostError.invalidColor(hex)
    }

    let hasAlpha = normalized.count == 8
    let red = CGFloat((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
    let green = CGFloat((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
    let blue = CGFloat((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
    let alpha = hasAlpha ? CGFloat(value & 0xFF) / 255 : 1
    return NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
}

func composeRoundedScreenshot(
    inputPath: String,
    outputPath: String,
    radius: CGFloat,
    backgroundHex: String
) throws {
    let inputURL = URL(fileURLWithPath: inputPath)
    guard let sourceImage = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
          let source = CGImageSourceCreateImageAtIndex(sourceImage, 0, nil) else {
        throw ActionHostError.captureFailed("Unable to read image at \(inputPath)")
    }

    let outputURL = URL(fileURLWithPath: outputPath)
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )

    let width = source.width
    let height = source.height
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
              data: nil,
              width: width,
              height: height,
              bitsPerComponent: 8,
              bytesPerRow: 0,
              space: colorSpace,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else {
        throw ActionHostError.unableToEncodeImage
    }

    let backgroundColor = try colorFromHex(backgroundHex).usingColorSpace(.sRGB) ?? NSColor.white
    context.setFillColor(backgroundColor.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    let drawRect = CGRect(x: 0, y: 0, width: width, height: height)
    let clipPath = CGPath(
        roundedRect: drawRect,
        cornerWidth: radius,
        cornerHeight: radius,
        transform: nil
    )
    context.addPath(clipPath)
    context.clip()
    context.draw(source, in: drawRect)

    guard let output = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(
              outputURL as CFURL,
              UTType.png.identifier as CFString,
              1,
              nil
          ) else {
        throw ActionHostError.unableToEncodeImage
    }

    CGImageDestinationAddImage(destination, output, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw ActionHostError.unableToEncodeImage
    }
}

@available(macOS 15.0, *)
final class WindowRecorder: NSObject, SCRecordingOutputDelegate, SCStreamDelegate {
    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private let writer: ResponseWriter
    private let logger: DebugLogger
    private var finishedSignalPath: String?
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var finishContinuation: CheckedContinuation<Void, Error>?
    private var recordingStarted = false
    private var recordingFinished = false
    private var recordingError: Error?

    init(writer: ResponseWriter, logger: DebugLogger) {
        self.writer = writer
        self.logger = logger
    }

    func recordRegion(rect: CGRect, outputPath: String, stopSignalPath: String?) async throws {
        try await recordRegion(
            rect: rect,
            outputPath: outputPath,
            stopSignalPath: stopSignalPath,
            finishedSignalPath: nil,
            fps: 15,
            scale: 1
        )
    }

    func recordRegion(rect: CGRect, outputPath: String, stopSignalPath: String?, finishedSignalPath: String?, fps: Double, scale: Double) async throws {
        logger.log("record-region: begin rect=\(rect) outputPath=\(outputPath)")
        self.finishedSignalPath = finishedSignalPath
        let outputURL = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let content = try await shareableContent()
        guard let selection = regionSelection(for: rect, displays: content.displays) else {
            throw ActionHostError.unsupportedOS("Could not resolve a display for rect \(rect)")
        }

        logger.log("record-region: display frame=\(selection.display.frame) sourceRect=\(selection.sourceRect)")
        let filter = SCContentFilter(display: selection.display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = max(Int(selection.sourceRect.width * scale), 1)
        configuration.height = max(Int(selection.sourceRect.height * scale), 1)
        configuration.minimumFrameInterval = CMTime(seconds: 1 / max(fps, 1), preferredTimescale: 600)
        configuration.sourceRect = selection.sourceRect
        logger.log("record-region: fps=\(fps) scale=\(scale) output=\(configuration.width)x\(configuration.height)")

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        let recordingConfiguration = SCRecordingOutputConfiguration()
        recordingConfiguration.outputURL = outputURL
        recordingConfiguration.outputFileType = .mov
        recordingConfiguration.videoCodecType = .h264

        let recordingOutput = SCRecordingOutput(configuration: recordingConfiguration, delegate: self)
        try stream.addRecordingOutput(recordingOutput)

        self.stream = stream
        self.recordingOutput = recordingOutput

        try await stream.startCapture()
        try await waitForRecordingStart()
        try writer.write(ActionHostResponse(status: "recording", outputPath: outputPath, detail: nil))

        if let stopSignalPath {
            try waitForStopSignal(at: stopSignalPath)
        } else {
            _ = try FileHandle.standardInput.readToEnd()
        }

        try await stream.stopCapture()
        try await waitForRecordingFinish()
        try writer.write(ActionHostResponse(status: "finished", outputPath: outputPath, detail: nil))
        try writeSignalFile(path: finishedSignalPath, contents: "finished\n")
    }

    func recordAppWindow(bundleId: String, outputPath: String) async throws {
        try await recordAppWindow(
            bundleId: bundleId,
            outputPath: outputPath,
            stopSignalPath: nil,
            finishedSignalPath: nil
        )
    }

    func recordAppWindow(bundleId: String, outputPath: String, stopSignalPath: String?, finishedSignalPath: String?) async throws {
        logger.log("record: begin bundleId=\(bundleId) outputPath=\(outputPath)")
        self.finishedSignalPath = finishedSignalPath
        let outputURL = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        logger.log("record: finding window")
        let selection = try await bestWindowSelection(for: bundleId)
        let window = selection.window
        logger.log("record: window id=\(window.windowID) frame=\(window.frame)")
        logger.log("record: creating content filter")
        let filter = SCContentFilter(display: selection.display, including: [window])
        logger.log("record: creating stream configuration")
        let configuration = SCStreamConfiguration()
        configuration.width = max(Int(window.frame.width), 1)
        configuration.height = max(Int(window.frame.height), 1)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.sourceRect = window.frame
        logger.log("record: configuration width=\(configuration.width) height=\(configuration.height)")

        logger.log("record: creating stream")
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        let recordingConfiguration = SCRecordingOutputConfiguration()
        recordingConfiguration.outputURL = outputURL
        recordingConfiguration.outputFileType = .mov
        recordingConfiguration.videoCodecType = .h264

        logger.log("record: creating recording output")
        let recordingOutput = SCRecordingOutput(configuration: recordingConfiguration, delegate: self)
        logger.log("record: adding recording output")
        try stream.addRecordingOutput(recordingOutput)

        self.stream = stream
        self.recordingOutput = recordingOutput

        logger.log("record: starting capture")
        try await stream.startCapture()
        logger.log("record: capture started")
        try await waitForRecordingStart()
        try writer.write(ActionHostResponse(status: "recording", outputPath: outputPath, detail: nil))
        logger.log("record: wrote recording reply")

        if let stopSignalPath {
            logger.log("record: waiting for stop file \(stopSignalPath)")
            try waitForStopSignal(at: stopSignalPath)
        } else {
            logger.log("record: waiting for stdin EOF")
            _ = try FileHandle.standardInput.readToEnd()
        }

        logger.log("record: stopping capture")
        try await stream.stopCapture()
        logger.log("record: capture stopped")
        try await waitForRecordingFinish()
        try writer.write(ActionHostResponse(status: "finished", outputPath: outputPath, detail: nil))
        try writeSignalFile(path: finishedSignalPath, contents: "finished\n")
        logger.log("record: wrote finished reply")
    }

    private func waitForStopSignal(at path: String) throws {
        let stopURL = URL(fileURLWithPath: path)
        while !FileManager.default.fileExists(atPath: stopURL.path) {
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    private func waitForRecordingStart() async throws {
        if let recordingError {
            throw recordingError
        }

        if recordingStarted {
            return
        }

        try await withCheckedThrowingContinuation { continuation in
            startContinuation = continuation
        }
    }

    private func waitForRecordingFinish() async throws {
        if let recordingError {
            throw recordingError
        }

        if recordingFinished {
            return
        }

        try await withCheckedThrowingContinuation { continuation in
            finishContinuation = continuation
        }
    }

    private func writeSignalFile(path: String?, contents: String) throws {
        guard let path else {
            return
        }

        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url)
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        recordingError = error
        logger.log("record: recordingOutput failed \(error.localizedDescription)")
        try? writeSignalFile(path: finishedSignalPath, contents: "error:\(error.localizedDescription)\n")
        startContinuation?.resume(throwing: error)
        startContinuation = nil
        finishContinuation?.resume(throwing: error)
        finishContinuation = nil
        FileHandle.standardError.write(Data("ActionHost recording failed: \(error.localizedDescription)\n".utf8))
    }

    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        logger.log("record: recording output started")
        recordingStarted = true
        startContinuation?.resume()
        startContinuation = nil
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        logger.log("record: recording output finished")
        recordingFinished = true
        finishContinuation?.resume()
        finishContinuation = nil
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        recordingError = error
        logger.log("record: stream stopped with error \(error.localizedDescription)")
        try? writeSignalFile(path: finishedSignalPath, contents: "error:\(error.localizedDescription)\n")
        startContinuation?.resume(throwing: error)
        startContinuation = nil
        finishContinuation?.resume(throwing: error)
        finishContinuation = nil
        FileHandle.standardError.write(Data("ActionHost stream stopped: \(error.localizedDescription)\n".utf8))
    }
}

func captureAppWindowScreenshot(bundleId: String, outputPath: String, writer: ResponseWriter) async throws {
    let outputURL = URL(fileURLWithPath: outputPath)
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )

    let selection = try await bestWindowSelection(for: bundleId)
    let window = selection.window
    guard let image = CGWindowListCreateImage(
        .null,
        .optionIncludingWindow,
        CGWindowID(window.windowID),
        [.bestResolution, .boundsIgnoreFraming]
    ) else {
        throw ActionHostError.unableToEncodeImage
    }

    guard let data = pngData(from: image) else {
        throw ActionHostError.unableToEncodeImage
    }

    try data.write(to: outputURL)
    try writer.write(ActionHostResponse(status: "screenshot", outputPath: outputPath, detail: nil))
}

func captureRegionScreenshot(rect: CGRect, outputPath: String, writer: ResponseWriter) async throws {
    let outputURL = URL(fileURLWithPath: outputPath)
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )

    let content = try await shareableContent()
    guard let selection = regionSelection(for: rect, displays: content.displays) else {
        throw ActionHostError.unsupportedOS("Could not resolve a display for rect \(rect)")
    }

    guard let image = CGDisplayCreateImage(selection.display.displayID, rect: selection.sourceRect) else {
        throw ActionHostError.unableToEncodeImage
    }

    guard let data = pngData(from: image) else {
        throw ActionHostError.unableToEncodeImage
    }

    try data.write(to: outputURL)
    try writer.write(ActionHostResponse(status: "screenshot", outputPath: outputPath, detail: nil))
}

func captureScreenScreenshot(outputPath: String, writer: ResponseWriter) async throws {
    let outputURL = URL(fileURLWithPath: outputPath)
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )

    guard let image = CGDisplayCreateImage(CGMainDisplayID()) else {
        throw ActionHostError.unableToEncodeImage
    }

    guard let data = pngData(from: image) else {
        throw ActionHostError.unableToEncodeImage
    }

    try data.write(to: outputURL)
    try writer.write(ActionHostResponse(status: "screenshot", outputPath: outputPath, detail: "main-display"))
}

struct OverlayBounds: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct OverlayViewport: Decodable {
    let id: String
    let bounds: OverlayBounds
    let surfaceId: String?
    let dimming: String
}

struct OverlayInputState: Decodable {
    let kind: String
    let keys: [String]?
    let text: String?
    let style: String?
}

struct StageOverlayState: Decodable {
    let sessionId: String
    let phase: String
    let backdrop: String
    let viewport: OverlayViewport?
    let targetApp: String?
    let summary: String
    let detail: String?
    let countdownRemaining: Int?
    let elapsedMs: Double?
    let isRecording: Bool
    let stepCurrent: Int?
    let stepTotal: Int?
    let stepLabel: String?
    let inputOverlay: OverlayInputState?
    let recentLogs: [String]?
}

final class StageOverlayView: NSView {
    var state: StageOverlayState? {
        didSet {
            needsDisplay = true
        }
    }

    let screenFrame: CGRect

    init(frame frameRect: NSRect, screenFrame: CGRect) {
        self.screenFrame = screenFrame
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let state else {
            return
        }

        guard let viewport = viewportRect(for: state) else {
            return
        }

        drawBackdrop(state: state, viewport: viewport)
        drawViewportFrame(state: state, viewport: viewport)

        if state.phase == "countdown", let countdown = state.countdownRemaining {
            drawCountdown(String(countdown), viewport: viewport)
        }

        drawInputOverlay(state: state, viewport: viewport)
    }

    private func viewportRect(for state: StageOverlayState) -> CGRect? {
        guard let bounds = state.viewport?.bounds else {
            return nil
        }

        return CGRect(
            x: bounds.x - screenFrame.minX,
            y: bounds.y - screenFrame.minY,
            width: bounds.width,
            height: bounds.height
        )
    }

    private func drawBackdrop(state: StageOverlayState, viewport: CGRect) {
        let outer = NSBezierPath(rect: bounds)
        let cutout = NSBezierPath(
            roundedRect: viewport,
            xRadius: 8,
            yRadius: 8
        )
        outer.append(cutout)
        outer.windingRule = .evenOdd
        outer.addClip()

        let gradient: NSGradient
        switch state.backdrop {
        case "matte":
            gradient = NSGradient(colors: [
                NSColor(calibratedRed: 0.91, green: 0.93, blue: 0.96, alpha: 0.98),
                NSColor(calibratedRed: 0.89, green: 0.92, blue: 0.95, alpha: 0.98),
            ])!
        case "gradient":
            gradient = NSGradient(colors: [
                NSColor(calibratedWhite: 0.18, alpha: 0.64),
                NSColor(calibratedWhite: 0.05, alpha: 0.88),
            ])!
        case "spotlight":
            gradient = NSGradient(colors: [
                NSColor(calibratedWhite: 0.16, alpha: 0.18),
                NSColor(calibratedWhite: 0.04, alpha: 0.78),
            ])!
        default:
            gradient = NSGradient(colors: [
                NSColor(calibratedWhite: 0.14, alpha: 0.56),
                NSColor(calibratedWhite: 0.04, alpha: 0.86),
            ])!
        }

        gradient.draw(in: bounds, angle: 300)

        let veilAlpha: CGFloat = state.phase == "countdown" || state.isRecording ? 0.62 : 0.42
        NSColor(calibratedWhite: 0.03, alpha: veilAlpha).setFill()
        bounds.fill()

        drawOrb(
            rect: CGRect(x: 42, y: bounds.height - 220, width: 280, height: 280),
            color: NSColor(calibratedWhite: 1.0, alpha: 0.08)
        )
        drawOrb(
            rect: CGRect(x: bounds.width - 260, y: 42, width: 220, height: 220),
            color: NSColor(calibratedWhite: 1.0, alpha: 0.05)
        )
    }

    private func drawOrb(rect: CGRect, color: NSColor) {
        guard let gradient = NSGradient(colorsAndLocations:
            (color, 0.0),
            (color.withAlphaComponent(0), 1.0)
        ) else {
            return
        }

        let path = NSBezierPath(ovalIn: rect)
        gradient.draw(in: path, relativeCenterPosition: NSZeroPoint)
    }

    private func drawViewportFrame(state: StageOverlayState, viewport: CGRect) {
        let outer = viewport
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 30
        shadow.shadowOffset = .zero
        shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.4)
        shadow.set()

        let glowPath = NSBezierPath(roundedRect: outer, xRadius: 8, yRadius: 8)
        let accent = state.isRecording
            ? NSColor(calibratedWhite: 0.9, alpha: 0.82)
            : NSColor(calibratedWhite: 1, alpha: 0.22)
        accent.setStroke()
        glowPath.lineWidth = state.isRecording ? 2 : 1.5
        glowPath.stroke()

        NSGraphicsContext.saveGraphicsState()
        let innerPath = NSBezierPath(roundedRect: viewport, xRadius: 8, yRadius: 8)
        NSColor(calibratedWhite: 1, alpha: 0.12).setStroke()
        innerPath.lineWidth = 1
        innerPath.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawCountdown(_ text: String, viewport: CGRect) {
        let glow = NSShadow()
        glow.shadowBlurRadius = 36
        glow.shadowOffset = .zero
        glow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.6)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: min(viewport.width, viewport.height) * 0.28, weight: .bold),
            .foregroundColor: NSColor(calibratedWhite: 0.96, alpha: 0.95),
            .shadow: glow,
        ]
        let size = text.size(withAttributes: attrs)
        let rect = CGRect(
            x: viewport.midX - size.width / 2,
            y: viewport.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        text.draw(in: rect, withAttributes: attrs)
    }

    private func drawInputOverlay(state: StageOverlayState, viewport: CGRect) {
        guard let overlay = state.inputOverlay else {
            return
        }

        switch overlay.kind {
        case "keys":
            drawKeyOverlay(keys: overlay.keys ?? [], viewport: viewport)
        case "typing":
            drawTypingOverlay(text: overlay.text ?? "", style: overlay.style ?? "default", viewport: viewport)
        default:
            break
        }
    }

    private func drawKeyOverlay(keys: [String], viewport: CGRect) {
        guard !keys.isEmpty else {
            return
        }

        let labels = keys.map(keyOverlayLabel)
        let fonts = labels.map { label in
            NSFont.systemFont(ofSize: ["⌘", "⇧", "⌥", "⌃", "fn"].contains(label) ? 28 : 23, weight: .medium)
        }
        let sizes = zip(labels, fonts).map { label, font in
            (label as NSString).size(withAttributes: [.font: font])
        }
        let keyWidths = zip(labels, sizes).map { label, size in
            max(size.width + 26, ["⌘", "⇧", "⌥", "⌃", "fn"].contains(label) ? 54 : 46)
        }

        let spacing: CGFloat = 8
        let totalWidth = keyWidths.reduce(0, +) + (CGFloat(keyWidths.count - 1) * spacing)
        let panelRect = CGRect(
            x: viewport.midX - totalWidth / 2 - 18,
            y: viewport.minY + 24,
            width: totalWidth + 36,
            height: 72
        )

        let panelShadow = NSShadow()
        panelShadow.shadowBlurRadius = 20
        panelShadow.shadowOffset = .zero
        panelShadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.24)
        panelShadow.set()

        let panelPath = NSBezierPath(roundedRect: panelRect, xRadius: 20, yRadius: 20)
        NSColor(calibratedWhite: 0.08, alpha: 0.76).setFill()
        panelPath.fill()
        NSColor(calibratedWhite: 1, alpha: 0.10).setStroke()
        panelPath.lineWidth = 1
        panelPath.stroke()

        var cursorX = panelRect.minX + 18
        for (index, label) in labels.enumerated() {
            let width = keyWidths[index]
            let keyRect = CGRect(x: cursorX, y: panelRect.minY + 11, width: width, height: 50)
            drawKeyCap(label: label, rect: keyRect, font: fonts[index])
            cursorX += width + spacing
        }
    }

    private func drawKeyCap(label: String, rect: CGRect, font: NSFont) {
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 8
        shadow.shadowOffset = CGSize(width: 0, height: -2)
        shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.24)
        shadow.set()

        let capRect = rect.insetBy(dx: 2, dy: 2)
        let capPath = NSBezierPath(roundedRect: capRect, xRadius: 10, yRadius: 10)
        NSColor(calibratedWhite: 0.15, alpha: 0.98).setFill()
        capPath.fill()

        let topRect = CGRect(x: capRect.minX, y: capRect.minY + capRect.height * 0.42, width: capRect.width, height: capRect.height * 0.58)
        let topPath = NSBezierPath(roundedRect: topRect, xRadius: 10, yRadius: 10)
        NSColor(calibratedWhite: 0.24, alpha: 1.0).setFill()
        topPath.fill()

        NSColor(calibratedWhite: 0.08, alpha: 1.0).setStroke()
        capPath.lineWidth = 1
        capPath.stroke()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
        ]
        let size = (label as NSString).size(withAttributes: attrs)
        let labelRect = CGRect(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2 + 2,
            width: size.width,
            height: size.height
        )
        (label as NSString).draw(in: labelRect, withAttributes: attrs)
    }

    private func drawTypingOverlay(text: String, style: String, viewport: CGRect) {
        guard !text.isEmpty else {
            return
        }

        let summary = summarizeTypingText(text)
        let panelWidth = min(viewport.width - 56, max(320, CGFloat(summary.count) * 10.4))
        let panelRect = CGRect(
            x: viewport.midX - panelWidth / 2,
            y: viewport.minY + 24,
            width: panelWidth,
            height: 56
        )

        let shadow = NSShadow()
        shadow.shadowBlurRadius = 18
        shadow.shadowOffset = .zero
        shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.16)
        shadow.set()

        let path = NSBezierPath(roundedRect: panelRect, xRadius: 18, yRadius: 18)
        let background: NSColor
        let border: NSColor
        let foreground: NSColor
        let font: NSFont

        switch style {
        case "notes":
            background = NSColor(calibratedRed: 0.99, green: 0.97, blue: 0.90, alpha: 0.97)
            border = NSColor(calibratedRed: 0.90, green: 0.84, blue: 0.66, alpha: 0.85)
            foreground = NSColor(calibratedRed: 0.20, green: 0.16, blue: 0.11, alpha: 1)
            font = NSFont.systemFont(ofSize: 18, weight: .medium)
        case "terminal":
            background = NSColor(calibratedRed: 0.11, green: 0.12, blue: 0.14, alpha: 0.95)
            border = NSColor(calibratedRed: 0.26, green: 0.54, blue: 0.32, alpha: 0.72)
            foreground = NSColor(calibratedRed: 0.62, green: 0.95, blue: 0.70, alpha: 1)
            font = NSFont.monospacedSystemFont(ofSize: 17, weight: .regular)
        case "code":
            background = NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.17, alpha: 0.95)
            border = NSColor(calibratedWhite: 1, alpha: 0.12)
            foreground = NSColor(calibratedWhite: 0.94, alpha: 1)
            font = NSFont.monospacedSystemFont(ofSize: 16, weight: .regular)
        default:
            background = NSColor(calibratedWhite: 0.12, alpha: 0.90)
            border = NSColor(calibratedWhite: 1, alpha: 0.10)
            foreground = NSColor(calibratedWhite: 0.96, alpha: 1)
            font = NSFont.systemFont(ofSize: 18, weight: .medium)
        }

        background.setFill()
        path.fill()
        border.setStroke()
        path.lineWidth = 1
        path.stroke()

        let displayText = style == "terminal" ? "$ \(summary)▌" : "\(summary)▌"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: foreground,
        ]
        let size = (displayText as NSString).size(withAttributes: attrs)
        let textRect = CGRect(
            x: panelRect.minX + 20,
            y: panelRect.midY - size.height / 2,
            width: panelRect.width - 40,
            height: size.height
        )
        (displayText as NSString).draw(in: textRect, withAttributes: attrs)
    }

    private func summarizeTypingText(_ text: String) -> String {
        let compact = text
            .replacingOccurrences(of: "\n", with: "  ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard compact.count > 46 else {
            return compact
        }
        let index = compact.index(compact.startIndex, offsetBy: 43)
        return "\(compact[..<index])..."
    }

    private func drawText(
        text: String,
        in rect: CGRect,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment = .left
    ) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style,
        ]
        text.draw(in: rect, withAttributes: attrs)
    }

}

@MainActor
final class StageOverlayController: NSObject {
    private let stateFile: String
    private let stopFile: String
    private let writer: ResponseWriter
    private let logger: DebugLogger
    private let controlFile: String?
    private var overlayWindow: NSWindow?
    private var controlWindow: StageHUDPanel?
    private var overlayView: StageOverlayView?
    private var controlViewModel: StageHUDViewModel?
    private var lastStateData: Data?
    private var pollTimer: Timer?
    private var currentPhase: String = "staging"
    private var panicRegistrationID: String?

    init(stateFile: String, stopFile: String, replyFile: String?, debugLogPath: String?, controlFile: String?) {
        self.stateFile = stateFile
        self.stopFile = stopFile
        self.writer = ResponseWriter(replyFile: replyFile)
        self.logger = DebugLogger(path: debugLogPath)
        self.controlFile = controlFile
    }

    func run() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        try writer.write(
            ActionHostResponse(
                status: "overlay-running",
                outputPath: nil,
                detail: String(ProcessInfo.processInfo.processIdentifier)
            )
        )
        try refreshState(force: true)
        startPolling()
        app.run()
    }

    private func refreshState(force: Bool) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: stateFile))
        if !force, data == lastStateData {
            return
        }

        let state = try JSONDecoder().decode(StageOverlayState.self, from: data)
        lastStateData = data
        currentPhase = state.phase
        logger.log("stage-overlay: apply phase=\(state.phase) summary=\(state.summary)")
        apply(state: state)
    }

    private func apply(state: StageOverlayState) {
        guard let viewport = state.viewport else {
            return
        }

        let viewportRect = CGRect(
            x: viewport.bounds.x,
            y: viewport.bounds.y,
            width: viewport.bounds.width,
            height: viewport.bounds.height
        )
        let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: viewportRect.midX, y: viewportRect.midY)) })
            ?? NSScreen.main
        guard let screen else {
            return
        }

        if overlayWindow == nil || overlayWindow?.screen != screen {
            logger.log("stage-overlay: create window on screen \(screen.frame)")
            createWindow(screen: screen)
        }

        overlayWindow?.setFrame(screen.frame, display: true)
        overlayView?.state = state
        controlViewModel?.phase = state.phase
        controlViewModel?.targetApp = state.targetApp ?? "Action"
        controlViewModel?.summary = state.summary
        controlViewModel?.detail = state.detail
        controlViewModel?.stepLabel = state.stepLabel
        controlViewModel?.countdownRemaining = state.countdownRemaining
        controlViewModel?.recentLogs = state.recentLogs ?? []
        controlViewModel?.elapsedMs = state.elapsedMs
        if let dockFrame = controlPanelFrame(screenFrame: screen.frame, viewportRect: viewportRect) {
            controlWindow?.setFrame(dockFrame, display: true)
        }
        overlayWindow?.orderFrontRegardless()
        controlWindow?.orderFrontRegardless()
        updatePanicRegistration(for: state)
        logger.log("stage-overlay: window ordered front viewport=\(viewportRect)")
    }

    private func createWindow(screen: NSScreen) {
        let overlayWindow = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        overlayWindow.level = .screenSaver
        overlayWindow.isOpaque = false
        overlayWindow.backgroundColor = .clear
        overlayWindow.hasShadow = false
        overlayWindow.ignoresMouseEvents = true
        overlayWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let overlayView = StageOverlayView(frame: CGRect(origin: .zero, size: screen.frame.size), screenFrame: screen.frame)
        overlayWindow.contentView = overlayView
        self.overlayWindow = overlayWindow
        self.overlayView = overlayView

        guard controlFile != nil else {
            self.controlWindow = nil
            self.controlViewModel = nil
            return
        }

        let controlSize = CGSize(width: 336, height: 456)
        let controlWindow = StageHUDPanel(
            contentRect: CGRect(origin: .zero, size: controlSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        controlWindow.level = actionHUDPanelLevel()
        controlWindow.isOpaque = false
        controlWindow.backgroundColor = .clear
        controlWindow.hasShadow = true
        controlWindow.ignoresMouseEvents = false
        controlWindow.isMovable = false
        controlWindow.isFloatingPanel = true
        controlWindow.hidesOnDeactivate = false
        controlWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle, .transient]
        controlWindow.isReleasedWhenClosed = false
        let controlViewModel = StageHUDViewModel()
        controlViewModel.onCommand = { [weak self] command in
            self?.appendControlCommand(command)
        }
        let controlView = NSHostingView(rootView: StageHUDRootView(model: controlViewModel))
        controlView.frame = CGRect(origin: .zero, size: controlSize)
        controlView.autoresizingMask = [.width, .height]
        controlWindow.contentView = controlView
        self.controlWindow = controlWindow
        self.controlViewModel = controlViewModel
    }

    private func startPolling() {
        let timer = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        pollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func tick() {
        if FileManager.default.fileExists(atPath: stopFile) {
            logger.log("stage-overlay: stop signal received")
            shutdown()
            return
        }

        enforceTopOrder()

        if shouldHandleControlCommandsLocally() {
            let commands = consumeControlCommands()
            if commands.contains("clear") || commands.contains("quit") {
                logger.log("stage-overlay: local dismiss command received")
                shutdown()
                return
            }
        }

        do {
            try refreshState(force: false)
        } catch {
            logger.log("stage-overlay: refresh failed \(error.localizedDescription)")
        }
    }

    private func shutdown() {
        pollTimer?.invalidate()
        pollTimer = nil
        overlayWindow?.orderOut(nil)
        controlWindow?.orderOut(nil)
        if let panicRegistrationID {
            ActionPanicRegistry.unregister(id: panicRegistrationID)
            self.panicRegistrationID = nil
        }
        NSApplication.shared.stop(nil)
    }

    private func controlPanelFrame(screenFrame: CGRect, viewportRect: CGRect) -> CGRect? {
        let edgePadding: CGFloat = 16
        let topPadding: CGFloat = 18
        let bottomPadding: CGFloat = 16
        let panelWidth: CGFloat = 336
        let panelHeight: CGFloat = min(456, screenFrame.height - topPadding - bottomPadding)
        let x = screenFrame.maxX - edgePadding - panelWidth
        let preferredTopAlignedY = viewportRect.maxY - panelHeight + 6
        let y = min(
            screenFrame.maxY - topPadding - panelHeight,
            max(screenFrame.minY + bottomPadding, preferredTopAlignedY)
        )
        return CGRect(x: x, y: y, width: panelWidth, height: panelHeight)
    }

    private func appendControlCommand(_ command: String) {
        guard let controlFile else {
            return
        }

        DispatchQueue.global(qos: .utility).async {
            let line = "\(command)\n"
            do {
                let url = URL(fileURLWithPath: controlFile)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: controlFile) {
                    let handle = try FileHandle(forWritingTo: url)
                    try handle.seekToEnd()
                    try handle.write(contentsOf: Data(line.utf8))
                    try handle.close()
                } else {
                    try Data(line.utf8).write(to: url)
                }
            } catch {
                FileHandle.standardError.write(Data("ActionHost control write failed: \(error.localizedDescription)\n".utf8))
            }
        }
    }

    private func shouldHandleControlCommandsLocally() -> Bool {
        switch currentPhase {
        case "created", "staging", "completed", "failed", "cancelled":
            return true
        default:
            return false
        }
    }

    private func consumeControlCommands() -> [String] {
        guard let controlFile,
              FileManager.default.fileExists(atPath: controlFile),
              let raw = try? String(contentsOfFile: controlFile, encoding: .utf8) else {
            return []
        }

        let commands = raw
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        guard !commands.isEmpty else {
            return []
        }

        try? "".write(toFile: controlFile, atomically: true, encoding: .utf8)
        return commands
    }

    private func enforceTopOrder() {
        overlayWindow?.orderFrontRegardless()
        controlWindow?.orderFrontRegardless()
    }

    private func updatePanicRegistration(for state: StageOverlayState) {
        guard controlFile != nil || !stopFile.isEmpty else {
            return
        }

        let registrationID = "stage-overlay-\(state.sessionId)"
        if panicRegistrationID != registrationID {
            if let panicRegistrationID {
                ActionPanicRegistry.unregister(id: panicRegistrationID)
            }
            panicRegistrationID = registrationID
        }

        let detail = state.targetApp.map { "\($0) · \(state.phase)" } ?? "Action · \(state.phase)"
        do {
            try ActionPanicRegistry.register(
                id: registrationID,
                title: "Stop Action",
                detail: detail,
                controlFile: controlFile,
                stopFile: stopFile
            )
        } catch {
            logger.log("stage-overlay: panic registration failed \(error.localizedDescription)")
        }
    }
}

func rectFromOptions(_ options: CommandOptions) throws -> CGRect {
    let x = Double(try options.required("x")) ?? 0
    let y = Double(try options.required("y")) ?? 0
    let width = Double(try options.required("width")) ?? 0
    let height = Double(try options.required("height")) ?? 0

    return CGRect(x: x, y: y, width: width, height: height)
}

func resolvedFinishedSignalPath(from options: CommandOptions) -> String {
    if let path = options.options["finished-file"], !path.isEmpty {
        return path
    }

    let outputBase = options.options["output"] ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString).path
    return "\(outputBase).finished"
}

func waitForFinishedSignal(at path: String) throws {
    while !FileManager.default.fileExists(atPath: path) {
        Thread.sleep(forTimeInterval: 0.1)
    }

    let contents = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    if contents.hasPrefix("error:") {
        throw ActionHostError.captureFailed(String(contents.dropFirst("error:".count)).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

func terminateRunningActionApps(timeout: TimeInterval = 2.5) -> Bool {
    let bundleId = "dev.action.Action"
    let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
    guard !running.isEmpty else {
        return true
    }

    for app in running {
        _ = app.terminate()
    }

    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        let remaining = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        if remaining.isEmpty {
            return true
        }
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.08))
    }

    return NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty
}

func run(command: ActionHostCommand, options: CommandOptions, writer: ResponseWriter, logger: DebugLogger) async throws {
    let agentBridge = ActionAgentCommandBridge()
    switch command {
    case .agent:
        throw ActionHostError.unsupportedOS("agent should be started before command dispatch")
    case .launcher:
        throw ActionHostError.unsupportedOS("launcher should be started via runUICommand")
    case .webkitSmoke:
        throw ActionHostError.unsupportedOS("webkit-smoke should be started via runUICommand")
    case .stageOverlay:
        throw ActionHostError.unsupportedOS("stage-overlay should be started via runUICommand")
    case .guidedCalculatorDemo:
        let runner = GuidedCaptureSessionRunner(writer: writer, logger: logger, options: options)
        try await runner.run()
    case .quitApp:
        let didQuit = terminateRunningActionApps()
        try writer.write(
            ActionHostResponse(
                status: didQuit ? "quit" : "error",
                outputPath: nil,
                detail: didQuit ? "terminated-running-action-apps" : "unable-to-quit-within-timeout"
            )
        )
    case .status:
        try writer.write(snapshot(promptAccessibility: false, requestScreenRecordingPermission: false))
    case .request:
        try writer.write(snapshot(promptAccessibility: true, requestScreenRecordingPermission: true))
    case .openAccessibilitySettings:
        openSettingsPane(anchor: "Privacy_Accessibility")
    case .openScreenRecordingSettings:
        openSettingsPane(anchor: "Privacy_ScreenCapture")
    case .currentSurface:
        try writer.write(try currentSurface())
    case .panicOverlay:
        throw ActionHostError.unsupportedOS("panic-overlay should be started via runUICommand")
    case .panicStop:
        let count = ActionPanicRegistry.triggerStopAll()
        try writer.write(
            ActionHostResponse(
                status: "stopping",
                outputPath: nil,
                detail: "\(count)"
            )
        )
    case .recordAppWindow:
        guard #available(macOS 15.0, *) else {
            throw ActionHostError.unsupportedOS("Window recording requires macOS 15.0 or newer.")
        }

        let bundleId = try options.required("bundle-id")
        let outputPath = try options.required("output")
        let finishedSignalPath = resolvedFinishedSignalPath(from: options)
        try writer.write(ActionHostResponse(status: "recording", outputPath: outputPath, detail: nil))
        var params: [String: String] = [
            "bundleId": bundleId,
            "output": outputPath,
            "finishedFile": finishedSignalPath,
        ]
        if let debugLog = options.options["debug-log"] {
            params["debugLog"] = debugLog
        }
        if let stopFile = options.options["stop-file"] {
            params["stopFile"] = stopFile
        }
        let response = try await agentBridge.send(method: .recordAppWindow, params: params)
        if !response.ok {
            throw ActionHostError.captureFailed(response.error ?? "Failed to start app-window recording")
        }
        try waitForFinishedSignal(at: finishedSignalPath)
    case .recordAppWindowLocal:
        guard #available(macOS 15.0, *) else {
            throw ActionHostError.unsupportedOS("Window recording requires macOS 15.0 or newer.")
        }

        let bundleId = try options.required("bundle-id")
        let outputPath = try options.required("output")
        let recorder = WindowRecorder(writer: writer, logger: logger)
        try await recorder.recordAppWindow(
            bundleId: bundleId,
            outputPath: outputPath,
            stopSignalPath: options.options["stop-file"],
            finishedSignalPath: options.options["finished-file"]
        )
    case .recordRegion:
        guard #available(macOS 15.0, *) else {
            throw ActionHostError.unsupportedOS("Region recording requires macOS 15.0 or newer.")
        }

        let outputPath = try options.required("output")
        let rect = try rectFromOptions(options)
        let finishedSignalPath = resolvedFinishedSignalPath(from: options)
        try writer.write(ActionHostResponse(status: "recording", outputPath: outputPath, detail: nil))
        var params: [String: String] = [
            "output": outputPath,
            "finishedFile": finishedSignalPath,
            "x": String(describing: rect.origin.x),
            "y": String(describing: rect.origin.y),
            "width": String(describing: rect.size.width),
            "height": String(describing: rect.size.height),
            "fps": String(describing: options.double("fps", default: 15)),
            "scale": String(describing: options.double("scale", default: 1)),
        ]
        if let debugLog = options.options["debug-log"] {
            params["debugLog"] = debugLog
        }
        if let stopFile = options.options["stop-file"] {
            params["stopFile"] = stopFile
        }
        let response = try await agentBridge.send(method: .recordRegion, params: params)
        if !response.ok {
            throw ActionHostError.captureFailed(response.error ?? "Failed to start region recording")
        }
        try waitForFinishedSignal(at: finishedSignalPath)
    case .recordRegionLocal:
        guard #available(macOS 15.0, *) else {
            throw ActionHostError.unsupportedOS("Region recording requires macOS 15.0 or newer.")
        }

        let outputPath = try options.required("output")
        let rect = try rectFromOptions(options)
        let recorder = WindowRecorder(writer: writer, logger: logger)
        try await recorder.recordRegion(
            rect: rect,
            outputPath: outputPath,
            stopSignalPath: options.options["stop-file"],
            finishedSignalPath: options.options["finished-file"],
            fps: options.double("fps", default: 15),
            scale: options.double("scale", default: 1)
        )
    case .recordingProbe:
        throw ActionHostError.unsupportedOS("recording-probe must be started through the UI command path")
    case .screenshotAppWindow:
        guard #available(macOS 14.0, *) else {
            throw ActionHostError.unsupportedOS("Window screenshots require macOS 14.0 or newer.")
        }

        let bundleId = try options.required("bundle-id")
        let outputPath = try options.required("output")
        let response = try await agentBridge.send(
            method: .screenshotAppWindow,
            params: [
                "bundleId": bundleId,
                "output": outputPath,
            ]
        )
        try writer.write(
            ActionHostResponse(
                status: response.result?["status"] ?? (response.ok ? "screenshot" : "error"),
                outputPath: response.result?["outputPath"] ?? outputPath,
                detail: response.error
            )
        )
    case .screenshotRegion:
        let outputPath = try options.required("output")
        let rect = try rectFromOptions(options)
        let response = try await agentBridge.send(
            method: .screenshotRegion,
            params: [
                "output": outputPath,
                "x": String(describing: rect.origin.x),
                "y": String(describing: rect.origin.y),
                "width": String(describing: rect.size.width),
                "height": String(describing: rect.size.height),
            ]
        )
        try writer.write(
            ActionHostResponse(
                status: response.result?["status"] ?? (response.ok ? "screenshot" : "error"),
                outputPath: response.result?["outputPath"] ?? outputPath,
                detail: response.error
            )
        )
    case .screenshotScreen:
        let outputPath = try options.required("output")
        let response = try await agentBridge.send(
            method: .screenshotScreen,
            params: ["output": outputPath]
        )
        try writer.write(
            ActionHostResponse(
                status: response.result?["status"] ?? (response.ok ? "screenshot" : "error"),
                outputPath: response.result?["outputPath"] ?? outputPath,
                detail: response.result?["detail"] ?? response.error
            )
        )
    case .activateApp:
        let bundleId = try options.required("bundle-id")
        try ActionNativeAutomation.activateApplication(bundleId: bundleId)
        try writer.write(ActionHostResponse(status: "activated", outputPath: nil, detail: bundleId))
    case .launchApp:
        let bundleId = try options.required("bundle-id")
        try await MainActor.run {
            try ActionNativeAutomation.launchApplication(bundleId: bundleId)
        }
        try writer.write(ActionHostResponse(status: "launched", outputPath: nil, detail: bundleId))
    case .prepareNotesNote:
        let noteName = try prepareNotesNote()
        try writer.write(ActionHostResponse(status: "prepared", outputPath: nil, detail: noteName))
    case .getCaptureWindowFrame:
        let bundleId = try options.required("bundle-id")
        let rect = try await getCaptureWindowFrame(bundleId: bundleId)
        try writer.write(
            WindowFrameResponse(
                status: "capture-window-frame",
                bundleId: bundleId,
                frame: overlayBounds(from: rect)
            )
        )
    case .composeRoundedScreenshot:
        let inputPath = try options.required("input")
        let outputPath = try options.required("output")
        let radius = CGFloat(options.double("radius", default: 24))
        let background = options.options["background"] ?? "E8EDF5"
        try composeRoundedScreenshot(
            inputPath: inputPath,
            outputPath: outputPath,
            radius: radius,
            backgroundHex: background
        )
        try writer.write(
            ActionHostResponse(
                status: "composed",
                outputPath: outputPath,
                detail: "radius=\(Int(radius)) background=\(background)"
            )
        )
    case .typeText:
        let text = try options.required("text")
        let delayMs = Int(options.double("delay-ms", default: 0))
        try postText(text, delayMs: delayMs > 0 ? delayMs : nil)
        try writer.write(ActionHostResponse(status: "typed", outputPath: nil, detail: text))
    case .pressKey:
        let key = try options.required("key")
        let modifiers = options.options["modifiers"]?
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
        try postKeyPress(key, modifiers: modifiers)
        let detail = modifiers.isEmpty ? key : "\(modifiers.joined(separator: "+"))+\(key)"
        try writer.write(ActionHostResponse(status: "pressed", outputPath: nil, detail: detail))
    case .clickPoint:
        let x = options.double("x", default: .nan)
        let y = options.double("y", default: .nan)
        guard x.isFinite, y.isFinite else {
            throw ActionHostError.missingOption("--x/--y")
        }
        try clickPoint(CGPoint(x: x, y: y))
        try writer.write(ActionHostResponse(status: "clicked", outputPath: nil, detail: "\(Int(x)),\(Int(y))"))
    case .drag:
        let fromX = options.double("from-x", default: .nan)
        let fromY = options.double("from-y", default: .nan)
        let toX = options.double("to-x", default: .nan)
        let toY = options.double("to-y", default: .nan)
        let durationMs = Int(options.double("duration-ms", default: 300))
        let filePath = options.options["file-path"]

        guard fromX.isFinite, fromY.isFinite, toX.isFinite, toY.isFinite else {
            throw ActionHostError.missingOption("--from-x --from-y --to-x --to-y")
        }
        if let filePath, !filePath.isEmpty, !FileManager.default.fileExists(atPath: filePath) {
            throw ActionHostError.fileNotFound(filePath)
        }
        if let filePath, !filePath.isEmpty {
            try ActionNativeAutomation.dragFile(path: filePath, from: CGPoint(x: fromX, y: fromY), to: CGPoint(x: toX, y: toY), durationMs: durationMs)
            try writer.write(ActionHostResponse(status: "dragged", outputPath: nil, detail: "file=\(filePath)"))
        } else {
            try ActionNativeAutomation.drag(from: CGPoint(x: fromX, y: fromY), to: CGPoint(x: toX, y: toY), durationMs: durationMs)
            try writer.write(ActionHostResponse(status: "dragged", outputPath: nil, detail: "\(Int(fromX)),\(Int(fromY))->\(Int(toX)),\(Int(toY))"))
        }
    case .clickCalculatorButton:
        let button = try options.required("button")
        try clickCalculatorButton(label: button)
        try writer.write(ActionHostResponse(status: "clicked", outputPath: nil, detail: button))
    case .inspectCalculatorButtons:
        try writer.write(calculatorButtons())
    case .inspectCalculatorUI:
        try writer.write(ActionNativeAutomation.calculatorAccessibilityNodes())
    case .inspectAppUI:
        let bundleId = try options.required("bundle-id")
        let maxDepth = Int(options.double("max-depth", default: 6))
        let maxNodes = Int(options.double("max-nodes", default: 250))
        try writer.write(
            ActionNativeAutomation.accessibilityNodes(
                bundleId: bundleId,
                maxDepth: maxDepth,
                maxNodes: maxNodes
            )
        )
    case .getCalculatorDisplay:
        try writer.write(
            ActionHostResponse(
                status: "calculator-display",
                outputPath: nil,
                detail: try ActionNativeAutomation.calculatorDisplayValue()
            )
        )
    case .setWindowFrame:
        let bundleId = try options.required("bundle-id")
        let rect = try rectFromOptions(options)
        try ActionNativeAutomation.setWindowFrame(bundleId: bundleId, rect: rect)
        try writer.write(ActionHostResponse(status: "window-framed", outputPath: nil, detail: bundleId))
    case .getWindowFrame:
        let bundleId = try options.required("bundle-id")
        let rect = try ActionNativeAutomation.getWindowFrame(bundleId: bundleId)
        try writer.write(
            WindowFrameResponse(
                status: "window-frame",
                bundleId: bundleId,
                frame: overlayBounds(from: rect)
            )
        )
    }
}

@main
struct ActionHostMain {
    static func main() {
        let options = CommandOptions(arguments: CommandLine.arguments)
        let writer = ResponseWriter(replyFile: options.options["reply-file"])
        let logger = DebugLogger(path: options.options["debug-log"])
        let command = options.command ?? .launcher

        if command == .agent {
            MainActor.assumeIsolated {
                ActionAgentRuntime.run(arguments: CommandLine.arguments)
            }
        }

        if runUICommandIfNeeded(command: command, options: options) {
            return
        }

        let terminationReason = "ActionHost command in progress"
        ProcessInfo.processInfo.disableAutomaticTermination(terminationReason)
        ProcessInfo.processInfo.disableSuddenTermination()

        Task {
            do {
                defer {
                    ProcessInfo.processInfo.enableSuddenTermination()
                    ProcessInfo.processInfo.enableAutomaticTermination(terminationReason)
                }
                try await run(command: command, options: options, writer: writer, logger: logger)
                Darwin.exit(0)
            } catch {
                defer {
                    ProcessInfo.processInfo.enableSuddenTermination()
                    ProcessInfo.processInfo.enableAutomaticTermination(terminationReason)
                }
                logger.log("error: \(error.localizedDescription)")
                if options.options["reply-file"] != nil {
                    try? writer.write(
                        ActionHostResponse(
                            status: "error",
                            outputPath: options.options["output"],
                            detail: error.localizedDescription
                        )
                    )
                }
                FileHandle.standardError.write(Data("ActionHost failed: \(error.localizedDescription)\n".utf8))
                Darwin.exit(1)
            }
        }

        dispatchMain()
    }

    private static func runUICommandIfNeeded(command: ActionHostCommand, options: CommandOptions) -> Bool {
        switch command {
        case .panicOverlay:
            let replyFile = options.options["reply-file"]
            let debugLogPath = options.options["debug-log"]
            MainActor.assumeIsolated {
                let controller = ActionPanicOverlayController(
                    replyFile: replyFile,
                    debugLogPath: debugLogPath
                )
                do {
                    try controller.run()
                } catch {
                    FileHandle.standardError.write(Data("ActionHost failed: \(error.localizedDescription)\n".utf8))
                    Darwin.exit(1)
                }
            }
            return true
        case .stageOverlay:
            let stateFile: String
            let stopFile: String
            do {
                stateFile = try options.required("state-file")
                stopFile = try options.required("stop-file")
            } catch {
                FileHandle.standardError.write(Data("ActionHost failed: \(error.localizedDescription)\n".utf8))
                Darwin.exit(1)
            }
            let replyFile = options.options["reply-file"]
            let debugLogPath = options.options["debug-log"]
            let controlFile = options.options["control-file"]
            MainActor.assumeIsolated {
                let controller = StageOverlayController(
                    stateFile: stateFile,
                    stopFile: stopFile,
                    replyFile: replyFile,
                    debugLogPath: debugLogPath,
                    controlFile: controlFile
                )
                do {
                    try controller.run()
                } catch {
                    FileHandle.standardError.write(Data("ActionHost failed: \(error.localizedDescription)\n".utf8))
                    Darwin.exit(1)
                }
            }
            return true
        case .launcher:
            MainActor.assumeIsolated {
                ActionLauncherController.shared.run()
            }
            return true
        case .webkitSmoke:
            let urlString = options.options["url"] ?? "http://127.0.0.1:4318/"
            guard let url = URL(string: urlString) else {
                FileHandle.standardError.write(Data("ActionHost failed: missing or invalid --url\n".utf8))
                Darwin.exit(1)
            }
            MainActor.assumeIsolated {
                let runner = WebKitSmokeAppRunner(url: url)
                runner.run()
            }
            return true
        case .recordingProbe:
            guard #available(macOS 15.0, *) else {
                FileHandle.standardError.write(Data("ActionHost failed: recording-probe requires macOS 15.0 or newer.\n".utf8))
                Darwin.exit(1)
            }
            let writer = ResponseWriter(replyFile: options.options["reply-file"])
            let logger = DebugLogger(path: options.options["debug-log"])
            let target: RecordingProbeAppRunner.Target
            if let bundleId = options.options["bundle-id"], !bundleId.isEmpty {
                target = .appWindow(bundleId)
            } else {
                let rect: CGRect
                do {
                    rect = try rectFromOptions(options)
                } catch {
                    FileHandle.standardError.write(Data("ActionHost failed: \(error.localizedDescription)\n".utf8))
                    Darwin.exit(1)
                }
                target = .region(rect)
            }
            let outputPath = options.options["output"] ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("recording-probe-\(UUID().uuidString).mov").path
            let config = RecordingProbeAppRunner.Configuration(
                target: target,
                outputPath: outputPath,
                stopSignalPath: options.options["stop-file"],
                finishedSignalPath: options.options["finished-file"],
                fps: options.double("fps", default: 15),
                scale: options.double("scale", default: 1)
            )
            MainActor.assumeIsolated {
                let runner = RecordingProbeAppRunner(configuration: config, writer: writer, debugLogger: logger)
                runner.run()
            }
            return true
        default:
            return false
        }
    }
}
