import SwiftUI

struct StageHUDRootView: View {
    @ObservedObject var model: StageHUDViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            controls
            logs
        }
        .padding(16)
        .frame(width: 312, height: 428, alignment: .topLeading)
        .background(panelBackground)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Circle()
                    .fill(accentColor)
                    .frame(width: 9, height: 9)
                    .shadow(color: accentColor.opacity(0.35), radius: 10)

                Text(model.phaseLabel)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(accentColor)

                Spacer()

                Text(model.targetApp)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(StageHUDTheme.textMuted)
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(model.summary)
                    .font(.system(size: 17, weight: .semibold, design: .monospaced))
                    .foregroundStyle(StageHUDTheme.textPrimary)
                    .lineLimit(2)

                Text(model.detailText)
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundStyle(StageHUDTheme.textSecondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                capsule("Floating HUD")
                if let elapsedText = model.elapsedText {
                    capsule(elapsedText)
                }
            }
        }
        .padding(14)
        .background(cardBackground)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Controls")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(StageHUDTheme.textMuted)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
            ], spacing: 10) {
                ForEach(model.buttons) { button in
                    Button(button.title) {
                        model.send(button.id)
                    }
                    .buttonStyle(StageHUDButtonStyle(tone: button.tone))
                    .disabled(!button.enabled)
                }
            }
        }
        .padding(14)
        .background(cardBackground)
    }

    private var logs: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent Events")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(StageHUDTheme.textMuted)
                Spacer()
                Text("\(model.recentLogs.count)")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(StageHUDTheme.textMuted)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if model.recentLogs.isEmpty {
                        Text("No events yet.")
                            .font(.system(size: 12, weight: .regular, design: .default))
                            .foregroundStyle(StageHUDTheme.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(Array(model.recentLogs.enumerated().reversed()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 12, weight: .regular, design: .default))
                                .foregroundStyle(StageHUDTheme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.white.opacity(0.04))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                                )
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(14)
        .background(cardBackground)
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [StageHUDTheme.panelBackgroundTop, StageHUDTheme.panelBackgroundBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(StageHUDTheme.panelBorder, lineWidth: 1)
            )
            .shadow(color: StageHUDTheme.panelShadow, radius: 14, x: 0, y: 8)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(StageHUDTheme.cardFill)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(StageHUDTheme.cardBorder, lineWidth: 1)
            )
    }

    private var accentColor: Color {
        switch model.phaseAccent {
        case .neutral:
            return StageHUDTheme.accentIdle
        case .paused:
            return StageHUDTheme.accentPaused
        case .recording:
            return StageHUDTheme.accentRecording
        }
    }

    private func capsule(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .foregroundStyle(StageHUDTheme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

struct StageHUDButtonStyle: ButtonStyle {
    let tone: StageHUDViewModel.ButtonTone

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(foregroundColor(configuration: configuration))
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(background(configuration: configuration))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(borderColor(configuration: configuration), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.992 : 1)
            .opacity(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private func background(configuration: Configuration) -> some View {
        Group {
            switch tone {
            case .primary:
                LinearGradient(
                    colors: [
                        StageHUDTheme.buttonPrimaryTop.opacity(configuration.isPressed ? 0.92 : 1),
                        StageHUDTheme.buttonPrimaryBottom.opacity(configuration.isPressed ? 0.92 : 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            case .secondary:
                Color(configuration.isPressed ? StageHUDTheme.buttonSecondaryHover : StageHUDTheme.buttonSecondary)
            case .destructive:
                LinearGradient(
                    colors: [
                        StageHUDTheme.accentRecording.opacity(configuration.isPressed ? 0.85 : 0.92),
                        StageHUDTheme.accentRecording.opacity(configuration.isPressed ? 0.70 : 0.78),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    private func foregroundColor(configuration: Configuration) -> Color {
        switch tone {
        case .primary:
            return Color.black.opacity(configuration.isPressed ? 0.86 : 0.92)
        case .secondary, .destructive:
            return StageHUDTheme.textPrimary.opacity(configuration.isPressed ? 0.88 : 1)
        }
    }

    private func borderColor(configuration: Configuration) -> Color {
        switch tone {
        case .primary:
            return Color.white.opacity(configuration.isPressed ? 0.22 : 0.14)
        case .secondary:
            return Color.white.opacity(configuration.isPressed ? 0.12 : 0.10)
        case .destructive:
            return Color.white.opacity(configuration.isPressed ? 0.14 : 0.10)
        }
    }
}
