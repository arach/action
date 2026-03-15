import AppKit
import WebKit
import OSLog

@MainActor
final class ActionWebViewController: NSViewController, WKNavigationDelegate {
    private let logger = Logger(subsystem: "dev.action.Action", category: "WebView")
    private let webView: WKWebView
    private var currentURL: URL?
    private var lastReloadToken: UUID?
    var onStatusChange: ((String) -> Void)?
    var currentReloadToken: UUID { lastReloadToken ?? UUID() }

    init() {
        let configuration = WKWebViewConfiguration()
        let preferences = WKPreferences()
        preferences.setValue(true, forKey: "developerExtrasEnabled")
        configuration.preferences = preferences

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsMagnification = true
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }

        self.webView = webView
        super.init(nibName: nil, bundle: nil)
        self.webView.navigationDelegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        self.view = container
    }

    func load(url: URL, reloadToken: UUID) {
        if currentURL != url {
            currentURL = url
            lastReloadToken = reloadToken
            report("Loading \(url.absoluteString)…")
            logger.notice("Loading URL: \(url.absoluteString, privacy: .public)")
            webView.load(URLRequest(url: url))
            return
        }

        if lastReloadToken != reloadToken {
            lastReloadToken = reloadToken
            report("Reloading \(url.absoluteString)…")
            logger.notice("Reloading URL: \(url.absoluteString, privacy: .public)")
            webView.reload()
        }
    }

    func reload() {
        guard let currentURL else {
            return
        }

        load(url: currentURL, reloadToken: UUID())
    }

    func showInspector() {
        let selector = NSSelectorFromString("_showWebInspector:")
        guard webView.responds(to: selector) else {
            report("Enable Safari Develop menu, then choose Develop > Action Browser")
            logger.error("Web Inspector selector unavailable")
            return
        }

        _ = webView.perform(selector, with: nil)
        report("Web Inspector requested")
    }

    private func report(_ status: String) {
        logger.notice("\(status, privacy: .public)")
        onStatusChange?(status)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        report("Connecting…")
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        report("Rendering…")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript(
            """
            JSON.stringify({
              title: document.title || "",
              readyState: document.readyState || "",
              bodyLength: document.body ? document.body.innerText.length : 0
            })
            """
        ) { [weak self] result, error in
            guard let self else {
                return
            }

            if let error {
                self.report("Loaded, JS probe failed: \(error.localizedDescription)")
                return
            }

            if let payload = result as? String {
                self.report("Loaded: \(payload)")
            } else {
                self.report("Loaded")
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        logger.error("Navigation failed: \(error.localizedDescription, privacy: .public)")
        report("Load failed: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        logger.error("Provisional navigation failed: \(error.localizedDescription, privacy: .public)")
        report("Load failed: \(error.localizedDescription)")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        logger.error("Web content process terminated")
        report("Web content process terminated")
    }
}
