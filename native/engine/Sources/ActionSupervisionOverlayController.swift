import AppKit
import SwiftUI

@MainActor
final class ActionSupervisionViewModel: ObservableObject {
    @Published var title: String = "Action Supervision"
    @Published var detail: String = "Supervisor stop · Cmd+Ctrl+. or Esc Esc"
    @Published var countLabel: String = "0 live"

    var onStop: (() -> Void)?
}

struct ActionSupervisionView: View {
    @ObservedObject var model: ActionSupervisionViewModel

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.title)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white)
                Text(model.detail)
                    .font(.system(size: 11, weight: .regular, design: .default))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .lineLimit(2)
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 8) {
                Text(model.countLabel)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.7))

                Button("STOP") {
                    model.onStop?()
                }
                .buttonStyle(ActionSupervisionButtonStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 296, height: 84, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.18, green: 0.04, blue: 0.05).opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.09), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.28), radius: 18, x: 0, y: 12)
        )
    }
}

struct ActionSupervisionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(red: 0.92, green: 0.20, blue: 0.19).opacity(configuration.isPressed ? 0.78 : 0.92))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

@MainActor
final class ActionSupervisionOverlayController: NSObject {
    private let writer: ResponseWriter
    private let logger: DebugLogger
    private let model = ActionSupervisionViewModel()
    private var window: StageHUDPanel?
    private var pollTimer: Timer?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var lastEscapeTimestamp: Date?

    init(replyFile: String?, debugLogPath: String?) {
        self.writer = ResponseWriter(replyFile: replyFile)
        self.logger = DebugLogger(path: debugLogPath)
    }

    func run() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        ActionSupervisionRegistry.recordOverlayPID(ProcessInfo.processInfo.processIdentifier)
        model.onStop = { [weak self] in
            self?.triggerStopAll(reason: "button")
        }
        try writer.write(
            ActionHostResponse(
                status: "supervision-overlay-running",
                outputPath: nil,
                detail: String(ProcessInfo.processInfo.processIdentifier)
            )
        )
        createWindow()
        startPolling()
        startKeyboardMonitoring()
        refresh()
        app.run()
    }

    private func createWindow() {
        guard window == nil else {
            return
        }

        let size = CGSize(width: 296, height: 84)
        let window = StageHUDPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.level = actionHUDPanelLevel()
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.ignoresMouseEvents = false
        window.isMovable = false
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle, .transient]
        window.isReleasedWhenClosed = false
        let rootView = NSHostingView(rootView: ActionSupervisionView(model: model))
        rootView.frame = CGRect(origin: .zero, size: size)
        rootView.autoresizingMask = [.width, .height]
        window.contentView = rootView
        self.window = window
    }

    private func startPolling() {
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        pollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func startKeyboardMonitoring() {
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleKeyEvent(event)
            }
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
            return event
        }
    }

    private func tick() {
        if FileManager.default.fileExists(atPath: ActionSupervisionRegistry.overlayStopSignalURL.path) {
            shutdown()
            return
        }

        window?.orderFrontRegardless()
        refresh()
    }

    private func refresh() {
        let registrations = ActionSupervisionRegistry.activeRegistrations()
        guard !registrations.isEmpty else {
            shutdown()
            return
        }

        let detail = registrations.last?.detail ?? "Supervisor stop · Cmd+Ctrl+. or Esc Esc"
        model.title = "Action Supervision"
        model.detail = detail
        model.countLabel = registrations.count == 1 ? "1 live" : "\(registrations.count) live"
        positionWindow()
        window?.orderFrontRegardless()
    }

    private func positionWindow() {
        guard let window else {
            return
        }

        let screen = NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let width: CGFloat = 296
        let height: CGFloat = 84
        let x = visibleFrame.maxX - width - 18
        let y = visibleFrame.maxY - height - 18
        window.setFrame(CGRect(x: x, y: y, width: width, height: height), display: true)
    }

    private func handleKeyEvent(_ event: NSEvent) {
        if isSupervisorShortcut(event) {
            triggerStopAll(reason: "shortcut")
        }
    }

    private func isSupervisorShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let characters = event.charactersIgnoringModifiers ?? ""
        if flags.contains([.command, .control]), characters == "." {
            return true
        }

        if event.keyCode == 53 {
            let timestamp = Date()
            if let lastEscapeTimestamp,
               timestamp.timeIntervalSince(lastEscapeTimestamp) < 0.45 {
                self.lastEscapeTimestamp = nil
                return true
            }
            self.lastEscapeTimestamp = timestamp
            return false
        }

        lastEscapeTimestamp = nil
        return false
    }

    private func triggerStopAll(reason: String) {
        let count = ActionSupervisionRegistry.triggerStopAll()
        logger.log("supervision-overlay: triggered stop count=\(count) reason=\(reason)")
        model.detail = count > 0
            ? "Sent stop to \(count) live session\(count == 1 ? "" : "s")."
            : "No live Action sessions were registered."
    }

    private func shutdown() {
        pollTimer?.invalidate()
        pollTimer = nil
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        window?.orderOut(nil)
        ActionSupervisionRegistry.clearOverlayPID()
        try? FileManager.default.removeItem(at: ActionSupervisionRegistry.overlayStopSignalURL)
        NSApplication.shared.stop(nil)
    }
}
