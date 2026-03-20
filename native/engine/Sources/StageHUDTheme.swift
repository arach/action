import SwiftUI

enum StageHUDTheme {
    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .darkAqua:
                return dark
            default:
                return light
            }
        })
    }

    static let appBackground = dynamic(
        light: NSColor(calibratedWhite: 0.98, alpha: 1),
        dark: NSColor(calibratedWhite: 0.05, alpha: 1)
    )
    static let railBackground = dynamic(
        light: NSColor(calibratedRed: 0.95, green: 0.95, blue: 0.93, alpha: 1),
        dark: NSColor(calibratedWhite: 0.07, alpha: 1)
    )
    static let footerBackground = dynamic(
        light: NSColor(calibratedWhite: 0.985, alpha: 1),
        dark: NSColor(calibratedWhite: 0.075, alpha: 1)
    )
    static let panelBackgroundTop = dynamic(
        light: NSColor.white,
        dark: NSColor(calibratedWhite: 0.07, alpha: 1)
    )
    static let panelBackgroundBottom = dynamic(
        light: NSColor.white,
        dark: NSColor(calibratedWhite: 0.07, alpha: 1)
    )
    static let panelBorder = dynamic(
        light: NSColor(calibratedWhite: 0.05, alpha: 0.12),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.12)
    )
    static let panelShadow = dynamic(
        light: NSColor(calibratedWhite: 0.0, alpha: 0.05),
        dark: NSColor(calibratedWhite: 0.0, alpha: 0.22)
    )
    static let textPrimary = dynamic(
        light: NSColor(calibratedWhite: 0.08, alpha: 1),
        dark: NSColor(calibratedWhite: 0.95, alpha: 1)
    )
    static let textSecondary = dynamic(
        light: NSColor(calibratedWhite: 0.26, alpha: 1),
        dark: NSColor(calibratedWhite: 0.74, alpha: 1)
    )
    static let textMuted = dynamic(
        light: NSColor(calibratedWhite: 0.46, alpha: 1),
        dark: NSColor(calibratedWhite: 0.52, alpha: 1)
    )
    static let cardFill = dynamic(
        light: NSColor.white,
        dark: NSColor(calibratedWhite: 0.09, alpha: 1)
    )
    static let cardBorder = dynamic(
        light: NSColor(calibratedWhite: 0.05, alpha: 0.10),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.10)
    )
    static let accentIdle = dynamic(
        light: NSColor(calibratedWhite: 0.14, alpha: 1),
        dark: NSColor(calibratedWhite: 0.86, alpha: 1)
    )
    static let accentRecording = Color(red: 0.98, green: 0.38, blue: 0.38)
    static let accentPaused = Color(red: 0.95, green: 0.76, blue: 0.34)
    static let buttonPrimaryTop = dynamic(
        light: NSColor(calibratedWhite: 0.10, alpha: 1),
        dark: NSColor(calibratedWhite: 0.95, alpha: 1)
    )
    static let buttonPrimaryBottom = dynamic(
        light: NSColor(calibratedWhite: 0.18, alpha: 1),
        dark: NSColor(calibratedWhite: 0.82, alpha: 1)
    )
    static let buttonSecondary = dynamic(
        light: NSColor.white,
        dark: NSColor(calibratedWhite: 0.10, alpha: 1)
    )
    static let buttonSecondaryHover = dynamic(
        light: NSColor(calibratedWhite: 0.97, alpha: 1),
        dark: NSColor(calibratedWhite: 0.14, alpha: 1)
    )
    static let buttonPrimaryText = dynamic(
        light: NSColor.white,
        dark: NSColor(calibratedWhite: 0.08, alpha: 1)
    )

    // Review surface tokens (premium pass V1)
    static let reviewCanvas = dynamic(
        light: NSColor(calibratedRed: 0.975, green: 0.978, blue: 0.985, alpha: 1),
        dark: NSColor(calibratedWhite: 0.055, alpha: 1)
    )
    static let reviewPanel = dynamic(
        light: NSColor(calibratedRed: 0.992, green: 0.993, blue: 0.996, alpha: 1),
        dark: NSColor(calibratedWhite: 0.08, alpha: 1)
    )
    static let reviewPanelRaised = dynamic(
        light: NSColor.white,
        dark: NSColor(calibratedWhite: 0.095, alpha: 1)
    )
    static let reviewStrokeSoft = dynamic(
        light: NSColor(calibratedWhite: 0.08, alpha: 0.08),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.08)
    )
    static let reviewStrokeStrong = dynamic(
        light: NSColor(calibratedWhite: 0.08, alpha: 0.16),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.16)
    )
    static let reviewAccent = dynamic(
        light: NSColor(calibratedRed: 0.19, green: 0.47, blue: 0.90, alpha: 1),
        dark: NSColor(calibratedRed: 0.47, green: 0.71, blue: 1.00, alpha: 1)
    )
    static let reviewAccentMuted = dynamic(
        light: NSColor(calibratedRed: 0.19, green: 0.47, blue: 0.90, alpha: 0.18),
        dark: NSColor(calibratedRed: 0.47, green: 0.71, blue: 1.00, alpha: 0.22)
    )
}
