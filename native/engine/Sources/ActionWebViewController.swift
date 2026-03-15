import AppKit
import WebKit
import OSLog

enum ActionWebViewCommand {
    case startLocalConsole
}

@MainActor
final class ActionWebViewController: NSViewController, WKNavigationDelegate {
    private let logger = Logger(subsystem: "dev.action.Action", category: "WebView")
    private let webView: WKWebView
    private var currentURL: URL?
    private var lastReloadToken: UUID?
    private var showingFallbackPage = false
    var onStatusChange: ((String) -> Void)?
    var onCommand: ((ActionWebViewCommand) -> Void)?
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
            showingFallbackPage = false
            report("Loading \(url.absoluteString)…")
            logger.notice("Loading URL: \(url.absoluteString, privacy: .public)")
            webView.load(URLRequest(url: url))
            return
        }

        if lastReloadToken != reloadToken {
            lastReloadToken = reloadToken
            showingFallbackPage = false
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
        showFallbackPageIfNeeded(for: currentURL, error: error)
        report("Load failed: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        logger.error("Provisional navigation failed: \(error.localizedDescription, privacy: .public)")
        showFallbackPageIfNeeded(for: currentURL, error: error)
        report("Load failed: \(error.localizedDescription)")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        logger.error("Web content process terminated")
        report("Web content process terminated")
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        if url.scheme == "action", url.host(percentEncoded: false) == "start-local-console" {
            onCommand?(.startLocalConsole)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    private func showFallbackPageIfNeeded(for url: URL?, error: Error) {
        guard let url,
              url.host(percentEncoded: false) == "127.0.0.1" || url.host(percentEncoded: false) == "localhost",
              url.port == 4318,
              !showingFallbackPage else {
            return
        }

        showingFallbackPage = true
        webView.loadHTMLString(localConsoleUnavailableHTML(url: url, error: error), baseURL: nil)
    }

    private func localConsoleUnavailableHTML(url: URL, error: Error) -> String {
        let escapedURL = url.absoluteString
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let escapedError = error.localizedDescription
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8" />
          <title>Local Console Unavailable</title>
          <style>
            :root {
              color-scheme: dark;
              --bg: #0b0e11;
              --panel: rgba(255,255,255,0.05);
              --border: rgba(255,255,255,0.10);
              --text: #f5f7fa;
              --muted: #9ca7b3;
              --accent: #f26f49;
            }
            * { box-sizing: border-box; }
            body {
              margin: 0;
              min-height: 100vh;
              display: grid;
              place-items: center;
              padding: 32px;
              background:
                radial-gradient(circle at top left, rgba(242,111,73,0.18), transparent 30%),
                radial-gradient(circle at bottom right, rgba(76,140,255,0.14), transparent 34%),
                var(--bg);
              color: var(--text);
              font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            }
            .panel {
              width: min(720px, 100%);
              padding: 24px;
              border-radius: 20px;
              background: var(--panel);
              border: 1px solid var(--border);
              backdrop-filter: blur(16px);
            }
            h1 {
              margin: 0 0 10px 0;
              font-size: 28px;
              line-height: 1.1;
            }
            p {
              margin: 0 0 14px 0;
              color: var(--muted);
              line-height: 1.5;
            }
            code, pre {
              font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
            }
            .callout {
              margin-top: 18px;
              padding: 14px 16px;
              border-radius: 14px;
              background: rgba(255,255,255,0.04);
              border: 1px solid var(--border);
            }
            .label {
              color: var(--accent);
              font-size: 12px;
              text-transform: uppercase;
              letter-spacing: 0.08em;
              margin-bottom: 8px;
            }
            pre {
              margin: 8px 0 0 0;
              white-space: pre-wrap;
              color: var(--text);
            }
            .cta {
              appearance: none;
              border: 0;
              border-radius: 12px;
              padding: 12px 14px;
              background: linear-gradient(90deg, #f26f49, #f48f52);
              color: #111;
              font-weight: 700;
              cursor: pointer;
              margin-top: 16px;
            }
          </style>
        </head>
        <body>
          <main class="panel">
            <h1>Local console is not running</h1>
            <p>Action tried to load <code>\(escapedURL)</code>, but nothing answered on that port.</p>
            <p>You can start it from here, or run a command manually from your dev shell.</p>
            <a href="action://start-local-console">
              <button class="cta">Start Local Console</button>
            </a>
            <div class="callout">
              <div class="label">Recommended</div>
              <pre>action-dev hud</pre>
            </div>
            <div class="callout">
              <div class="label">Fallback</div>
              <pre>bun run hud</pre>
            </div>
            <div class="callout">
              <div class="label">Load Error</div>
              <pre>\(escapedError)</pre>
            </div>
          </main>
        </body>
        </html>
        """
    }
}
