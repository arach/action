import AppKit
@preconcurrency import ApplicationServices
import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit

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
    case status
    case request
    case openAccessibilitySettings = "open-accessibility-settings"
    case openScreenRecordingSettings = "open-screen-recording-settings"
    case stageOverlay = "stage-overlay"
    case recordAppWindow = "record-app-window"
    case screenshotAppWindow = "screenshot-app-window"
    case activateApp = "activate-app"
    case typeText = "type-text"
    case pressKey = "press-key"
    case clickCalculatorButton = "click-calculator-button"
    case inspectCalculatorButtons = "inspect-calculator-buttons"
    case setWindowFrame = "set-window-frame"
    case recordRegion = "record-region"
    case screenshotRegion = "screenshot-region"
}

enum ActionHostError: LocalizedError {
    case missingOption(String)
    case unsupportedOS(String)
    case windowNotFound(String)
    case unableToEncodeImage
    case missingOutputPath
    case missingStopSignalPath
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
    let command: ActionHostCommand
    let options: [String: String]

    init(arguments: [String]) {
        let commandName = arguments.dropFirst().first
        self.command = commandName.flatMap(ActionHostCommand.init(rawValue:)) ?? .status

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

struct OverlayBounds: Decodable {
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
            roundedRect: viewport.insetBy(dx: -18, dy: -18),
            xRadius: 28,
            yRadius: 28
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
        let outer = viewport.insetBy(dx: -10, dy: -10)
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 30
        shadow.shadowOffset = .zero
        shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.4)
        shadow.set()

        let glowPath = NSBezierPath(roundedRect: outer, xRadius: 28, yRadius: 28)
        let accent = state.isRecording
            ? NSColor(calibratedWhite: 0.9, alpha: 0.82)
            : NSColor(calibratedWhite: 1, alpha: 0.22)
        accent.setStroke()
        glowPath.lineWidth = state.isRecording ? 4 : 2
        glowPath.stroke()

        NSGraphicsContext.saveGraphicsState()
        let innerPath = NSBezierPath(roundedRect: viewport, xRadius: 22, yRadius: 22)
        NSColor(calibratedWhite: 1, alpha: 0.12).setStroke()
        innerPath.lineWidth = 1
        innerPath.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawHudPill(state: StageOverlayState, viewport: CGRect) {
        let width: CGFloat = 320
        let height: CGFloat = 82
        let x = min(bounds.width - width - 24, max(24, viewport.maxX - width))
        let y = min(bounds.height - height - 24, viewport.maxY + 18)
        let rect = CGRect(x: x, y: y, width: width, height: height)
        let path = NSBezierPath(roundedRect: rect, xRadius: 22, yRadius: 22)

        NSColor(calibratedWhite: 0.06, alpha: 0.76).setFill()
        path.fill()
        NSColor(calibratedWhite: 1, alpha: 0.12).setStroke()
        path.lineWidth = 1
        path.stroke()

        let indicatorRect = CGRect(x: rect.minX + 16, y: rect.maxY - 26, width: 10, height: 10)
        let indicatorPath = NSBezierPath(ovalIn: indicatorRect)
        let indicatorColor = state.isRecording
            ? NSColor(calibratedWhite: 0.92, alpha: 1)
            : NSColor(calibratedWhite: 0.75, alpha: 1)
        indicatorColor.setFill()
        indicatorPath.fill()

        drawText(
            text: state.isRecording ? "Recording" : state.phase.capitalized,
            in: CGRect(x: rect.minX + 34, y: rect.maxY - 34, width: 140, height: 18),
            font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            color: NSColor.white
        )
        drawText(
            text: state.targetApp ?? "Action",
            in: CGRect(x: rect.maxX - 120, y: rect.maxY - 34, width: 96, height: 18),
            font: NSFont.systemFont(ofSize: 11, weight: .medium),
            color: NSColor(calibratedWhite: 1, alpha: 0.72),
            alignment: .right
        )
        if let current = state.stepCurrent, let total = state.stepTotal, total > 0 {
            drawText(
                text: "Step \(current)/\(total)",
                in: CGRect(x: rect.maxX - 120, y: rect.minY + 14, width: 96, height: 16),
                font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                color: NSColor(calibratedWhite: 1, alpha: 0.78),
                alignment: .right
            )
        }
        drawText(
            text: state.summary,
            in: CGRect(x: rect.minX + 16, y: rect.minY + 36, width: rect.width - 32, height: 20),
            font: NSFont.monospacedSystemFont(ofSize: 15, weight: .semibold),
            color: NSColor(calibratedWhite: 0.98, alpha: 1)
        )
        drawText(
            text: state.stepLabel ?? state.detail ?? phaseDetail(for: state),
            in: CGRect(x: rect.minX + 16, y: rect.minY + 14, width: rect.width - 32, height: 16),
            font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            color: NSColor(calibratedWhite: 1, alpha: 0.62)
        )
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
    private var window: NSWindow?
    private var overlayView: StageOverlayView?
    private var lastStateData: Data?

    init(stateFile: String, stopFile: String, replyFile: String?, debugLogPath: String?) {
        self.stateFile = stateFile
        self.stopFile = stopFile
        self.writer = ResponseWriter(replyFile: replyFile)
        self.logger = DebugLogger(path: debugLogPath)
    }

    func run() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        try refreshState(force: true)
        try writer.write(
            ActionHostResponse(
                status: "overlay-running",
                outputPath: nil,
                detail: String(ProcessInfo.processInfo.processIdentifier)
            )
        )
        while !FileManager.default.fileExists(atPath: stopFile) {
            do {
                try refreshState(force: false)
            } catch {
                logger.log("stage-overlay: refresh failed \(error.localizedDescription)")
            }

            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.12))
        }

        logger.log("stage-overlay: stop signal received")
        window?.orderOut(nil)
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

        if window == nil || window?.screen != screen {
            logger.log("stage-overlay: create window on screen \(screen.frame)")
            createWindow(screen: screen)
        }

        window?.setFrame(screen.frame, display: true)
        overlayView?.state = state
        window?.orderFrontRegardless()
        logger.log("stage-overlay: window ordered front viewport=\(viewportRect)")
    }

    private func createWindow(screen: NSScreen) {
        let window = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let overlayView = StageOverlayView(frame: CGRect(origin: .zero, size: screen.frame.size), screenFrame: screen.frame)
        window.contentView = overlayView
        self.window = window
        self.overlayView = overlayView
    }
}

func rectFromOptions(_ options: CommandOptions) throws -> CGRect {
    let x = Double(try options.required("x")) ?? 0
    let y = Double(try options.required("y")) ?? 0
    let width = Double(try options.required("width")) ?? 0
    let height = Double(try options.required("height")) ?? 0

    return CGRect(x: x, y: y, width: width, height: height)
}

func run(command: ActionHostCommand, options: CommandOptions, writer: ResponseWriter, logger: DebugLogger) async throws {
    switch command {
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
        try await MainActor.run {
            let controller = StageOverlayController(
                stateFile: stateFile,
                stopFile: stopFile,
                replyFile: replyFile,
                debugLogPath: debugLogPath
            )
            try controller.run()
        }
    case .recordAppWindow:
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
        let recorder = WindowRecorder(writer: writer, logger: logger)
        try await recorder.recordRegion(
            rect: rect,
            outputPath: outputPath,
            stopSignalPath: options.options["stop-file"],
            finishedSignalPath: options.options["finished-file"],
            fps: options.double("fps", default: 15),
            scale: options.double("scale", default: 1)
        )
    case .screenshotAppWindow:
        guard #available(macOS 14.0, *) else {
            throw ActionHostError.unsupportedOS("Window screenshots require macOS 14.0 or newer.")
        }

        let bundleId = try options.required("bundle-id")
        let outputPath = try options.required("output")
        try await captureAppWindowScreenshot(bundleId: bundleId, outputPath: outputPath, writer: writer)
    case .screenshotRegion:
        let outputPath = try options.required("output")
        let rect = try rectFromOptions(options)
        try await captureRegionScreenshot(rect: rect, outputPath: outputPath, writer: writer)
    case .activateApp:
        let bundleId = try options.required("bundle-id")
        try activateApplication(bundleId: bundleId)
        try writer.write(ActionHostResponse(status: "activated", outputPath: nil, detail: bundleId))
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
    case .setWindowFrame:
        let bundleId = try options.required("bundle-id")
        let rect = try rectFromOptions(options)
        try setWindowFrame(bundleId: bundleId, rect: rect)
        try writer.write(ActionHostResponse(status: "window-framed", outputPath: nil, detail: bundleId))
    }
}

@main
struct ActionHostMain {
    static func main() async {
        let options = CommandOptions(arguments: CommandLine.arguments)
        let writer = ResponseWriter(replyFile: options.options["reply-file"])
        let logger = DebugLogger(path: options.options["debug-log"])

        do {
            try await run(command: options.command, options: options, writer: writer, logger: logger)
        } catch {
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
            exit(1)
        }
    }
}
