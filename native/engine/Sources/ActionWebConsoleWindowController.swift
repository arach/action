import AppKit
import OSLog
import WebKit

@MainActor
final class ActionWebConsoleWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate {
    private let logger = Logger(subsystem: "dev.action.Action", category: "EmbeddedWeb")
    private let webView: WKWebView
    private let urlField: NSTextField
    private let statusLabel: NSTextField
    private var hasBootstrappedWebProcess = false
    private var pendingURLAfterBootstrap: URL?
    private var requestedURL: URL?
    var onStatusChange: (@MainActor (String) -> Void)?

    init(initialURL: URL = URL(string: "http://127.0.0.1:4318/")!) {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = nil
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }

        let urlField = NSTextField(string: initialURL.absoluteString)
        urlField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        urlField.usesSingleLineMode = true
        urlField.lineBreakMode = .byTruncatingMiddle

        let statusLabel = NSTextField(labelWithString: "Ready")
        statusLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor

        let loadButton = NSButton(title: "Load", target: nil, action: nil)
        loadButton.bezelStyle = .rounded
        loadButton.setButtonType(.momentaryPushIn)

        let toolbar = NSStackView(views: [urlField, loadButton])
        toolbar.orientation = .horizontal
        toolbar.spacing = 8
        toolbar.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 6, right: 12)

        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        [toolbar, statusLabel, webView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview($0)
        }

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: root.topAnchor),

            statusLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            statusLabel.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 4),

            webView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            webView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            webView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1240, height: 860),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Action Embedded Console"
        window.center()
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.managed, .fullScreenNone, .moveToActiveSpace]
        window.isReleasedWhenClosed = false
        window.contentView = root

        self.webView = webView
        self.urlField = urlField
        self.statusLabel = statusLabel
        super.init(window: window)
        self.webView.navigationDelegate = self
        loadButton.target = self
        loadButton.action = #selector(loadFromField)
        window.delegate = self
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowOcclusionDidChange(_:)),
            name: NSWindow.didChangeOcclusionStateNotification,
            object: window
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(url: URL) {
        logger.notice("show(url:) called with \(url.absoluteString, privacy: .public)")
        guard let window else {
            logger.error("window missing in show(url:)")
            return
        }

        urlField.stringValue = url.absoluteString
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.contentView?.layoutSubtreeIfNeeded()
        let isAttached = webView.window != nil
        let visibility = window.occlusionState.contains(.visible)
        logger.notice("webview-attached=\(isAttached, privacy: .public) window-visible=\(window.isVisible, privacy: .public) occlusion-visible=\(visibility, privacy: .public) occlusion-state=\(window.occlusionState.rawValue, privacy: .public)")
        requestedURL = url
        tryStartRequestedNavigation()
    }

    func reload() {
        webView.reload()
    }

    func currentURL() -> URL? {
        let text = urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return nil
        }
        return URL(string: text)
    }

    @objc
    private func loadFromField() {
        loadCurrentFieldURL()
    }

    private func loadCurrentFieldURL() {
        let raw = urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            setStatus("Invalid URL")
            return
        }
        guard let url = URL(string: raw) else {
            setStatus("Invalid URL: \(raw)")
            return
        }

        beginNavigation(to: url)
    }

    private func beginNavigation(to url: URL) {
        setStatus("Loading \(url.absoluteString)")
        logger.notice("Calling webView.load for \(url.absoluteString, privacy: .public)")
        webView.load(URLRequest(url: url))
    }

    private func tryStartRequestedNavigation() {
        guard let window, let requestedURL else {
            return
        }
        guard window.isVisible else {
            setStatus("Waiting for browser window…")
            return
        }
        guard window.occlusionState.contains(.visible) else {
            setStatus("Waiting for browser window to become visible…")
            return
        }

        self.requestedURL = nil
        if hasBootstrappedWebProcess {
            pendingURLAfterBootstrap = nil
            beginNavigation(to: requestedURL)
            return
        }

        pendingURLAfterBootstrap = requestedURL
        hasBootstrappedWebProcess = true
        setStatus("Bootstrapping WebKit process…")
        webView.loadHTMLString(
            """
            <!doctype html>
            <html>
            <head><meta charset="utf-8"><title>Action Bootstrap</title></head>
            <body style="font-family:-apple-system;padding:12px;">Bootstrapping WebKit…</body>
            </html>
            """,
            baseURL: nil
        )
    }

    private func setStatus(_ text: String) {
        statusLabel.stringValue = text
        onStatusChange?(text)
        logger.notice("status: \(text, privacy: .public)")
    }

    func windowWillClose(_ notification: Notification) {
        setStatus("Embedded console window closed")
    }

    @objc
    private func windowOcclusionDidChange(_ notification: Notification) {
        guard let window else {
            return
        }
        let visible = window.occlusionState.contains(.visible)
        logger.notice("window occlusion changed. visible=\(visible, privacy: .public) state=\(window.occlusionState.rawValue, privacy: .public)")
        if visible {
            tryStartRequestedNavigation()
        }
    }

    @objc
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        setStatus("Connecting...")
    }

    @objc
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        setStatus("Rendering...")
    }

    @objc
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let pendingURLAfterBootstrap {
            self.pendingURLAfterBootstrap = nil
            logger.notice("Bootstrap completed, loading pending URL \(pendingURLAfterBootstrap.absoluteString, privacy: .public)")
            beginNavigation(to: pendingURLAfterBootstrap)
            return
        }
        setStatus("Loaded: \(webView.url?.absoluteString ?? "(unknown)")")
    }

    @objc
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        setStatus("Load failed: \(error.localizedDescription)")
    }

    @objc
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        setStatus("Load failed: \(error.localizedDescription)")
    }

    @objc
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        setStatus("Web content process terminated")
    }
}
