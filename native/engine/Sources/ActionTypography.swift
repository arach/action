import AppKit
import CoreText
import SwiftUI

/// Action's type scale.
///
/// Three families, and only three:
///
/// - **Mono — JetBrains Mono.** The house monospace across Talkie, Scout and
///   Lattices, so a number or a command reads the same wherever it appears. It
///   is not a system font, so every call falls back to the platform monospace
///   when it is missing rather than silently landing on something else.
/// - **Editorial — New York**, via `.serif`. Apple designed it for screen text;
///   at 15pt it holds a row title far better than a print face like EB Garamond,
///   which the brand uses on the web where the sizes are twice as large.
/// - **UI — SF Pro**, via `.system`. The rest of macOS, and the right default
///   for anything the operator reads as chrome rather than as content.
///
/// The named roles below are the whole scale. Reaching past them for an ad-hoc
/// `.system(size:)` is how a surface ends up with ten sizes that are each two
/// points apart and none of which mean anything.
enum ActionType {
    /// Resolved once: `NSFont(name:)` hits the font cache, and every label on a
    /// dense screen would otherwise ask the same question.
    ///
    /// Nil when JetBrains Mono is not installed, which is the common case on a
    /// machine that has not set up the house fonts — the app ships without them
    /// today, so the fallback below is a real path, not a theoretical one.
    static let monoFamily: String? = {
        for candidate in ["JetBrains Mono", "JetBrainsMono-Regular", "JetBrainsMonoNL-Regular"] {
            if NSFont(name: candidate, size: 12) != nil {
                return candidate
            }
        }
        return nil
    }()

    /// `fixedSize` on purpose: this is an operator console with alignment that
    /// depends on the grid holding, not body copy that should track Dynamic Type.
    ///
    /// Ligatures are turned off. JetBrains Mono ships them on, and it renders the
    /// `--` in `-- bun --cwd` as a single long dash — in a command the operator
    /// is meant to read and retype, that is a wrong character on screen, not a
    /// stylistic flourish.
    private static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        guard let monoFamily,
              let base = NSFont(name: monoFamily, size: size) else {
            return .system(size: size, weight: weight, design: .monospaced)
        }
        let descriptor = base.fontDescriptor.addingAttributes([
            .featureSettings: [
                [
                    NSFontDescriptor.FeatureKey.typeIdentifier: kLigaturesType,
                    NSFontDescriptor.FeatureKey.selectorIdentifier: kCommonLigaturesOffSelector,
                ],
                [
                    NSFontDescriptor.FeatureKey.typeIdentifier: kLigaturesType,
                    NSFontDescriptor.FeatureKey.selectorIdentifier: kRareLigaturesOffSelector,
                ],
            ],
        ])
        guard let resolved = NSFont(descriptor: descriptor, size: size) else {
            return .custom(monoFamily, fixedSize: size).weight(weight)
        }
        return Font(resolved).weight(weight)
    }

    /// The editorial face.
    ///
    /// Overridable at runtime with
    /// `defaults write dev.action.Action ActionEditorialFont "<family>"` so the
    /// choice can be judged in the real UI rather than in a specimen. `system`
    /// falls back to New York.
    static let editorialFamily: String? = {
        let requested = UserDefaults.standard.string(forKey: "ActionEditorialFont")
            ?? "Charter"
        guard requested.lowercased() != "system",
              NSFont(name: requested, size: 12) != nil else {
            return nil
        }
        return requested
    }()

    private static func editorial(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        guard let editorialFamily else {
            return .system(size: size, weight: weight, design: .serif)
        }
        return .custom(editorialFamily, fixedSize: size).weight(weight)
    }

    // MARK: Roles

    /// Section title. One per screen.
    static let pageTitle = editorial(34, .regular)
    /// The one sentence a panel exists to say.
    static let panelLead = editorial(21, .regular)
    /// Row titles. 14, not 15: in a four-row ledger the titles are the only
    /// serif on the line, and a point larger tips them from "leading" to "loud".
    static let body = editorial(14)
    /// The sentence beside a panel label. One step down from `body` on purpose:
    /// at the same size it competes with the row titles underneath it.
    static let subtitle = editorial(13)
    /// Supporting sentence under a lead.
    static let bodySmall = editorial(13)
    /// Row titles that are literally code (a calculator expression, a verb).
    static let bodyMono = mono(14)

    /// A number meant to be read across the room: the elapsed clock.
    static let display = mono(26, .medium)
    /// Commands, counts, durations, timestamps.
    static let code = mono(11)
    /// The same size, for numbers that should sit on the digit grid.
    static let meta = mono(11)
    /// Eyebrows, chips, column headers. Always paired with `labelTracking`.
    static let label = mono(9, .semibold)
    /// Unemphasised twin of `label`, for values beside a label.
    static let labelRegular = mono(9)

    /// Tracking for `label`. Small mono caps close up without it; this is the
    /// value at which the letters read as a set rather than a word.
    static let labelTracking: CGFloat = 0.9
    /// The page eyebrow sits alone above a 34pt title and can carry more air.
    static let eyebrowTracking: CGFloat = 1.3
}
