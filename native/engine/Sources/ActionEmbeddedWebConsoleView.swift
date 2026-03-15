import SwiftUI

@MainActor
final class ActionEmbeddedWebConsoleBridge: ObservableObject {
    fileprivate weak var controller: ActionWebViewController?
    fileprivate var currentURL: URL?

    func load(_ url: URL) {
        currentURL = url
        controller?.load(url: url, reloadToken: UUID())
    }

    func reload() {
        guard let currentURL else { return }
        controller?.load(url: currentURL, reloadToken: UUID())
    }

    func showInspector() {
        controller?.showInspector()
    }
}

struct ActionEmbeddedWebConsoleView: NSViewControllerRepresentable {
    let url: URL
    @ObservedObject var bridge: ActionEmbeddedWebConsoleBridge
    let onStatusChange: (String) -> Void
    let onCommand: (ActionWebViewCommand) -> Void

    func makeNSViewController(context: Context) -> ActionWebViewController {
        let controller = ActionWebViewController()
        controller.onStatusChange = onStatusChange
        controller.onCommand = onCommand
        bridge.controller = controller
        bridge.currentURL = url
        controller.load(url: url, reloadToken: UUID())
        return controller
    }

    func updateNSViewController(_ controller: ActionWebViewController, context: Context) {
        controller.onStatusChange = onStatusChange
        controller.onCommand = onCommand
        bridge.controller = controller

        if bridge.currentURL != url {
            bridge.currentURL = url
            controller.load(url: url, reloadToken: UUID())
        }
    }
}
