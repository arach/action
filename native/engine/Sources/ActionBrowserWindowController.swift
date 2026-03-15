import AppKit

@MainActor
final class ActionBrowserWindowController: NSWindowController, NSWindowDelegate {
    private let webController = ActionWebViewController()
    private let defaultFrame = CGRect(x: 0, y: 0, width: 1180, height: 820)
    var onStatusChange: ((String) -> Void)? {
        get { webController.onStatusChange }
        set { webController.onStatusChange = newValue }
    }
    var onCommand: ((ActionWebViewCommand) -> Void)? {
        get { webController.onCommand }
        set { webController.onCommand = newValue }
    }

    init() {
        let window = NSWindow(
            contentRect: defaultFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Action Embedded Console"
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.managed, .fullScreenNone, .moveToActiveSpace]
        window.center()
        window.contentViewController = webController

        super.init(window: window)
        window.delegate = self
        shouldCascadeWindows = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(url: URL, reload: Bool = false) {
        guard let window else {
            return
        }

        placeWindowOnActiveScreen(window)

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        showWindow(nil)
        window.orderFrontRegardless()
        window.makeMain()
        window.makeKey()
        NSApplication.shared.activate(ignoringOtherApps: true)
        onStatusChange?(
            "Browser window opened at \(Int(window.frame.origin.x)),\(Int(window.frame.origin.y)) size \(Int(window.frame.size.width))x\(Int(window.frame.size.height))"
        )
        webController.load(url: url, reloadToken: reload ? UUID() : webController.currentReloadToken)
        updateWindowTitle(with: url)
    }

    func reload() {
        webController.reload()
    }

    func showInspector() {
        webController.showInspector()
    }

    func updateWindowTitle(with url: URL) {
        window?.title = "Action Embedded Console - \(url.host(percentEncoded: false) ?? url.absoluteString)"
    }

    func windowWillClose(_ notification: Notification) {
        onStatusChange?("Browser window closed")
    }

    private func placeWindowOnActiveScreen(_ window: NSWindow) {
        let screen = NSApp.keyWindow?.screen ?? NSScreen.main ?? window.screen ?? NSScreen.screens.first
        guard let screen else {
            return
        }

        let visible = screen.visibleFrame
        let width = min(defaultFrame.width, visible.width - 40)
        let height = min(defaultFrame.height, visible.height - 40)
        let originX = visible.midX - (width / 2)
        let originY = visible.midY - (height / 2)
        let frame = CGRect(x: originX, y: originY, width: width, height: height)
        window.setFrame(frame, display: false)
    }
}
