import SwiftUI

enum StageHUDTheme {
    static let panelBackgroundTop = Color(nsColor: .windowBackgroundColor)
    static let panelBackgroundBottom = Color(nsColor: .underPageBackgroundColor)
    static let panelBorder = Color.primary.opacity(0.14)
    static let panelShadow = Color.black.opacity(0.18)
    static let textPrimary = Color.primary.opacity(0.95)
    static let textSecondary = Color.primary.opacity(0.72)
    static let textMuted = Color.primary.opacity(0.48)
    static let cardFill = Color.primary.opacity(0.03)
    static let cardBorder = Color.primary.opacity(0.14)
    static let accentIdle = Color.primary.opacity(0.82)
    static let accentRecording = Color(red: 0.98, green: 0.38, blue: 0.38)
    static let accentPaused = Color(red: 0.95, green: 0.76, blue: 0.34)
    static let buttonPrimaryTop = Color.primary.opacity(0.92)
    static let buttonPrimaryBottom = Color.primary.opacity(0.82)
    static let buttonSecondary = Color.primary.opacity(0.07)
    static let buttonSecondaryHover = Color.primary.opacity(0.11)
}
