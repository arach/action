import AppKit
import SwiftUI

@MainActor
final class ActionLauncherController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static let shared = ActionLauncherController()

    private var window: NSWindow?
    private var settingsWindow: NSWindow?
    private let viewModel = ActionLauncherViewModel()
    private var appearanceMode: ActionAppearanceMode {
        get { ActionAppearanceStore.shared.mode }
        set { ActionAppearanceStore.shared.mode = newValue }
    }

    func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.delegate = self
        applyAppearanceMode()
        configureMenu()
        showWindow()
        app.activate(ignoringOtherApps: true)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        viewModel.startAgent()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel.stopAgent()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showWindow()
        } else {
            window?.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        showWindow()
        for url in urls {
            viewModel.handleIncomingDeepLink(url)
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        NSApplication.shared.terminate(nil)
    }

    private func showWindow() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let rootView = ActionLauncherRootView(model: viewModel)
        let hostingView = NSHostingView(rootView: rootView)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1240, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Action"
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = false
        window.toolbarStyle = .unifiedCompact
        window.backgroundColor = NSColor.windowBackgroundColor
        window.tabbingMode = .disallowed
        window.center()
        window.setFrameAutosaveName("ActionLauncherWindow")
        window.contentView = hostingView
        window.appearance = appearanceMode.appearance
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    private func configureMenu() {
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Action"
        let mainMenu = NSMenu(title: "MainMenu")

        let appItem = NSMenuItem(title: appName, action: nil, keyEquivalent: "")
        let appMenu = NSMenu(title: appName)
        appMenu.addItem(
            withTitle: "About \(appName)",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Settings…",
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        appMenu.addItem(
            withTitle: "Open Embedded Console",
            action: #selector(openBrowserWindow),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Hide \(appName)",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        let hideOthers = NSMenuItem(
            title: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(
            withTitle: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit \(appName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(
            withTitle: "New Window",
            action: #selector(openNewWindow),
            keyEquivalent: "n"
        )
        fileMenu.addItem(
            withTitle: "Open Embedded Console",
            action: #selector(openBrowserWindow),
            keyEquivalent: "b"
        )
        fileMenu.addItem(
            withTitle: "Open Console in Browser",
            action: #selector(openConsoleInBrowser),
            keyEquivalent: ""
        )
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(
            withTitle: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        windowMenu.addItem(
            withTitle: "Zoom",
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        )
        windowMenu.addItem(.separator())
        windowMenu.addItem(
            withTitle: "Bring All to Front",
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        )
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        let app = NSApplication.shared
        app.mainMenu = mainMenu
        app.windowsMenu = windowMenu
        app.servicesMenu = NSMenu(title: "Services")
    }

    @objc
    private func openNewWindow() {
        showWindow()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc
    private func openBrowserWindow() {
        viewModel.openEmbeddedConsole()
    }

    @objc
    private func openConsoleInBrowser() {
        viewModel.openWebConsoleInBrowser()
    }

    @objc
    private func showAbout() {
        NSApplication.shared.orderFrontStandardAboutPanel(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc
    private func showSettings() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let content = NSHostingView(
            rootView: ActionSettingsRootView(
                appearanceMode: Binding(
                    get: { self.appearanceMode },
                    set: { [weak self] mode in
                        self?.setAppearanceMode(mode)
                    }
                )
            )
        )

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 460, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.center()
        window.contentView = content
        window.appearance = appearanceMode.appearance
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.makeKeyAndOrderFront(nil)
        self.settingsWindow = window
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func setAppearanceMode(_ mode: ActionAppearanceMode) {
        appearanceMode = mode
        viewModel.appearanceMode = mode
        applyAppearanceMode()
    }

    private func applyAppearanceMode() {
        NSApplication.shared.appearance = appearanceMode.appearance
        for window in NSApplication.shared.windows {
            window.appearance = appearanceMode.appearance
        }
    }

}
