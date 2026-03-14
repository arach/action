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
    case recordAppWindow = "record-app-window"
    case screenshotAppWindow = "screenshot-app-window"
}

enum ActionHostError: LocalizedError {
    case missingOption(String)
    case unsupportedOS(String)
    case windowNotFound(String)
    case unableToEncodeImage
    case missingOutputPath

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

    return PermissionSnapshot(
        accessibility: accessibility,
        screenRecording: screenRecording
    )
}

func printJSON(_ value: some Encodable) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([0x0a]))
}

func openSettingsPane(anchor: String) {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else {
        return
    }

    NSWorkspace.shared.open(url)
}

func shareableContent() async throws -> SCShareableContent {
    guard screenRecordingStatus() == .granted else {
        throw ActionHostError.unsupportedOS("Screen Recording permission has not been granted yet.")
    }

    return try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
}

func bestWindow(for bundleId: String) async throws -> SCWindow {
    let content = try await shareableContent()

    let candidates = content.windows.filter { window in
        window.owningApplication?.bundleIdentifier == bundleId && window.isOnScreen && window.windowLayer == 0
    }

    if let active = candidates.first(where: \.isActive) {
        return active
    }

    if let largest = candidates.max(by: { lhs, rhs in
        lhs.frame.width * lhs.frame.height < rhs.frame.width * rhs.frame.height
    }) {
        return largest
    }

    throw ActionHostError.windowNotFound(bundleId)
}

func pngData(from image: CGImage) -> Data? {
    let bitmap = NSBitmapImageRep(cgImage: image)
    return bitmap.representation(using: .png, properties: [:])
}

@available(macOS 15.0, *)
final class WindowRecorder: NSObject, SCRecordingOutputDelegate, SCStreamDelegate {
    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?

    func recordAppWindow(bundleId: String, outputPath: String) async throws {
        let outputURL = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let window = try await bestWindow(for: bundleId)
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        configuration.width = max(Int(window.frame.width), 1)
        configuration.height = max(Int(window.frame.height), 1)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.showsCursor = true
        configuration.showMouseClicks = true
        configuration.scalesToFit = true
        configuration.captureResolution = .automatic

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        let recordingConfiguration = SCRecordingOutputConfiguration()
        recordingConfiguration.outputURL = outputURL
        recordingConfiguration.outputFileType = .mp4
        recordingConfiguration.videoCodecType = .h264

        let recordingOutput = SCRecordingOutput(configuration: recordingConfiguration, delegate: self)
        try stream.addRecordingOutput(recordingOutput)

        self.stream = stream
        self.recordingOutput = recordingOutput

        try await stream.startCapture()
        try printJSON(ActionHostResponse(status: "recording", outputPath: outputPath, detail: nil))

        _ = try FileHandle.standardInput.readToEnd()

        try await stream.stopCapture()
        try printJSON(ActionHostResponse(status: "finished", outputPath: outputPath, detail: nil))
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        FileHandle.standardError.write(Data("ActionHost recording failed: \(error.localizedDescription)\n".utf8))
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        FileHandle.standardError.write(Data("ActionHost stream stopped: \(error.localizedDescription)\n".utf8))
    }
}

func captureAppWindowScreenshot(bundleId: String, outputPath: String) async throws {
    let outputURL = URL(fileURLWithPath: outputPath)
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )

    let window = try await bestWindow(for: bundleId)
    let filter = SCContentFilter(desktopIndependentWindow: window)
    let configuration = SCStreamConfiguration()
    configuration.width = max(Int(window.frame.width), 1)
    configuration.height = max(Int(window.frame.height), 1)
    configuration.showsCursor = true

    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    guard let data = pngData(from: image) else {
        throw ActionHostError.unableToEncodeImage
    }

    try data.write(to: outputURL)
    try printJSON(ActionHostResponse(status: "screenshot", outputPath: outputPath, detail: nil))
}

func run(command: ActionHostCommand, options: CommandOptions) async throws {
    switch command {
    case .status:
        try printJSON(snapshot(promptAccessibility: false, requestScreenRecordingPermission: false))
    case .request:
        try printJSON(snapshot(promptAccessibility: true, requestScreenRecordingPermission: true))
    case .openAccessibilitySettings:
        openSettingsPane(anchor: "Privacy_Accessibility")
    case .openScreenRecordingSettings:
        openSettingsPane(anchor: "Privacy_ScreenCapture")
    case .recordAppWindow:
        guard #available(macOS 15.0, *) else {
            throw ActionHostError.unsupportedOS("Window recording requires macOS 15.0 or newer.")
        }

        let bundleId = try options.required("bundle-id")
        let outputPath = try options.required("output")
        let recorder = WindowRecorder()
        try await recorder.recordAppWindow(bundleId: bundleId, outputPath: outputPath)
    case .screenshotAppWindow:
        guard #available(macOS 14.0, *) else {
            throw ActionHostError.unsupportedOS("Window screenshots require macOS 14.0 or newer.")
        }

        let bundleId = try options.required("bundle-id")
        let outputPath = try options.required("output")
        try await captureAppWindowScreenshot(bundleId: bundleId, outputPath: outputPath)
    }
}

@main
struct ActionHostMain {
    static func main() async {
        let options = CommandOptions(arguments: CommandLine.arguments)

        do {
            try await run(command: options.command, options: options)
        } catch {
            FileHandle.standardError.write(Data("ActionHost failed: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
