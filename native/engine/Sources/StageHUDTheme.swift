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
        light: NSColor(calibratedRed: 0.953, green: 0.922, blue: 0.867, alpha: 1),
        dark: NSColor(calibratedRed: 0.078, green: 0.098, blue: 0.102, alpha: 1)
    )
    static let railBackground = dynamic(
        light: NSColor(calibratedRed: 0.925, green: 0.886, blue: 0.812, alpha: 1),
        dark: NSColor(calibratedRed: 0.055, green: 0.071, blue: 0.074, alpha: 1)
    )
    static let footerBackground = dynamic(
        light: NSColor(calibratedRed: 0.929, green: 0.894, blue: 0.827, alpha: 1),
        dark: NSColor(calibratedRed: 0.055, green: 0.071, blue: 0.074, alpha: 1)
    )
    static let panelBackgroundTop = dynamic(
        light: NSColor(calibratedRed: 0.980, green: 0.961, blue: 0.922, alpha: 1),
        dark: NSColor(calibratedRed: 0.110, green: 0.133, blue: 0.137, alpha: 1)
    )
    static let panelBackgroundBottom = dynamic(
        light: NSColor(calibratedRed: 0.980, green: 0.961, blue: 0.922, alpha: 1),
        dark: NSColor(calibratedRed: 0.110, green: 0.133, blue: 0.137, alpha: 1)
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
        light: NSColor(calibratedRed: 0.125, green: 0.157, blue: 0.169, alpha: 1),
        dark: NSColor(calibratedRed: 0.953, green: 0.922, blue: 0.867, alpha: 1)
    )
    static let textSecondary = dynamic(
        light: NSColor(calibratedRed: 0.349, green: 0.384, blue: 0.380, alpha: 1),
        dark: NSColor(calibratedRed: 0.659, green: 0.702, blue: 0.694, alpha: 1)
    )
    static let textMuted = dynamic(
        light: NSColor(calibratedRed: 0.529, green: 0.502, blue: 0.463, alpha: 1),
        dark: NSColor(calibratedRed: 0.482, green: 0.529, blue: 0.522, alpha: 1)
    )
    static let cardFill = dynamic(
        light: NSColor(calibratedRed: 0.980, green: 0.961, blue: 0.922, alpha: 1),
        dark: NSColor(calibratedRed: 0.110, green: 0.133, blue: 0.137, alpha: 1)
    )
    static let cardBorder = dynamic(
        light: NSColor(calibratedRed: 0.125, green: 0.157, blue: 0.169, alpha: 0.12),
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
        light: NSColor(calibratedRed: 0.980, green: 0.961, blue: 0.922, alpha: 1),
        dark: NSColor(calibratedRed: 0.110, green: 0.133, blue: 0.137, alpha: 1)
    )
    static let buttonSecondaryHover = dynamic(
        light: NSColor(calibratedRed: 0.996, green: 0.984, blue: 0.957, alpha: 1),
        dark: NSColor(calibratedRed: 0.137, green: 0.165, blue: 0.169, alpha: 1)
    )
    static let buttonPrimaryText = dynamic(
        light: NSColor.white,
        dark: NSColor(calibratedWhite: 0.08, alpha: 1)
    )

    // Run outcome tokens. The Runs ledger needs one glanceable status colour per
    // row, legible at 6pt dot size against cardFill in both appearances.
    static let runOk = dynamic(
        light: NSColor(calibratedRed: 0.13, green: 0.55, blue: 0.33, alpha: 1),
        dark: NSColor(calibratedRed: 0.38, green: 0.80, blue: 0.55, alpha: 1)
    )
    static let runRunning = dynamic(
        light: NSColor(calibratedRed: 0.72, green: 0.50, blue: 0.06, alpha: 1),
        dark: NSColor(calibratedRed: 0.95, green: 0.76, blue: 0.34, alpha: 1)
    )
    static let runFailed = dynamic(
        light: NSColor(calibratedRed: 0.78, green: 0.21, blue: 0.19, alpha: 1),
        dark: NSColor(calibratedRed: 0.98, green: 0.45, blue: 0.42, alpha: 1)
    )
    static let runStopped = dynamic(
        light: NSColor(calibratedWhite: 0.52, alpha: 1),
        dark: NSColor(calibratedWhite: 0.55, alpha: 1)
    )
    /// Zebra wash for dense ledger rows. Deliberately near-invisible: it should
    /// steady the eye across a 260-row scan without reading as a stripe.
    static let rowAlternate = dynamic(
        light: NSColor(calibratedWhite: 0.0, alpha: 0.018),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.022)
    )
    /// Selection wash for the run the operator last opened. It has to survive the
    /// zebra underneath it and still leave room for a hovered variant on top, so
    /// the pair is tuned together rather than reusing `reviewAccentMuted`.
    static let runSelection = dynamic(
        light: NSColor(calibratedRed: 0.19, green: 0.47, blue: 0.90, alpha: 0.13),
        dark: NSColor(calibratedRed: 0.47, green: 0.71, blue: 1.00, alpha: 0.17)
    )
    static let runSelectionHover = dynamic(
        light: NSColor(calibratedRed: 0.19, green: 0.47, blue: 0.90, alpha: 0.22),
        dark: NSColor(calibratedRed: 0.47, green: 0.71, blue: 1.00, alpha: 0.27)
    )
    /// Backing for the hovered row's destination chip. Sits on top of the hover
    /// fill, so it needs its own weight rather than borrowing the selection wash.
    static let runActionChip = dynamic(
        light: NSColor(calibratedRed: 0.19, green: 0.47, blue: 0.90, alpha: 0.11),
        dark: NSColor(calibratedRed: 0.47, green: 0.71, blue: 1.00, alpha: 0.15)
    )

    // Capture HUD tokens. The recorder is deliberately dark in both system
    // appearances so its operational state remains stable over any surface.
    static let hudCanvas = Color(red: 0.055, green: 0.071, blue: 0.074)
    static let hudPanel = Color(red: 0.095, green: 0.118, blue: 0.122)
    static let hudPanelRaised = Color(red: 0.125, green: 0.153, blue: 0.157)
    static let hudPaper = Color(red: 0.953, green: 0.922, blue: 0.867)
    static let hudInk = Color(red: 0.055, green: 0.071, blue: 0.074)
    static let hudMuted = Color(red: 0.60, green: 0.65, blue: 0.64)
    static let hudGrid = Color.white.opacity(0.045)
    static let hudStroke = Color.white.opacity(0.10)
    static let hudStrokeStrong = Color.white.opacity(0.19)
    static let hudCoral = Color(red: 0.937, green: 0.416, blue: 0.278)
    static let hudCoralHot = Color(red: 1.0, green: 0.49, blue: 0.32)
    static let hudCyan = Color(red: 0.122, green: 0.725, blue: 0.776)
    static let hudAmber = Color(red: 0.894, green: 0.725, blue: 0.412)
    static let hudMetalTop = Color(red: 0.115, green: 0.118, blue: 0.112)
    static let hudMetalEdge = Color(red: 0.39, green: 0.39, blue: 0.35)
    static let hudRecess = Color(red: 0.026, green: 0.031, blue: 0.031)
    static let hudEtch = Color(red: 0.68, green: 0.68, blue: 0.61)
    static let hudShadow = Color.black.opacity(0.58)

    // Finishing tokens (texture + bevel pass). Restrained graphite polish:
    // a rolled top highlight, a settled bottom shadow, brushed grain, and a
    // brighter sheen for machined cylinder controls. All additive, all subtle.
    static let hudBevelLight = Color.white.opacity(0.055)
    static let hudBevelHairline = Color.white.opacity(0.11)
    static let hudBevelShadow = Color.black.opacity(0.34)
    static let hudGrain = Color.white.opacity(0.028)
    static let hudGrainDark = Color.black.opacity(0.05)
    static let hudMetalSheen = Color(red: 0.30, green: 0.31, blue: 0.29)
    static let hudMetalCore = Color(red: 0.165, green: 0.170, blue: 0.160)
    static let hudMetalTrough = Color(red: 0.045, green: 0.048, blue: 0.046)

    // MARK: - Field tokens (Home)
    //
    // Home is the one surface that speaks in the brand's own voice rather than
    // the neutral operator chrome the ledgers use. The pair below is the brand
    // paper/graphite set from `assets/brand`, split across the two system
    // appearances: paper in light, graphite in dark. Both keep the same coral
    // and the same cyan, so a live drive reads identically either way — the
    // colour that means "running" must not depend on the operator's theme.
    //
    // Coral is the runtime-truth colour: something is happening to this Mac
    // right now. Cyan is the secondary signal and never competes with it.

    private static func hex(_ value: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(
            calibratedRed: CGFloat((value >> 16) & 0xFF) / 255.0,
            green: CGFloat((value >> 8) & 0xFF) / 255.0,
            blue: CGFloat(value & 0xFF) / 255.0,
            alpha: alpha
        )
    }

    /// Page ground.
    static let fieldCanvas = dynamic(light: hex(0xF3EBDD), dark: hex(0x14191A))
    /// Raised card over the canvas.
    static let fieldPanel = dynamic(light: hex(0xFAF5EB), dark: hex(0x1C2223))
    /// The status console at the top of Home.
    ///
    /// A shade *below* the canvas where the other panels sit a shade above it,
    /// so the console reads as recessed into the page rather than as one more
    /// card on it. That is the whole hierarchy: everything else is content laid
    /// on the surface, this is a window cut into it showing the machine's state.
    static let fieldConsole = dynamic(light: hex(0xEDE4D3), dark: hex(0x111617))
    static let fieldPanelEdge = dynamic(
        light: hex(0x20282B, alpha: 0.12),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.10)
    )
    /// Hairline under the page header.
    static let fieldRule = dynamic(
        light: hex(0x20282B, alpha: 0.22),
        dark: hex(0xF3EBDD, alpha: 0.18)
    )
    /// The vertical field grid. Near-invisible on purpose: it should register as
    /// paper texture, not as a ruled sheet.
    static let fieldGrid = dynamic(
        light: hex(0x20282B, alpha: 0.025),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.028)
    )

    static let fieldInk = dynamic(light: hex(0x20282B), dark: hex(0xF3EBDD))
    static let fieldInkSecondary = dynamic(light: hex(0x596261), dark: hex(0xA8B3B1))
    /// Ledger row titles. Between `fieldInk` and `fieldInkSecondary`: still the
    /// most prominent thing in its row, without printing as black.
    static let fieldInkRow = dynamic(light: hex(0x3D4241), dark: hex(0xD5D0C4))
    /// Field tan. An accent voice, not a demotion — it carries the editorial
    /// subtitle beside a panel label, where a warm aside is the intent.
    ///
    /// It is deliberately *not* used for numbers. Tan is saturated enough that
    /// applying it to every duration and timestamp made the metadata louder than
    /// the row titles it describes, which is exactly backwards.
    static let fieldInkMuted = dynamic(light: hex(0xA77850), dark: hex(0x7B8785))
    /// Numeric metadata: durations, timestamps, counts. A genuinely quiet warm
    /// grey, so a row reads title-first.
    static let fieldInkMeta = dynamic(light: hex(0x8A8175), dark: hex(0x6F7A78))

    /// The recessed dark block: the live lease panel and the command well. It
    /// stays dark in both appearances for the same reason the capture HUD does —
    /// what it reports is operational state, not decoration.
    ///
    /// Warmed in light mode. The brand graphite (`#20282b`) is a cool blue-green,
    /// and against warm paper it reads as a foreign object dropped on the page
    /// rather than as part of it. This keeps the same darkness and drops the blue,
    /// so the block belongs to the palette it sits in. Dark mode keeps the cool
    /// graphite, because there it sits on a cool ground and already agrees with it.
    static let fieldDeep = dynamic(light: hex(0x25231F), dark: hex(0x0A0E0F))
    static let fieldDeepText = hex_(0xF3EBDD)
    static let fieldDeepMeta = hex_(0x8D9997)
    static let fieldDeepEdge = Color(nsColor: hex(0xF3EBDD, alpha: 0.12))
    static let fieldDeepChip = Color(nsColor: hex(0xF3EBDD, alpha: 0.10))

    /// Runtime truth. Same value as `hudCoral`, named for where it is used.
    static let fieldAccent = hudCoral
    static let fieldAccentText = dynamic(light: hex(0xFAF5EB), dark: hex(0x0E1213))
    static let fieldSignal = hudCyan

    private static func hex_(_ value: UInt32) -> Color {
        Color(nsColor: hex(value))
    }

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
