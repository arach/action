import AppKit
import ActionCore
@preconcurrency import ApplicationServices
import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit
import SwiftUI

enum PermissionState: String, Encodable {
    case granted
    case denied
}

struct PermissionSnapshot: Encodable {
    let accessibility: PermissionState
    let screenRecording: PermissionState
    let notes: [String]?
}

struct ActionHostResponse: Encodable {
    let status: String
    let outputPath: String?
    let detail: String?
}

enum ActionHostCommand: String {
    case agent
    case launcher
    case webkitSmoke = "webkit-smoke"
    case guidedCalculatorDemo = "guided-calculator-demo"
    case status
    case request
    case openAccessibilitySettings = "open-accessibility-settings"
    case openScreenRecordingSettings = "open-screen-recording-settings"
    case stageOverlay = "stage-overlay"
    case launchApp = "launch-app"
    case recordAppWindow = "record-app-window"
    case recordAppWindowLocal = "record-app-window-local"
    case screenshotAppWindow = "screenshot-app-window"
    case activateApp = "activate-app"
    case typeText = "type-text"
    case pressKey = "press-key"
    case clickCalculatorButton = "click-calculator-button"
    case inspectCalculatorButtons = "inspect-calculator-buttons"
    case inspectCalculatorUI = "inspect-calculator-ui"
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

func postText(_ text: String) throws {
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
        keyUp.post(tap: .cghidEventTap)
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

func bestWindowSelection(for bundleId: String) async throws -> WindowSelection {
    let content = try await shareableContent()

    let candidates = content.windows.filter { window in
        window.owningApplication?.bundleIdentifier == bundleId && window.isOnScreen && window.windowLayer == 0
    }

    let selectedWindow: SCWindow

    if let active = candidates.first(where: \.isActive) {
        selectedWindow = active
    } else if let largest = candidates.max(by: { lhs, rhs in
        lhs.frame.width * lhs.frame.height < rhs.frame.width * rhs.frame.height
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

func pngData(from image: CGImage) -> Data? {
    let bitmap = NSBitmapImageRep(cgImage: image)
    return bitmap.representation(using: .png, properties: [:])
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
        drawHudPill(state: state, viewport: viewport)

        if state.phase == "countdown", let countdown = state.countdownRemaining {
            drawCountdown(String(countdown), viewport: viewport)
        }
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

    private func drawHudPill(state: StageOverlayState, viewport: CGRect) {
        let reservedRightInset: CGFloat = 340
        let width: CGFloat = min(440, max(320, viewport.width + 84))
        let height: CGFloat = 110
        let maxX = max(24, bounds.width - reservedRightInset - width)
        let x = min(maxX, max(24, viewport.minX))
        let yAbove = viewport.maxY + 14
        let yBelow = viewport.minY - height - 14
        let y: CGFloat
        if yAbove + height <= bounds.height - 24 {
            y = yAbove
        } else {
            y = max(24, yBelow)
        }
        let rect = CGRect(x: x, y: y, width: width, height: height)
        let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)

        NSColor(calibratedWhite: 0.055, alpha: 0.9).setFill()
        path.fill()
        NSColor(calibratedWhite: 1, alpha: 0.16).setStroke()
        path.lineWidth = 1
        path.stroke()

        let phaseLabel = state.isRecording ? "RECORDING" : state.phase.uppercased()
        let contentInset: CGFloat = 14
        let contentWidth = rect.width - (contentInset * 2)
        let topY = rect.maxY - contentInset

        let divider = NSBezierPath()
        divider.move(to: CGPoint(x: rect.minX + contentInset, y: topY - 22))
        divider.line(to: CGPoint(x: rect.maxX - contentInset, y: topY - 22))
        NSColor(calibratedWhite: 1, alpha: 0.12).setStroke()
        divider.lineWidth = 1
        divider.stroke()

        let indicatorRect = CGRect(x: rect.minX + contentInset, y: topY - 13, width: 6, height: 6)
        let indicatorPath = NSBezierPath(ovalIn: indicatorRect)
        let indicatorColor = state.isRecording
            ? NSColor(calibratedWhite: 0.95, alpha: 1.0)
            : NSColor(calibratedWhite: 0.7, alpha: 0.95)
        indicatorColor.setFill()
        indicatorPath.fill()

        drawText(
            text: phaseLabel,
            in: CGRect(x: rect.minX + contentInset + 12, y: topY - 17, width: 210, height: 12),
            font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
            color: NSColor(calibratedWhite: 1, alpha: 0.88)
        )
        drawText(
            text: state.targetApp ?? "Action",
            in: CGRect(x: rect.maxX - contentInset - 132, y: topY - 17, width: 132, height: 12),
            font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            color: NSColor(calibratedWhite: 1, alpha: 0.68),
            alignment: .right
        )

        let headline = state.summary
        drawText(
            text: headline,
            in: CGRect(x: rect.minX + contentInset, y: rect.maxY - 56, width: contentWidth, height: 18),
            font: NSFont.monospacedSystemFont(ofSize: 15, weight: .semibold),
            color: NSColor(calibratedWhite: 0.98, alpha: 0.96)
        )

        let context: String
        if let label = state.stepLabel, !label.isEmpty {
            context = label
        } else if let detail = state.detail, !detail.isEmpty {
            context = detail
        } else {
            context = phaseDetail(for: state)
        }
        drawText(
            text: context,
            in: CGRect(x: rect.minX + contentInset, y: rect.maxY - 74, width: contentWidth, height: 14),
            font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            color: NSColor(calibratedWhite: 1, alpha: 0.62)
        )

        var chipX = rect.minX + contentInset
        let chipY = rect.minY + 12

        func drawChip(_ text: String) {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
            ]
            let textSize = text.size(withAttributes: attrs)
            let chipWidth = textSize.width + 18
            if chipX + chipWidth > rect.maxX - contentInset {
                return
            }
            let chipRect = CGRect(x: chipX, y: chipY, width: chipWidth, height: 20)
            let chipPath = NSBezierPath(roundedRect: chipRect, xRadius: 4, yRadius: 4)
            NSColor(calibratedWhite: 1, alpha: 0.08).setFill()
            chipPath.fill()
            NSColor(calibratedWhite: 1, alpha: 0.14).setStroke()
            chipPath.lineWidth = 1
            chipPath.stroke()
            drawText(
                text: text,
                in: CGRect(x: chipRect.minX + 9, y: chipRect.minY + 4, width: chipRect.width - 12, height: 12),
                font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                color: NSColor(calibratedWhite: 1, alpha: 0.72)
            )
            chipX += chipWidth + 8
        }

        if state.phase == "countdown", let remaining = state.countdownRemaining {
            drawChip("START IN \(remaining)S")
        }
        if let current = state.stepCurrent, let total = state.stepTotal, total > 0 {
            drawChip("STEP \(current)/\(total)")
        }
        if let logs = state.recentLogs, let last = logs.last, !last.isEmpty {
            drawChip(last.uppercased())
        }
    }

    private func phaseDetail(for state: StageOverlayState) -> String {
        switch state.phase {
        case "countdown":
            return "Stand by for capture"
        case "recording":
            return "Viewport locked and capture live"
        case "completed":
            return "Artifacts saved"
        default:
            return "Guided capture session"
        }
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

    init(stateFile: String, stopFile: String, replyFile: String?, debugLogPath: String?, controlFile: String?) {
        self.stateFile = stateFile
        self.stopFile = stopFile
        self.writer = ResponseWriter(replyFile: replyFile)
        self.logger = DebugLogger(path: debugLogPath)
        self.controlFile = controlFile
    }

    func run() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        configureAppIcon()
        app.activate(ignoringOtherApps: true)
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
        controlViewModel?.recentLogs = state.recentLogs ?? []
        controlViewModel?.elapsedMs = state.elapsedMs
        if let dockFrame = controlPanelFrame(screenFrame: screen.frame, viewportRect: viewportRect) {
            controlWindow?.setFrame(dockFrame, display: true)
        }
        overlayWindow?.orderFrontRegardless()
        controlWindow?.orderFrontRegardless()
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

        let controlSize = CGSize(width: 312, height: 428)
        let controlWindow = StageHUDPanel(
            contentRect: CGRect(origin: .zero, size: controlSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        controlWindow.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) - 1)
        controlWindow.isOpaque = false
        controlWindow.backgroundColor = .clear
        controlWindow.hasShadow = true
        controlWindow.ignoresMouseEvents = false
        controlWindow.isMovable = false
        controlWindow.isFloatingPanel = true
        controlWindow.hidesOnDeactivate = false
        controlWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
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
        NSApplication.shared.stop(nil)
    }

    private func controlPanelFrame(screenFrame: CGRect, viewportRect: CGRect) -> CGRect? {
        let sideGap: CGFloat = 14
        let edgePadding: CGFloat = 16
        let topPadding: CGFloat = 18
        let bottomPadding: CGFloat = 16
        let panelWidth: CGFloat = 312
        let panelHeight: CGFloat = min(428, screenFrame.height - topPadding - bottomPadding)
        let preferredRightX = viewportRect.maxX + sideGap
        let preferredLeftX = viewportRect.minX - sideGap - panelWidth
        let hasRoomOnRight = preferredRightX + panelWidth <= screenFrame.maxX - edgePadding
        let unclampedX = hasRoomOnRight ? preferredRightX : preferredLeftX
        let x = min(
            screenFrame.maxX - edgePadding - panelWidth,
            max(screenFrame.minX + edgePadding, unclampedX)
        )
        let preferredTopAlignedY = viewportRect.maxY - panelHeight
        let y = min(
            screenFrame.maxY - topPadding - panelHeight,
            max(screenFrame.minY + bottomPadding, preferredTopAlignedY)
        )
        return CGRect(x: x, y: y, width: panelWidth, height: panelHeight)
    }

    private func configureAppIcon() {
        if let image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Action") {
            image.size = NSSize(width: 512, height: 512)
            NSApplication.shared.applicationIconImage = image
        }
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

func run(command: ActionHostCommand, options: CommandOptions, writer: ResponseWriter, logger: DebugLogger) async throws {
    let agentBridge = ActionAgentCommandBridge()
    switch command {
    case .agent:
        throw ActionHostError.unsupportedOS("agent should be started before command dispatch")
    case .launcher:
        throw ActionHostError.unsupportedOS("launcher should be started via runUICommand")
    case .webkitSmoke:
        throw ActionHostError.unsupportedOS("webkit-smoke should be started via runUICommand")
    case .guidedCalculatorDemo:
        let runner = GuidedCaptureSessionRunner(writer: writer, logger: logger, options: options)
        try await runner.run()
    case .status:
        try writer.write(snapshot(promptAccessibility: false, requestScreenRecordingPermission: false))
    case .request:
        try writer.write(snapshot(promptAccessibility: true, requestScreenRecordingPermission: true))
    case .openAccessibilitySettings:
        openSettingsPane(anchor: "Privacy_Accessibility")
    case .openScreenRecordingSettings:
        openSettingsPane(anchor: "Privacy_ScreenCapture")
    case .stageOverlay:
        let stateFile = try options.required("state-file")
        let stopFile = try options.required("stop-file")
        let replyFile = options.options["reply-file"]
        let debugLogPath = options.options["debug-log"]
        let controlFile = options.options["control-file"]
        try await MainActor.run {
            let controller = StageOverlayController(
                stateFile: stateFile,
                stopFile: stopFile,
                replyFile: replyFile,
                debugLogPath: debugLogPath,
                controlFile: controlFile
            )
            try controller.run()
        }
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
    case .typeText:
        let text = try options.required("text")
        try postText(text)
        try writer.write(ActionHostResponse(status: "typed", outputPath: nil, detail: text))
    case .pressKey:
        let key = try options.required("key")
        try postText(key)
        try writer.write(ActionHostResponse(status: "pressed", outputPath: nil, detail: key))
    case .clickCalculatorButton:
        let button = try options.required("button")
        try clickCalculatorButton(label: button)
        try writer.write(ActionHostResponse(status: "clicked", outputPath: nil, detail: button))
    case .inspectCalculatorButtons:
        try writer.write(calculatorButtons())
    case .inspectCalculatorUI:
        try writer.write(ActionNativeAutomation.calculatorAccessibilityNodes())
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
                frame: OverlayBounds(
                    x: rect.origin.x,
                    y: rect.origin.y,
                    width: rect.size.width,
                    height: rect.size.height
                )
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
        case .launcher:
            MainActor.assumeIsolated {
                ActionLauncherController.shared.run()
            }
            return true
        case .webkitSmoke:
            let urlString = options.options["url"] ?? "https://www.apple.com"
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
