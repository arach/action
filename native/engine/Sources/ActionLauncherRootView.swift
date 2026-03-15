import SwiftUI

struct ActionLauncherRootView: View {
    @ObservedObject var model: ActionLauncherViewModel

    var body: some View {
        HStack(spacing: 0) {
            utilityRail
                .frame(width: 320)
                .background(railBackground)

            Divider()
                .overlay(Color.white.opacity(0.06))

            browserSummaryPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(consoleBackground)
        }
        .frame(minWidth: 1180, minHeight: 760)
        .background(Color(red: 0.04, green: 0.05, blue: 0.07))
    }

    private var utilityRail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Action")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(StageHUDTheme.textPrimary)

                    Text("Native launcher for staging, utilities, and quick access to the console.")
                        .font(.system(size: 13, weight: .regular, design: .default))
                        .foregroundStyle(StageHUDTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("UI stays in AppKit. Runtime capability is moving behind a local agent.")
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .foregroundStyle(StageHUDTheme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                utilityCard(title: "Utilities") {
                    VStack(spacing: 10) {
                        launcherButton("Refresh Permissions", action: model.refreshPermissions)
                        launcherButton("Request Permissions", action: model.requestPermissions)
                        launcherButton("Open Accessibility", action: model.openAccessibilitySettings)
                        launcherButton("Open Screen Recording", action: model.openScreenRecordingSettings)
                    }
                }

                utilityCard(title: "Runtime") {
                    VStack(alignment: .leading, spacing: 10) {
                        statusRow(label: "Agent", value: model.agentStatus)
                    }
                }

                utilityCard(title: "Scenes") {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("calculator-demo")
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundStyle(StageHUDTheme.textPrimary)
                            Text("Current bundled scenario. More scene controls can land here next.")
                                .font(.system(size: 12, weight: .regular, design: .default))
                                .foregroundStyle(StageHUDTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        launcherButton("Open Scenarios Folder", action: model.openScenariosFolder)
                    }
                }

                utilityCard(title: "Web View") {
                    VStack(spacing: 10) {
                        launcherButton("Open Embedded Console", action: model.openBrowserWindow)
                        launcherButton("Load Apple.com", action: model.showDemoSite)
                        launcherButton("Load Local Console", action: model.showLocalConsole)
                        launcherButton("Reload Embedded Console", action: model.reloadConsole)
                        launcherButton("Open Current URL in Browser", action: model.openWebConsoleInBrowser)
                    }
                }

                utilityCard(title: "Permissions") {
                    VStack(alignment: .leading, spacing: 10) {
                        statusRow(label: "Accessibility", value: model.accessibilityStatus)
                        statusRow(label: "Screen Recording", value: model.screenRecordingStatus)

                        if !model.notes.isEmpty {
                            Divider()
                                .overlay(Color.white.opacity(0.06))

                            ForEach(model.notes, id: \.self) { note in
                                Text(note)
                                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                                    .foregroundStyle(StageHUDTheme.textMuted)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
    }

    private var browserSummaryPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Browser Window")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(StageHUDTheme.textPrimary)

                Text("Embedded WebKit is enabled with the same minimal AppKit pattern proven in the tutorial app: one window, one web view, one URL field.")
                    .font(.system(size: 14, weight: .regular, design: .default))
                    .foregroundStyle(StageHUDTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            utilityCard(title: "Current Target") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(model.consoleURL.absoluteString)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(StageHUDTheme.textPrimary)
                        .textSelection(.enabled)

                    Text(model.consoleStatus)
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .foregroundStyle(StageHUDTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(28)
    }

    private var railBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.09, green: 0.10, blue: 0.13),
                Color(red: 0.06, green: 0.07, blue: 0.09),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var consoleBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.06, blue: 0.08),
                Color(red: 0.04, green: 0.05, blue: 0.07),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func utilityCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(StageHUDTheme.textMuted)

            content()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private func statusRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .regular, design: .default))
                .foregroundStyle(StageHUDTheme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(StageHUDTheme.textPrimary)
        }
    }

    private func launcherButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(StageHUDButtonStyle(tone: .secondary))
    }
}
