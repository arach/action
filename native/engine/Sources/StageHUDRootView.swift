import SwiftUI

struct StageHUDRootView: View {
    @ObservedObject var model: StageHUDViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            primaryControls
            utilityControls
            logs
        }
        .padding(16)
        .frame(width: 336, height: 456, alignment: .topLeading)
        .background(panelBackground)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 9, height: 9)
                        .shadow(color: accentColor.opacity(0.35), radius: 10)

                    Text(model.phaseLabel)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(accentColor)
                }

                Spacer()

                statusChip(model.targetApp)
                if let elapsedText = model.elapsedText {
                    statusChip(elapsedText)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(model.summary)
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundStyle(StageHUDTheme.textPrimary)
                    .lineLimit(2)

                Text(model.detailText)
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundStyle(StageHUDTheme.textSecondary)
                    .lineLimit(3)
            }
        }
        .padding(15)
        .background(cardBackground)
    }

    private var primaryControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Transport")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(StageHUDTheme.textMuted)

            HStack(spacing: 10) {
                controlButton("start")
                controlButton("stop")
            }
        }
        .padding(15)
        .background(cardBackground)
    }

    private var utilityControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Session")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(StageHUDTheme.textMuted)

            HStack(spacing: 10) {
                controlButton("replay")
                controlButton("clear")
                controlButton("quit")
            }
        }
        .padding(15)
        .background(cardBackground)
    }

    private var logs: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
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
                        ForEach(Array(model.recentLogs.enumerated().reversed()), id: \.offset) { index, line in
                            HStack(alignment: .top, spacing: 10) {
                                Text(String(format: "%02d", model.recentLogs.count - index))
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(StageHUDTheme.textMuted)
                                    .padding(.top, 2)

                                Text(line)
                                    .font(.system(size: 12, weight: .regular, design: .default))
                                    .foregroundStyle(StageHUDTheme.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 9)
                            .padding(.horizontal, 11)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.primary.opacity(0.035))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(15)
        .background(cardBackground)
    }

    private var panelBackground: some View {
        ActionChamferedShape(cornerCut: 8)
            .fill(StageHUDTheme.panelBackgroundTop)
            .overlay(
                ActionChamferedShape(cornerCut: 8)
                    .stroke(StageHUDTheme.panelBorder, lineWidth: 1)
            )
            .shadow(color: StageHUDTheme.panelShadow, radius: 14, x: 0, y: 8)
    }

    private var cardBackground: some View {
        ActionChamferedShape(cornerCut: 6)
            .fill(StageHUDTheme.cardFill)
            .overlay(
                ActionChamferedShape(cornerCut: 6)
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

    private func statusChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .foregroundStyle(StageHUDTheme.textSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(StageHUDTheme.buttonSecondary)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(StageHUDTheme.cardBorder, lineWidth: 1)
            )
    }

    private func controlButton(_ id: String) -> some View {
        let button = model.buttons.first(where: { $0.id == id })

        return Button(button?.title ?? id.capitalized) {
            model.send(id)
        }
        .buttonStyle(StageHUDButtonStyle(tone: button?.tone ?? .secondary))
        .disabled(!(button?.enabled ?? false))
    }
}

struct StageHUDButtonStyle: ButtonStyle {
    let tone: StageHUDViewModel.ButtonTone

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .regular, design: .monospaced))
            .foregroundStyle(foregroundColor(configuration: configuration))
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(background(configuration: configuration))
            .overlay(
                ActionChamferedShape(cornerCut: 4)
                    .stroke(borderColor(configuration: configuration), lineWidth: 1)
            )
            .clipShape(ActionChamferedShape(cornerCut: 4))
            .scaleEffect(configuration.isPressed ? 0.992 : 1)
            .opacity(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private func background(configuration: Configuration) -> some View {
        Group {
            switch tone {
            case .primary:
                Color(configuration.isPressed ? StageHUDTheme.buttonPrimaryBottom : StageHUDTheme.buttonPrimaryTop)
            case .secondary:
                Color(configuration.isPressed ? StageHUDTheme.buttonSecondaryHover : StageHUDTheme.buttonSecondary)
            case .destructive:
                Color(StageHUDTheme.accentRecording.opacity(configuration.isPressed ? 0.78 : 0.88))
            }
        }
    }

    private func foregroundColor(configuration: Configuration) -> Color {
        switch tone {
        case .primary:
            return StageHUDTheme.buttonPrimaryText.opacity(configuration.isPressed ? 0.88 : 1)
        case .secondary, .destructive:
            return StageHUDTheme.textPrimary.opacity(configuration.isPressed ? 0.88 : 1)
        }
    }

    private func borderColor(configuration: Configuration) -> Color {
        switch tone {
        case .primary:
            return StageHUDTheme.panelBorder.opacity(configuration.isPressed ? 1 : 0.9)
        case .secondary:
            return StageHUDTheme.cardBorder.opacity(configuration.isPressed ? 1 : 0.95)
        case .destructive:
            return StageHUDTheme.cardBorder.opacity(configuration.isPressed ? 1 : 0.95)
        }
    }
}
