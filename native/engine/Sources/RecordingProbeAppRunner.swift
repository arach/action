import AppKit
import OSLog

@available(macOS 15.0, *)
@MainActor
final class RecordingProbeAppRunner: NSObject, NSApplicationDelegate, NSWindowDelegate {
    enum Target {
        case region(CGRect)
        case appWindow(String)
    }

    private static var retainedRunner: RecordingProbeAppRunner?

    struct Configuration {
        let target: Target
        let outputPath: String
        let stopSignalPath: String?
        let finishedSignalPath: String?
        let fps: Double
        let scale: Double
    }

    private let logger = Logger(subsystem: "dev.action.Action", category: "RecordingProbe")
    private let configuration: Configuration
    private let writer: ResponseWriter
    private let debugLogger: DebugLogger

    private var window: NSWindow?
    private var statusField: NSTextField?
    private let panicRegistrationID = "recording-probe-\(UUID().uuidString)"

    init(configuration: Configuration, writer: ResponseWriter, debugLogger: DebugLogger) {
        self.configuration = configuration
        self.writer = writer
        self.debugLogger = debugLogger
    }

    func run() {
        Self.retainedRunner = self
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = self
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerPanicStopIfNeeded()
        showWindow()
        startRecording()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        ActionPanicRegistry.unregister(id: panicRegistrationID)
        Self.retainedRunner = nil
    }

    func windowWillClose(_ notification: Notification) {
        NSApplication.shared.terminate(nil)
    }

    private func showWindow() {
        let root = NSView(frame: .zero)
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.clear.cgColor

        let window = NSWindow(
            contentRect: CGRect(x: -10_000, y: -10_000, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.contentView = root
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.orderFrontRegardless()

        self.window = window
        self.statusField = nil
    }

    private func startRecording() {
        let configuration = self.configuration
        let writer = self.writer
        let debugLogger = self.debugLogger

        report("Starting recording probe…")

        Task { [weak self] in
            let recorder = WindowRecorder(writer: writer, logger: debugLogger)

            do {
                switch configuration.target {
                case .region(let rect):
                    try await recorder.recordRegion(
                        rect: rect,
                        outputPath: configuration.outputPath,
                        stopSignalPath: configuration.stopSignalPath,
                        finishedSignalPath: configuration.finishedSignalPath,
                        fps: configuration.fps,
                        scale: configuration.scale
                    )
                case .appWindow(let bundleId):
                    try await recorder.recordAppWindow(
                        bundleId: bundleId,
                        outputPath: configuration.outputPath,
                        stopSignalPath: configuration.stopSignalPath,
                        finishedSignalPath: configuration.finishedSignalPath
                    )
                }

                self?.report("Finished: \(configuration.outputPath)")
                NSApplication.shared.terminate(nil)
            } catch {
                self?.report("Failed: \(error.localizedDescription)")
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func report(_ message: String) {
        statusField?.stringValue = message
        logger.notice("\(message, privacy: .public)")
    }

    private func registerPanicStopIfNeeded() {
        guard let stopSignalPath = configuration.stopSignalPath, !stopSignalPath.isEmpty else {
            return
        }

        do {
            try ActionPanicRegistry.register(
                id: panicRegistrationID,
                title: "Stop Recording",
                detail: "Recording probe",
                controlFile: nil,
                stopFile: stopSignalPath
            )
        } catch {
            logger.error("Failed to register panic stop: \(error.localizedDescription, privacy: .public)")
        }
    }
}
