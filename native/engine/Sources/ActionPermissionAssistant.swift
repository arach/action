import ActionCore
import AppKit
import ApplicationServices
import CoreGraphics
import SwiftUI

/// Which signed app the user should drag into a macOS privacy list.
enum ActionPermissionTarget: String, Identifiable {
    case host
    case agent

    var id: String { rawValue }

    var process: ActionPermissionProcess {
        switch self {
        case .host: return .host
        case .agent: return .agent
        }
    }

    var displayName: String { process.displayName }
    var subtitle: String { process.subtitle }
    var bundleIdentifier: String { process.bundleIdentifier }

    var appURL: URL {
        switch self {
        case .host:
            return Bundle.main.bundleURL
        case .agent:
            return actionAgentHelperAppURL() ?? Bundle.main.bundleURL
        }
    }
}

/// Utility panel that can become key so AppKit file-drag sessions are not swallowed.
private final class ActionPermissionAssistantPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Talkie-style helper: open the privacy pane, then float a drag tile of the
/// current signed app next to System Settings so the user can drop it into
/// Screen Recording (or Accessibility) and toggle it on.
@MainActor
final class ActionPermissionAssistant {
    static let shared = ActionPermissionAssistant()

    private var panel: NSPanel?

    private init() {}

    func present(
        target: ActionPermissionTarget,
        permission: ActionPermissionKind,
        isGranted: @escaping () async -> Bool,
        openSettings: Bool = true
    ) {
        if openSettings {
            actionOpenPrivacySettings(for: permission)
        }

        let content = ActionPermissionAssistantView(
            target: target,
            permission: permission,
            isGranted: isGranted,
            onOpenSettings: { actionOpenPrivacySettings(for: permission) },
            onRevealApp: { Self.reveal(target.appURL) },
            onRelaunch: { Self.quitAndRelaunch() },
            onClose: { [weak self] in self?.close() }
        )

        let existingPanel: NSPanel
        if let panel {
            panel.title = "\(permission.title) Setup"
            panel.contentViewController = NSHostingController(rootView: content)
            existingPanel = panel
        } else {
            let panel = ActionPermissionAssistantPanel(
                contentRect: NSRect(x: 0, y: 0, width: 430, height: 286),
                styleMask: [.titled, .closable, .utilityWindow, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.title = "\(permission.title) Setup"
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isMovableByWindowBackground = false
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = false
            panel.acceptsMouseMovedEvents = true
            panel.level = actionHUDPanelLevel()
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            panel.backgroundColor = NSColor(StageHUDTheme.appBackground)
            panel.contentViewController = NSHostingController(rootView: content)
            panel.setContentSize(NSSize(width: 430, height: 286))
            self.panel = panel
            existingPanel = panel
        }

        Task { @MainActor [weak self] in
            let didActivate: Bool
            if openSettings {
                didActivate = await Self.waitForSystemSettingsFrontmost(
                    timeout: permission == .screenRecording ? 6.0 : 30.0
                )
            } else {
                didActivate = true
            }

            // Accessibility uses the system prompt to open Settings. If the
            // user dismisses it, do not leave a helper hovering. Screen
            // Recording on current macOS often never prompts, so we opened
            // Settings ourselves and still show the drag tile if the pane
            // did not come forward in time.
            if permission == .accessibility && openSettings && !didActivate {
                return
            }

            guard let self else { return }
            self.position(existingPanel)
            NSApp.activate(ignoringOtherApps: true)
            existingPanel.orderFrontRegardless()
            existingPanel.makeKey()
        }
    }

    func close() {
        panel?.orderOut(nil)
    }

    private static func waitForSystemSettingsFrontmost(timeout: TimeInterval) async -> Bool {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if let app = NSWorkspace.shared.frontmostApplication, isSystemSettings(app) {
                return true
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        return false
    }

    private static func isSystemSettings(_ app: NSRunningApplication) -> Bool {
        switch app.bundleIdentifier {
        case "com.apple.systempreferences", "com.apple.SystemSettings":
            return true
        default:
            return app.localizedName == "System Settings"
        }
    }

    private static func quitAndRelaunch() {
        let appURL = Bundle.main.bundleURL
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = [
            "-c",
            "/bin/sleep 1; /usr/bin/open -n \"\(appURL.path)\"",
        ]
        try? task.run()
        NSApp.terminate(nil)
    }

    private static func reveal(_ appURL: URL) {
        if FileManager.default.fileExists(atPath: appURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([appURL])
        }
    }

    private func position(_ panel: NSPanel) {
        let size = CGSize(
            width: max(panel.frame.width, 430),
            height: max(panel.frame.height, 235)
        )

        let anchor = Self.systemSettingsWindowBounds()
            ?? Self.largestCurrentAppWindowBounds(excluding: panel)

        guard let anchor else {
            positionOnMainScreen(panel, size: size)
            return
        }

        let displayBounds = Self.displayBounds(containing: anchor)
            ?? Self.displayBounds(containing: CGPoint(x: anchor.midX, y: anchor.midY))
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)

        let margin: CGFloat = 16
        let gap: CGFloat = 12
        let centeredX = anchor.midX - size.width / 2
        let centeredY = anchor.midY - size.height / 2
        let x: CGFloat
        let y: CGFloat

        if anchor.maxY + gap + size.height <= displayBounds.maxY - margin {
            x = clamp(centeredX, min: displayBounds.minX + margin, max: displayBounds.maxX - size.width - margin)
            y = anchor.maxY + gap
        } else if anchor.minY - gap - size.height >= displayBounds.minY + margin {
            x = clamp(centeredX, min: displayBounds.minX + margin, max: displayBounds.maxX - size.width - margin)
            y = anchor.minY - gap - size.height
        } else if anchor.maxX + gap + size.width <= displayBounds.maxX - margin {
            x = anchor.maxX + gap
            y = clamp(centeredY, min: displayBounds.minY + margin, max: displayBounds.maxY - size.height - margin)
        } else if anchor.minX - gap - size.width >= displayBounds.minX + margin {
            x = anchor.minX - gap - size.width
            y = clamp(centeredY, min: displayBounds.minY + margin, max: displayBounds.maxY - size.height - margin)
        } else {
            x = clamp(centeredX, min: displayBounds.minX + margin, max: displayBounds.maxX - size.width - margin)
            y = displayBounds.maxY - size.height - margin
        }

        let topLeft = CGPoint(x: x, y: y)
        let origin = CGPoint(
            x: topLeft.x,
            y: displayBounds.maxY - (topLeft.y - displayBounds.minY) - size.height
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func positionOnMainScreen(_ panel: NSPanel, size: CGSize) {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = screenFrame.maxX - size.width - 32
        let y = screenFrame.maxY - size.height - 72
        panel.setFrame(
            NSRect(
                x: max(screenFrame.minX + 16, x),
                y: max(screenFrame.minY + 16, y),
                width: size.width,
                height: size.height
            ),
            display: true
        )
    }

    private static func systemSettingsWindowBounds() -> CGRect? {
        visibleWindowBounds {
            ($0[kCGWindowOwnerName as String] as? String) == "System Settings"
        }
    }

    private static func largestCurrentAppWindowBounds(excluding panel: NSPanel) -> CGRect? {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        return visibleWindowBounds {
            guard let ownerPID = ($0[kCGWindowOwnerPID as String] as? NSNumber)?.intValue,
                  ownerPID == currentPID else { return false }
            guard let bounds = windowBounds(from: $0), bounds.width > panel.frame.width + 40 else { return false }
            return true
        }
    }

    private static func visibleWindowBounds(where matches: (NSDictionary) -> Bool) -> CGRect? {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [NSDictionary] else {
            return nil
        }

        return windows
            .filter { matches($0) }
            .compactMap(windowBounds(from:))
            .filter { $0.width > 100 && $0.height > 100 }
            .max { $0.width * $0.height < $1.width * $1.height }
    }

    private static func windowBounds(from info: NSDictionary) -> CGRect? {
        guard let dictionary = info[kCGWindowBounds as String] as? NSDictionary else {
            return nil
        }
        return CGRect(dictionaryRepresentation: dictionary)
    }

    private static func displayBounds(containing rect: CGRect) -> CGRect? {
        displayBounds(containing: CGPoint(x: rect.midX, y: rect.midY))
    }

    private static func displayBounds(containing point: CGPoint) -> CGRect? {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &displays, &count)
        return displays.map(CGDisplayBounds).first { $0.contains(point) }
    }

    private func clamp(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        Swift.max(minimum, Swift.min(value, maximum))
    }
}

@MainActor
private struct ActionPermissionAssistantView: View {
    let target: ActionPermissionTarget
    let permission: ActionPermissionKind
    let isGranted: () async -> Bool
    let onOpenSettings: () -> Void
    let onRevealApp: () -> Void
    let onRelaunch: () -> Void
    let onClose: () -> Void

    @State private var granted = false
    @State private var isRechecking = false
    @ObservedObject private var themeStore = ActionThemeStore.shared

    private var appIcon: NSImage {
        NSWorkspace.shared.icon(forFile: target.appURL.path)
    }

    private var headline: String {
        switch permission {
        case .accessibility:
            return "Add \(target.displayName) to Accessibility"
        case .screenRecording:
            return "Enable Screen Recording for \(target.displayName)"
        }
    }

    private var hint: String {
        switch permission {
        case .accessibility:
            return "Drag this app into the Accessibility list, or toggle it if it is already listed."
        case .screenRecording:
            return "If \(target.displayName) is not listed, drag it into Screen Recording. Toggle it on, then click Quit & Relaunch."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: permission.iconName)
                    .font(ActionIcon.large)
                    .foregroundStyle(granted ? StageHUDTheme.runOk : StageHUDTheme.hudAmber)
                    .frame(width: 30, height: 30)
                    .background((granted ? StageHUDTheme.runOk : StageHUDTheme.hudAmber).opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(headline)
                        .font(ActionType.uiBodyStrong)
                        .foregroundStyle(StageHUDTheme.textPrimary)
                    Text(hint)
                        .font(ActionType.uiCaption)
                        .foregroundStyle(StageHUDTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Label(statusText, systemImage: statusIcon)
                    .font(ActionType.uiMicro)
                    .foregroundStyle(granted ? StageHUDTheme.runOk : StageHUDTheme.textMuted)
            }

            HStack(alignment: .center, spacing: 14) {
                NativeActionAppDragTile(
                    appURL: target.appURL,
                    appIcon: appIcon,
                    permissionName: permission.title,
                    isDragEnabled: !granted,
                    onDragCompleted: {
                        Task { await refreshStatus() }
                    }
                )
                .frame(width: 92, height: 92)

                VStack(alignment: .leading, spacing: 4) {
                    Text(target.displayName)
                        .font(ActionType.uiBodyStrong)
                        .foregroundStyle(StageHUDTheme.textPrimary)
                    Text(target.subtitle)
                        .font(ActionType.uiCaption)
                        .foregroundStyle(StageHUDTheme.textMuted)
                    Text(target.bundleIdentifier)
                        .font(ActionType.mono(10))
                        .foregroundStyle(StageHUDTheme.textSecondary)
                        .textSelection(.enabled)
                    Text(target.appURL.path)
                        .font(ActionType.mono(9))
                        .foregroundStyle(StageHUDTheme.textMuted)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button("Open \(permission.title)", systemImage: "gearshape") {
                    onOpenSettings()
                }

                Button("Reveal App", systemImage: "folder") {
                    onRevealApp()
                }

                Spacer()

                if permission.requiresRelaunch {
                    Button("Quit & Relaunch", systemImage: "arrow.clockwise.circle") {
                        onRelaunch()
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Quit Action and reopen it so the new Screen Recording permission takes effect.")
                }

                Button(granted ? "Done" : "Close") {
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
            }
            .buttonStyle(.bordered)
            .font(ActionType.uiCaption)
        }
        .padding(16)
        .frame(width: 430)
        .background(StageHUDTheme.appBackground)
        .id(themeStore.revision)
        .task(id: "\(target.id)-\(permission.rawValue)") {
            while !Task.isCancelled {
                await refreshStatus()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private var statusText: String {
        if granted { return "Granted" }
        if isRechecking { return "Checking" }
        return "Waiting"
    }

    private var statusIcon: String {
        if granted { return "checkmark.circle.fill" }
        if isRechecking { return "arrow.clockwise" }
        return "arrow.down.app"
    }

    private func refreshStatus() async {
        isRechecking = true
        granted = await isGranted()
        isRechecking = false
    }
}

private struct NativeActionAppDragTile: NSViewRepresentable {
    let appURL: URL
    let appIcon: NSImage
    let permissionName: String
    var isDragEnabled: Bool = true
    var onDragCompleted: () -> Void = {}

    func makeNSView(context: Context) -> NativeActionAppDragTileView {
        NativeActionAppDragTileView(
            appURL: appURL,
            appIcon: appIcon,
            permissionName: permissionName,
            isDragEnabled: isDragEnabled,
            onDragCompleted: onDragCompleted
        )
    }

    func updateNSView(_ nsView: NativeActionAppDragTileView, context: Context) {
        nsView.appURL = appURL
        nsView.appIcon = appIcon
        nsView.permissionName = permissionName
        nsView.isDragEnabled = isDragEnabled
        nsView.onDragCompleted = onDragCompleted
    }
}

/// System Settings only accepts an app-bundle file URL written by `NSURL`.
final class NativeActionAppDragTileView: NSView, NSDraggingSource {
    var appURL: URL {
        didSet { updateToolTip(); needsDisplay = true }
    }
    var appIcon: NSImage {
        didSet { needsDisplay = true }
    }
    var permissionName: String {
        didSet { updateToolTip() }
    }
    var isDragEnabled: Bool {
        didSet { updateToolTip(); discardCursorRects(); needsDisplay = true }
    }
    var onDragCompleted: () -> Void

    private var dragStartLocation: NSPoint?
    private var isDragging = false
    private let dragThreshold: CGFloat = 4

    init(
        appURL: URL,
        appIcon: NSImage,
        permissionName: String,
        isDragEnabled: Bool,
        onDragCompleted: @escaping () -> Void
    ) {
        self.appURL = appURL
        self.appIcon = appIcon
        self.permissionName = permissionName
        self.isDragEnabled = isDragEnabled
        self.onDragCompleted = onDragCompleted
        super.init(frame: .zero)
        updateToolTip()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let amber = NSColor(calibratedRed: 0.96, green: 0.65, blue: 0.14, alpha: isDragEnabled ? 1.0 : 0.42)
        let fill = NSColor(calibratedWhite: 0.08, alpha: 0.96)
        let cardRect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: 7, yRadius: 7)

        fill.setFill()
        cardPath.fill()

        let iconSize = min(bounds.width, bounds.height) * 0.50
        let iconRect = NSRect(
            x: (bounds.width - iconSize) / 2,
            y: 15,
            width: iconSize,
            height: iconSize
        )
        appIcon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: isDragEnabled ? 1.0 : 0.45)

        if let symbol = NSImage(
            systemSymbolName: isDragEnabled ? "hand.draw" : "checkmark.circle.fill",
            accessibilityDescription: isDragEnabled ? "Drag" : "Granted"
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)) {
            let symbolSize = NSSize(width: 17, height: 17)
            let symbolRect = NSRect(
                x: (bounds.width - symbolSize.width) / 2,
                y: iconRect.maxY + 5,
                width: symbolSize.width,
                height: symbolSize.height
            )
            symbol.isTemplate = true
            amber.set()
            symbol.draw(in: symbolRect)
        }

        drawStatusLabel(isDragEnabled ? "DRAG ME" : "GRANTED", color: amber)

        var dash: [CGFloat] = [5, 4]
        cardPath.setLineDash(&dash, count: dash.count, phase: 0)
        cardPath.lineWidth = isDragEnabled ? 1.2 : 1.0
        amber.withAlphaComponent(isDragEnabled ? 0.72 : 0.35).setStroke()
        cardPath.stroke()
    }

    private func drawStatusLabel(_ label: String, color: NSColor) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let labelFont = NSFont.monospacedSystemFont(ofSize: 8.5, weight: .semibold)
        let attributed = NSAttributedString(
            string: label,
            attributes: [
                .font: labelFont,
                .foregroundColor: color,
                .paragraphStyle: paragraphStyle,
            ]
        )
        attributed.draw(
            in: NSRect(x: 0, y: bounds.height - 20, width: bounds.width, height: 12)
        )
    }

    override func mouseDown(with event: NSEvent) {
        guard isDragEnabled else { return }
        window?.makeKey()
        _ = window?.makeFirstResponder(self)
        dragStartLocation = convert(event.locationInWindow, from: nil)
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragEnabled, !isDragging, let startLocation = dragStartLocation else { return }
        let currentLocation = convert(event.locationInWindow, from: nil)
        let dx = currentLocation.x - startLocation.x
        let dy = currentLocation.y - startLocation.y
        guard sqrt(dx * dx + dy * dy) >= dragThreshold else { return }
        startDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        dragStartLocation = nil
        isDragging = false
    }

    override func resetCursorRects() {
        if isDragEnabled {
            addCursorRect(bounds, cursor: .openHand)
        }
    }

    private func startDrag(with event: NSEvent) {
        isDragging = true
        dragStartLocation = nil

        let draggingItem = NSDraggingItem(pasteboardWriter: appURL as NSURL)
        let imageSize = NSSize(width: 64, height: 64)
        let imageFrame = NSRect(
            x: bounds.midX - imageSize.width / 2,
            y: bounds.midY - imageSize.height / 2,
            width: imageSize.width,
            height: imageSize.height
        )
        draggingItem.setDraggingFrame(imageFrame, contents: appIcon)

        let session = beginDraggingSession(with: [draggingItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        isDragging = false
        dragStartLocation = nil
        onDragCompleted()
    }

    private func updateToolTip() {
        toolTip = isDragEnabled
            ? "Drag \(appURL.lastPathComponent) into \(permissionName)"
            : "\(permissionName) is enabled"
    }
}
