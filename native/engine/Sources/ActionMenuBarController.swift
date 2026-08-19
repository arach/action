import AppKit
import SwiftUI

/// Lattices-style extra: template icon, left-click popover, right-click menu.
/// The popover is a switchboard for scenarios and recent takes, not a second Action.
@MainActor
final class ActionMenuBarController: NSObject, NSPopoverDelegate {
    static let shared = ActionMenuBarController()

    static let popoverWidth: CGFloat = 340
    static let popoverHeight: CGFloat = 372

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var contextMenu: NSMenu?
    private weak var model: ActionLauncherViewModel?

    var isPopoverShown: Bool {
        popover?.isShown == true
    }

    private override init() {
        super.init()
    }

    func start(model: ActionLauncherViewModel) {
        self.model = model
        guard statusItem == nil else { return }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = Self.templateIcon
            button.toolTip = "Action"
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }

        contextMenu = buildContextMenu()
    }

    func dismissPopover() {
        popover?.performClose(nil)
    }

    func warmUpPopover() {
        let popover = makePopover()
        _ = popover.contentViewController?.view
    }

    @objc
    private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent,
              let button = statusItem?.button else { return }

        if event.type == .rightMouseUp {
            contextMenu?.popUp(
                positioning: nil,
                at: NSPoint(x: 0, y: button.bounds.height + 4),
                in: button
            )
        } else if let popover, popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem?.button else { return }
        model?.refreshScenarios()
        model?.refreshSessions()
        let popover = makePopover()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func makePopover() -> NSPopover {
        if let popover { return popover }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.contentSize = NSSize(width: Self.popoverWidth, height: Self.popoverHeight)
        popover.delegate = self
        if let model {
            popover.contentViewController = NSHostingController(
                rootView: ActionMenuBarPopoverView(
                    model: model,
                    onDismiss: { [weak self] in self?.dismissPopover() }
                )
            )
        }
        self.popover = popover
        return popover
    }

    func popoverWillShow(_ notification: Notification) {
        model?.refreshScenarios()
        model?.refreshSessions()
    }

    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()

        addItem(to: menu, title: "Open Action", action: #selector(menuOpenHome), key: "")
        addItem(to: menu, title: "Scenarios", action: #selector(menuOpenScenarios), key: "")
        addItem(to: menu, title: "Runs", action: #selector(menuOpenRuns), key: "")
        addItem(to: menu, title: "Library", action: #selector(menuOpenLibrary), key: "")
        menu.addItem(.separator())
        addItem(to: menu, title: "Settings…", action: #selector(menuOpenSettings), key: ",")
        menu.addItem(.separator())
        addItem(to: menu, title: "Quit Action", action: #selector(menuQuit), key: "q")
        return menu
    }

    private func addItem(to menu: NSMenu, title: String, action: Selector, key: String) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    @objc private func menuOpenHome() { reveal(.home) }
    @objc private func menuOpenScenarios() { reveal(.scenarios) }
    @objc private func menuOpenRuns() { reveal(.runs) }
    @objc private func menuOpenLibrary() { reveal(.library) }
    @objc private func menuOpenSettings() { reveal(.settings) }

    @objc
    private func menuQuit() {
        NSApp.terminate(nil)
    }

    private func reveal(_ destination: ActionLauncherDestination) {
        dismissPopover()
        ActionLauncherController.shared.reveal(destination)
    }

    private static let templateIcon: NSImage = {
        let size: CGFloat = 18
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            let inset = NSRect(x: 2, y: 2, width: size - 4, height: size - 4)
            let field = NSBezierPath(roundedRect: inset, xRadius: 3.2, yRadius: 3.2)
            NSColor.black.withAlphaComponent(0.22).setFill()
            field.fill()
            field.lineWidth = 1
            NSColor.black.setStroke()
            field.stroke()

            let play = NSBezierPath()
            play.move(to: NSPoint(x: 7.2, y: 5.4))
            play.line(to: NSPoint(x: 7.2, y: 12.6))
            play.line(to: NSPoint(x: 13.4, y: 9.0))
            play.close()
            NSColor.black.setFill()
            play.fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}

struct ActionMenuBarPopoverView: View {
    @ObservedObject var model: ActionLauncherViewModel
    var onDismiss: () -> Void

    private let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            divider
            sectionLabel("Run")
            scenarioList
            divider
            sectionLabel("Recent runs")
            takeList
            Spacer(minLength: 0)
            divider
            footer
        }
        .frame(width: ActionMenuBarController.popoverWidth, height: ActionMenuBarController.popoverHeight)
        .background(StageHUDTheme.hudCanvas)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ActionSupervisionBrandMark(size: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text("Action")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(StageHUDTheme.hudPaper)
                Text(headerDetail)
                    .font(.system(size: 11))
                    .foregroundStyle(StageHUDTheme.hudMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            headerButton(systemName: "house") {
                open(.home)
            }
            .help("Open Action")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var headerDetail: String {
        let scenarioCount = model.scenarios.count
        let takeCount = model.recentSessions.count
        if model.isRunningGuidedDemo {
            return model.guidedDemoStatus
        }
        if scenarioCount == 0 && takeCount == 0 {
            return "Scenarios and takes"
        }
        let scenarioLabel = scenarioCount == 1 ? "1 scenario" : "\(scenarioCount) scenarios"
        let takeLabel = takeCount == 1 ? "1 run" : "\(takeCount) runs"
        return "\(scenarioLabel) · \(takeLabel)"
    }

    private var scenarioList: some View {
        VStack(spacing: 2) {
            if model.scenarios.isEmpty {
                emptyRow("No scenarios yet")
            } else {
                ForEach(Array(model.scenarios.prefix(4))) { scenario in
                    rowButton {
                        onDismiss()
                        model.runScenarioFromLauncher(scenario)
                        ActionLauncherController.shared.showMainWindow()
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(scenario.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(StageHUDTheme.hudPaper)
                                .lineLimit(1)
                            Text("\(scenario.steps.count) steps · \(scenario.targetAppName)")
                                .font(.system(size: 10))
                                .foregroundStyle(StageHUDTheme.hudMuted)
                                .lineLimit(1)
                        }
                    }
                    .disabled(model.isRunningGuidedDemo)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private var takeList: some View {
        Group {
            if model.recentSessions.isEmpty {
                emptyRow("No takes yet")
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(model.recentSessions.prefix(12))) { session in
                            rowButton {
                                onDismiss()
                                model.revealSessionInLauncher(session)
                                ActionLauncherController.shared.showMainWindow()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(session.displayTitle)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(StageHUDTheme.hudPaper)
                                            .lineLimit(1)
                                        Text(takeSubtitle(session))
                                            .font(.system(size: 10))
                                            .foregroundStyle(StageHUDTheme.hudMuted)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 6)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(StageHUDTheme.hudMuted)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Open Action") {
                open(.home)
            }
            .buttonStyle(ActionSupervisionSecondaryButtonStyle())

            Spacer(minLength: 8)

            Button("Quit") {
                onDismiss()
                NSApp.terminate(nil)
            }
            .buttonStyle(ActionSupervisionSecondaryButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(StageHUDTheme.hudMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    private func emptyRow(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12))
            .foregroundStyle(StageHUDTheme.hudMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
    }

    private func rowButton<Label: View>(
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button(action: action) {
            label()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func headerButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
        }
        .buttonStyle(ActionSupervisionIconButtonStyle())
        .accessibilityLabel("Open Action")
    }

    private var divider: some View {
        Rectangle()
            .fill(StageHUDTheme.hudPaper.opacity(0.10))
            .frame(height: 1)
    }

    private func takeSubtitle(_ session: ActionSessionSummary) -> String {
        var parts: [String] = [session.kind.rawValue]
        if !session.subtitle.isEmpty, session.subtitle != session.displayTitle {
            parts.append(session.subtitle)
        }
        if let date = session.finishedAt ?? session.startedAt {
            parts.append(relativeFormatter.localizedString(for: date, relativeTo: Date()))
        }
        return parts.joined(separator: " · ")
    }

    private func open(_ destination: ActionLauncherDestination) {
        onDismiss()
        ActionLauncherController.shared.reveal(destination)
    }
}
