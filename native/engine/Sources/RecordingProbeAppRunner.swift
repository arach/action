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

    init(configuration: Configuration, writer: ResponseWriter, debugLogger: DebugLogger) {
        self.configuration = configuration
        self.writer = writer
        self.debugLogger = debugLogger
    }

    func run() {
        Self.retainedRunner = self
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.delegate = self
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        showWindow()
        startRecording()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        Self.retainedRunner = nil
    }

    func windowWillClose(_ notification: Notification) {
        NSApplication.shared.terminate(nil)
    }

    private func showWindow() {
        let statusField = NSTextField(labelWithString: "Preparing recording probe…")
        statusField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        statusField.textColor = .secondaryLabelColor
        statusField.lineBreakMode = .byTruncatingMiddle
        statusField.maximumNumberOfLines = 3
        statusField.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView(frame: .zero)
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        root.addSubview(statusField)

        NSLayoutConstraint.activate([
            statusField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            statusField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            statusField.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
        ])

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 520, height: 140),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Recording Probe"
        window.contentView = root
        window.center()
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)

        self.window = window
        self.statusField = statusField
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
}
