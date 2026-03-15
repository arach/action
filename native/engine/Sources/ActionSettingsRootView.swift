import SwiftUI

struct ActionSettingsRootView: View {
    @Binding var appearanceMode: ActionAppearanceMode

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .foregroundStyle(StageHUDTheme.textPrimary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Appearance")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(StageHUDTheme.textMuted)

                Picker("Appearance", selection: $appearanceMode) {
                    ForEach(ActionAppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text("System follows macOS. Light and Dark force a high-contrast app theme.")
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundStyle(StageHUDTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 460, height: 220, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
