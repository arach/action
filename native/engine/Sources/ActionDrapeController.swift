import AppKit
import CoreGraphics
import Foundation

/// A flat color sheet. Action owns this so a take never writes the desktop picture.
///
/// Default level is `.normal`, ordered front. AXRaise the windows you want filmed
/// and they land above the sheet; everything else stays buried. Same level is what
/// makes AXRaise able to beat it. `--level desktop` sits under app windows instead.
/// `--space space` keeps the sheet on the current Space only.
final class ActionDrapeController: NSObject {
    private let color: NSColor
    private let levelMode: String
    private let spaceMode: String
    private let stopFile: String?
    private let parentProcessID: pid_t?
    private let lifetime: TimeInterval
    private let frames: [CGRect]
    private let writer: ResponseWriter
    private let logger: DebugLogger
    private var windows: [NSWindow] = []
    private var pollTimer: Timer?
    private var signalSources: [DispatchSourceSignal] = []

    init(options: CommandOptions) throws {
        self.writer = ResponseWriter(replyFile: options.options["reply-file"])
        self.logger = DebugLogger(path: options.options["debug-log"])
        self.color = try colorFromHex(options.options["color"] ?? "0e0d0a")
        self.levelMode = options.options["level"] ?? "normal"
        self.spaceMode = options.options["space"] ?? "drape"
        self.stopFile = options.options["stop-file"]
        self.parentProcessID = options.options["parent-pid"].flatMap { pid_t($0) }
        self.lifetime = options.double("seconds", default: 0)
        if let spec = options.options["bounds"] {
            self.frames = [try ActionDrapeController.parseBounds(spec)]
        } else {
            self.frames = NSScreen.screens.map(\.frame)
        }
    }

    func run() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        for frame in frames {
            let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.backgroundColor = color
            window.isOpaque = true
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false
            if levelMode == "desktop" {
                window.level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            } else {
                // Ordinary window level. Raise subjects and they sit above this.
                window.level = .normal
            }
            var behavior: NSWindow.CollectionBehavior = [.stationary, .ignoresCycle]
            if spaceMode != "space" {
                behavior.insert(.canJoinAllSpaces)
            }
            window.collectionBehavior = behavior
            window.orderFrontRegardless()
            windows.append(window)
        }

        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                self?.shutdown()
            }
            source.resume()
            signalSources.append(source)
        }

        if lifetime > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + lifetime) { [weak self] in
                self?.shutdown()
            }
        }

        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.tick()
        }
        pollTimer = timer
        RunLoop.main.add(timer, forMode: .common)

        try writer.write(
            ActionHostResponse(
                status: "drape-running",
                outputPath: nil,
                detail: String(ProcessInfo.processInfo.processIdentifier)
            )
        )
        logger.log("drape up: pid \(ProcessInfo.processInfo.processIdentifier) level=\(levelMode) space=\(spaceMode) windows=\(windows.count)")
        app.run()
    }

    private func tick() {
        if let stopFile, FileManager.default.fileExists(atPath: stopFile) {
            logger.log("drape: stop file received")
            shutdown()
            return
        }
        if let parentProcessID, kill(parentProcessID, 0) != 0 {
            logger.log("drape: parent \(parentProcessID) is gone, dismissing")
            shutdown()
        }
    }

    private func shutdown() {
        pollTimer?.invalidate()
        pollTimer = nil
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        NSApplication.shared.stop(nil)
    }

    /// Top-left origin, same space as screencapture and Action region recording.
    private static func parseBounds(_ spec: String) throws -> CGRect {
        let numbers = spec.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard numbers.count == 4 else {
            throw ActionHostError.missingOption("--bounds x,y,width,height")
        }
        let rect = CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
        let primary = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens[0]
        return CGRect(
            x: rect.minX,
            y: primary.frame.height - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}
