import AppKit
import SwiftUI

// MARK: - Product links

enum ActionDocs {
    static let siteURL = URL(string: "https://arach.github.io/action/")!
    static let siteHostLabel = "arach.github.io/action"
}

extension Notification.Name {
    static let actionShowKeyboardCheatSheet = Notification.Name("Action.ShowKeyboardCheatSheet")
}

// MARK: - Settings primitives
// Inspired by HudsonUI HudSettings + Scout settings rows:
// calm static rows, section labels, surface cards — not dense list chrome.

struct ActionSettingsSectionLabel: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(StageHUDTheme.textMuted)
    }
}

struct ActionSettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ActionSettingsSectionLabel(title: title)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(StageHUDTheme.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(StageHUDTheme.cardBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

struct ActionSettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(StageHUDTheme.cardBorder)
            .frame(height: 1)
            .padding(.leading, 52)
    }
}

struct ActionSettingsLeadingIcon: View {
    let systemName: String
    var color: Color = StageHUDTheme.textMuted

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(color)
            .frame(width: 28, height: 28)
    }
}

/// Informational or tappable settings row: icon · title/subtitle · trailing badge.
struct ActionSettingsRow<Badge: View>: View {
    let icon: String
    var iconColor: Color = StageHUDTheme.textMuted
    let title: String
    var subtitle: String? = nil
    var onTap: (() -> Void)? = nil
    @ViewBuilder var badge: () -> Badge

    var body: some View {
        let row = HStack(spacing: 12) {
            ActionSettingsLeadingIcon(systemName: icon, color: iconColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(StageHUDTheme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(StageHUDTheme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)
            badge()

            if onTap != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(StageHUDTheme.textMuted.opacity(0.7))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())

        if let onTap {
            Button(action: onTap) { row }
                .buttonStyle(.plain)
        } else {
            row
        }
    }
}

extension ActionSettingsRow where Badge == EmptyView {
    init(
        icon: String,
        iconColor: Color = StageHUDTheme.textMuted,
        title: String,
        subtitle: String? = nil,
        onTap: (() -> Void)? = nil
    ) {
        self.init(
            icon: icon,
            iconColor: iconColor,
            title: title,
            subtitle: subtitle,
            onTap: onTap,
            badge: { EmptyView() }
        )
    }
}

/// Title/subtitle on the left, control on the right.
struct ActionSettingsControlRow<Control: View>: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var iconColor: Color = StageHUDTheme.textMuted
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let icon {
                ActionSettingsLeadingIcon(systemName: icon, color: iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(StageHUDTheme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(StageHUDTheme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 16)
            control()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct ActionSettingsStatusBadge: View {
    enum Kind {
        case ok
        case warning
        case neutral
        case offline
    }

    let text: String
    var kind: Kind = .neutral

    private var color: Color {
        switch kind {
        case .ok:
            return Color(nsColor: .systemGreen)
        case .warning:
            return Color(nsColor: .systemOrange)
        case .offline:
            return Color(nsColor: .systemRed).opacity(0.85)
        case .neutral:
            return StageHUDTheme.textMuted
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(StageHUDTheme.textSecondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(StageHUDTheme.buttonSecondaryHover.opacity(0.85))
        )
    }
}

/// Permission row patterned after Lattices: status + detail + action.
struct ActionSettingsPermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    var statusLabel: String? = nil
    let primaryActionTitle: String
    let onPrimary: () -> Void
    var onOpenSettings: (() -> Void)? = nil

    private var resolvedStatus: String {
        statusLabel ?? (granted ? "Granted" : "Needed")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ActionSettingsLeadingIcon(
                systemName: granted ? "checkmark.shield.fill" : "exclamationmark.shield.fill",
                color: granted ? Color(nsColor: .systemGreen) : Color(nsColor: .systemOrange)
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(StageHUDTheme.textPrimary)
                    ActionSettingsStatusBadge(
                        text: resolvedStatus,
                        kind: granted ? .ok : .warning
                    )
                }
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(StageHUDTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if !granted {
                Button(primaryActionTitle, action: onPrimary)
                    .buttonStyle(ActionSettingsPillButtonStyle(primary: true))
            }

            if let onOpenSettings {
                Button(action: onOpenSettings) {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(StageHUDTheme.textMuted)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open System Settings")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct ActionSettingsPillButtonStyle: ButtonStyle {
    var primary: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(primary ? StageHUDTheme.buttonPrimaryText : StageHUDTheme.textPrimary)
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(primary
                        ? (configuration.isPressed ? StageHUDTheme.buttonPrimaryBottom : StageHUDTheme.buttonPrimaryTop)
                        : (configuration.isPressed ? StageHUDTheme.buttonSecondaryHover : StageHUDTheme.buttonSecondary))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(primary ? Color.clear : StageHUDTheme.cardBorder, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}

struct ActionSettingsPageHeader: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(StageHUDTheme.reviewAccent)
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(StageHUDTheme.textPrimary)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(StageHUDTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Keyboard cheat sheet

struct ActionKeyboardCheatSheetView: View {
    var onOpenDocs: () -> Void = {
        NSWorkspace.shared.open(ActionDocs.siteURL)
    }
    var onClose: (() -> Void)?

    private let groups: [(title: String, rows: [(keys: String, action: String)])] = [
        (
            "App",
            [
                ("⌘1", "Loop"),
                ("⌘2", "Library"),
                ("⌘3", "Settings"),
                ("⌘,", "Settings window"),
                ("⌘/", "This cheat sheet"),
                ("?", "This cheat sheet"),
            ]
        ),
        (
            "Loop",
            [
                ("1 · 2 · 3", "Start · Edit · Review phases"),
                ("New loop", "Draft Calculator scenario"),
                ("Approve & run", "Capture from Edit"),
            ]
        ),
        (
            "Library",
            [
                ("Click", "Open take"),
                ("Hover", "Quick actions"),
                ("Right-click", "Replay, Finder, Delete…"),
            ]
        ),
        (
            "Review (media notes)",
            [
                ("N", "Open note composer"),
                ("1 / 2 / 3 / 4", "Point · Range · Region · Draw"),
                ("Space", "Play / pause"),
                ("Esc", "Cancel selection / close composer"),
                ("⌘↩", "Save note"),
                ("[ / ]", "Previous / next note"),
            ]
        ),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Keyboard")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(StageHUDTheme.textPrimary)
                    Text("Quick navigation for Action.")
                        .font(.system(size: 13))
                        .foregroundStyle(StageHUDTheme.textSecondary)
                }
                Spacer()
                if let onClose {
                    Button("Done", action: onClose)
                        .buttonStyle(ActionSettingsPillButtonStyle(primary: true))
                        .keyboardShortcut(.defaultAction)
                }
            }

            ForEach(groups, id: \.title) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.title.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(StageHUDTheme.textMuted)

                    VStack(spacing: 0) {
                        ForEach(Array(group.rows.enumerated()), id: \.offset) { index, row in
                            HStack {
                                Text(row.keys)
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(StageHUDTheme.textPrimary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(StageHUDTheme.buttonSecondaryHover)
                                    )
                                Spacer(minLength: 12)
                                Text(row.action)
                                    .font(.system(size: 13))
                                    .foregroundStyle(StageHUDTheme.textSecondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)

                            if index < group.rows.count - 1 {
                                Rectangle()
                                    .fill(StageHUDTheme.cardBorder)
                                    .frame(height: 1)
                                    .padding(.leading, 12)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(StageHUDTheme.cardFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(StageHUDTheme.cardBorder, lineWidth: 1)
                    )
                }
            }

            HStack(spacing: 10) {
                Button {
                    onOpenDocs()
                } label: {
                    Label("Documentation", systemImage: "book")
                }
                .buttonStyle(ActionSettingsPillButtonStyle())

                Text(ActionDocs.siteHostLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(StageHUDTheme.textMuted)

                Spacer()
            }
        }
        .padding(24)
        .frame(width: 440)
        .background(StageHUDTheme.appBackground)
    }
}
