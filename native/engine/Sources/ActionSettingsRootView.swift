import SwiftUI

/// Lightweight preferences window (menu bar / separate window path).
/// The in-app Settings pane lives in `ActionLauncherRootView`.
struct ActionSettingsRootView: View {
    @Binding var appearanceMode: ActionAppearanceMode

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ActionSettingsPageHeader(
                icon: "paintpalette",
                title: "Appearance",
                subtitle: "How Action looks on this Mac."
            )

            ActionSettingsSection(title: "Theme") {
                ActionSettingsControlRow(
                    title: "Appearance",
                    subtitle: "System follows macOS. Light and Dark force the theme.",
                    icon: "circle.lefthalf.filled"
                ) {
                    Picker("Appearance", selection: $appearanceMode) {
                        ForEach(ActionAppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 220)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 480, height: 260, alignment: .topLeading)
        .background(StageHUDTheme.appBackground)
    }
}
