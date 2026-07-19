import AppKit
import SwiftUI

// The panel window is grown by a transparent margin on every side so the card's
// soft drop shadow has room to render. The AppKit window shadow (which follows
// the rectangular window bounds, not the rounded card) stays off; this margin
// keeps the shape-aware SwiftUI shadow from being clipped to a hard rectangle.
private let actionSupervisionShadowMargin: CGFloat = 24

@MainActor
final class ActionSupervisionViewModel: ObservableObject {
    @Published var title: String = "Action Supervision"
    @Published var detail: String = "Supervisor stop · Cmd+Ctrl+. or Esc Esc"
    @Published var countLabel: String = "0 live"
    @Published var isMinimized: Bool = false

    var onStop: (() -> Void)?
    var onToggleMinimized: (() -> Void)?
}

struct ActionSupervisionView: View {
    @ObservedObject var model: ActionSupervisionViewModel

    var body: some View {
        Group {
            if model.isMinimized {
                minimizedBody
            } else {
                expandedBody
            }
        }
        .help("Drag to reposition. Use Stop to halt supervised Action sessions.")
    }

    private var expandedBody: some View {
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
                HStack(spacing: 8) {
                    Text(model.countLabel)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.7))

                    Button {
                        model.onToggleMinimized?()
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.86))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.white.opacity(0.10)))
                    }
                    .buttonStyle(.plain)
                    .help("Minimize supervision")
                }

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
                .shadow(color: Color.black.opacity(0.26), radius: 14, x: 0, y: 8)
        )
        .padding(actionSupervisionShadowMargin)
    }

    private var minimizedBody: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(red: 0.92, green: 0.20, blue: 0.19))
                .frame(width: 8, height: 8)

            Text(model.countLabel)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.86))

            Spacer(minLength: 4)

            Button {
                model.onToggleMinimized?()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.86))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Expand supervision")

            Button("STOP") {
                model.onStop?()
            }
            .buttonStyle(ActionSupervisionButtonStyle())
        }
        .padding(.horizontal, 12)
        .frame(width: 206, height: 44, alignment: .leading)
        .background(
            Capsule(style: .continuous)
                .fill(Color(red: 0.18, green: 0.04, blue: 0.05).opacity(0.96))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.09), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.26), radius: 13, x: 0, y: 7)
        )
        .padding(actionSupervisionShadowMargin)
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
    private enum OverlayLayout {
        // Window sizes include the transparent shadow margin on every side; the
        // visible card is inset by `margin` and reads at its card size.
        static let margin = actionSupervisionShadowMargin
        static let expandedSize = CGSize(width: 296 + margin * 2, height: 84 + margin * 2)
        static let minimizedSize = CGSize(width: 206 + margin * 2, height: 44 + margin * 2)
        static let edgeInset: CGFloat = 18
        static let frameDefaultsKey = "Action.SupervisionOverlay.Frame"
        static let minimizedDefaultsKey = "Action.SupervisionOverlay.Minimized"
    }

    private let writer: ResponseWriter
    private let logger: DebugLogger
    private let model = ActionSupervisionViewModel()
    private var window: StageHUDPanel?
    private var pollTimer: Timer?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var windowMoveObserver: NSObjectProtocol?
    private var lastEscapeTimestamp: Date?
    private var hasPositionedWindow = false
    private var isWindowPresented = false

    init(replyFile: String?, debugLogPath: String?) {
        self.writer = ResponseWriter(replyFile: replyFile)
        self.logger = DebugLogger(path: debugLogPath)
    }

    func run() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        ActionSupervisionRegistry.recordOverlayPID(ProcessInfo.processInfo.processIdentifier)
        model.isMinimized = UserDefaults.standard.bool(forKey: OverlayLayout.minimizedDefaultsKey)
        model.onStop = { [weak self] in
            self?.triggerStopAll(reason: "button")
        }
        model.onToggleMinimized = { [weak self] in
            self?.toggleMinimized()
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

        let size = currentWindowSize
        let window = StageHUDPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.level = actionHUDPanelLevel()
        window.isOpaque = false
        window.backgroundColor = .clear
        // The card draws its own shape-aware shadow. Leaving the AppKit window
        // shadow on would stack a hard rectangle behind the rounded silhouette.
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.isMovable = true
        window.isMovableByWindowBackground = true
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle, .transient]
        window.isReleasedWhenClosed = false
        let rootView = NSHostingView(rootView: ActionSupervisionView(model: model))
        rootView.frame = CGRect(origin: .zero, size: size)
        rootView.autoresizingMask = [.width, .height]
        window.contentView = rootView
        self.window = window
        windowMoveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.persistWindowFrame()
            }
        }
        positionWindow()
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

        refresh()
    }

    private func refresh() {
        let registrations = ActionSupervisionRegistry.activeRegistrations()
        guard !registrations.isEmpty else {
            shutdown()
            return
        }

        // Only publish when a value actually changes. The poll runs several
        // times a second; assigning unconditionally would fire objectWillChange
        // on every tick and churn the view — the source of the visible flicker.
        let detail = registrations.last?.detail ?? "Supervisor stop · Cmd+Ctrl+. or Esc Esc"
        let countLabel = registrations.count == 1 ? "1 live" : "\(registrations.count) live"
        if model.title != "Action Supervision" {
            model.title = "Action Supervision"
        }
        if model.detail != detail {
            model.detail = detail
        }
        if model.countLabel != countLabel {
            model.countLabel = countLabel
        }
        if !hasPositionedWindow {
            positionWindow()
        }

        let ownsVisibleControls = registrations.contains { $0.ownsVisibleControls == true }
        if ownsVisibleControls {
            if isWindowPresented {
                window?.orderOut(nil)
                isWindowPresented = false
            }
        } else if !isWindowPresented {
            window?.orderFrontRegardless()
            isWindowPresented = true
        }
    }

    private func positionWindow() {
        guard let window else {
            return
        }

        let screen = NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let size = currentWindowSize

        if let savedFrame = savedWindowFrame(size: size),
           visibleFrame.intersects(savedFrame.insetBy(dx: min(savedFrame.width - 24, 0), dy: min(savedFrame.height - 24, 0))) {
            window.setFrame(clamped(frame: savedFrame, to: visibleFrame), display: true)
            hasPositionedWindow = true
            return
        }

        // Offset by the transparent margin so the visible card — not the padded
        // window — sits `edgeInset` from the top-right corner.
        let cornerInset = OverlayLayout.edgeInset - OverlayLayout.margin
        let x = visibleFrame.maxX - size.width - cornerInset
        let y = visibleFrame.maxY - size.height - cornerInset
        window.setFrame(CGRect(origin: CGPoint(x: x, y: y), size: size), display: true)
        hasPositionedWindow = true
        persistWindowFrame()
    }

    private var currentWindowSize: CGSize {
        model.isMinimized ? OverlayLayout.minimizedSize : OverlayLayout.expandedSize
    }

    private func toggleMinimized() {
        model.isMinimized.toggle()
        UserDefaults.standard.set(model.isMinimized, forKey: OverlayLayout.minimizedDefaultsKey)
        resizeWindowForCurrentPresentation()
    }

    private func resizeWindowForCurrentPresentation() {
        guard let window else {
            return
        }

        let oldFrame = window.frame
        let size = currentWindowSize
        let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let resizedFrame = CGRect(
            x: oldFrame.minX,
            y: oldFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        window.setFrame(clamped(frame: resizedFrame, to: visibleFrame), display: true, animate: true)
        persistWindowFrame()
    }

    private func persistWindowFrame() {
        guard let window else {
            return
        }

        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: OverlayLayout.frameDefaultsKey)
    }

    private func savedWindowFrame(size: CGSize) -> CGRect? {
        guard let raw = UserDefaults.standard.string(forKey: OverlayLayout.frameDefaultsKey), !raw.isEmpty else {
            return nil
        }

        let saved = NSRectFromString(raw)
        guard saved.width > 0, saved.height > 0 else {
            return nil
        }

        return CGRect(origin: saved.origin, size: size)
    }

    private func clamped(frame: CGRect, to visibleFrame: CGRect) -> CGRect {
        let x = min(max(frame.minX, visibleFrame.minX + 8), visibleFrame.maxX - frame.width - 8)
        let y = min(max(frame.minY, visibleFrame.minY + 8), visibleFrame.maxY - frame.height - 8)
        return CGRect(x: x, y: y, width: frame.width, height: frame.height)
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
        if let windowMoveObserver {
            NotificationCenter.default.removeObserver(windowMoveObserver)
            self.windowMoveObserver = nil
        }
        window?.orderOut(nil)
        isWindowPresented = false
        ActionSupervisionRegistry.clearOverlayPID(ifOwnedBy: ProcessInfo.processInfo.processIdentifier)
        try? FileManager.default.removeItem(at: ActionSupervisionRegistry.overlayStopSignalURL)
        NSApplication.shared.terminate(nil)
    }
}
