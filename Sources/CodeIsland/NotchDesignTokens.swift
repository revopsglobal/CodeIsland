import SwiftUI

/// The design-token system the review (2026-07-19, move R2) found neither app
/// had: every colour, radius and size was an inline literal at its point of use,
/// which is the mechanical reason the "one accent" direction reached the Hub and
/// never the notch panel — there was nothing to change.
///
/// Values are the artifact's contrast-checked palette. Colours that read as
/// *text, border or meter* split by appearance because the dark accents fail
/// WCAG AA on white (signal 1.82:1, danger 2.79:1); the same hues pass as
/// *fills* because a fill carries near-black text (9.77:1, 6.62:1). So the
/// accent splits by role, not by a naive inversion.
enum NotchTokens {

    // MARK: Surfaces (dark ground / light ground)

    static let surface0 = dynamic(dark: 0x08090B, light: 0xF2F3F6)
    static let surface1 = dynamic(dark: 0x101217, light: 0xFFFFFF)
    static let surface2 = dynamic(dark: 0x171A20, light: 0xF4F5F8)
    static let surface3 = dynamic(dark: 0x1E222A, light: 0xECEEF2)

    // MARK: Text — opacity is not mirrored (38% on black ≈ 45% on white)

    static let text1 = dynamic(dark: 0xFFFFFF, light: 0x17171B)
    static let text2 = dynamicA(dark: (0xFFFFFF, 0.62), light: (0x17171B, 0.62))
    static let text3 = dynamicA(dark: (0xFFFFFF, 0.38), light: (0x17171B, 0.45))
    static let text4 = dynamicA(dark: (0xFFFFFF, 0.22), light: (0x17171B, 0.34))

    // MARK: Semantic — three colours, total

    /// "Needs you", and nothing else may use it. Splits by role.
    static let signalFill = Color(hex: 0xFFB04D)                 // same in both modes
    static let signalText = dynamic(dark: 0xFFB04D, light: 0x9A5A00)
    /// On-fill foreground pinned to each fill so the pair can never drift —
    /// the bug where `.black` was hardcoded on-accent at six iOS sites.
    static let onSignal = Color(hex: 0x241505)

    /// Destructive consequence only. Splits by role.
    static let dangerFill = Color(hex: 0xFF6B5E)
    static let dangerText = dynamic(dark: 0xFF6B5E, light: 0xB3261E)
    static let onDanger = Color(hex: 0x2A0806)

    /// Motion meter only, never text. Clears the 3:1 non-text-graphic bar on light.
    static let live = dynamic(dark: 0x4DD966, light: 0x1E8F45)

    /// Running/processing status as *text* (the project name of a live session).
    /// The bright green reads on black but fails on white, so it darkens.
    static let runningText = dynamic(dark: 0x4DD966, light: 0x1E8F45)

    // MARK: Radius — replaces 3,4,5,6,7,8,9,10,11,16 on Mac

    static let radiusSmall: CGFloat = 10
    static let radiusMedium: CGFloat = 14
    static let radiusLarge: CGFloat = 18
    static let radiusXLarge: CGFloat = 22

    // MARK: Space — a 4pt scale

    static let space1: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 12
    static let space4: CGFloat = 16
    static let space6: CGFloat = 24

    // MARK: Type — two faces, one job each

    /// Human content: project names, states, actions.
    static func sans(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }

    /// Machine content: commands, paths, IDs. Always in a recessed well.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // MARK: Foreground ink — the sweep target

    /// Muted foreground at a given opacity: white ink on the dark panel.
    ///
    /// Light mode was reverted 2026-07-20 — it rendered unreadable on the real
    /// notch (the headless snapshot did not reproduce it). This and the token
    /// resolvers below are pinned to their dark values so the panel is always
    /// dark, exactly as it was before the light-mode wiring, while keeping the
    /// token structure and the SF Pro / SF Mono type split intact. The light
    /// values are retained in the resolvers as documentation of the intended
    /// palette for a future, properly-verified attempt.
    static func ink(_ opacity: Double) -> Color {
        Color(hex: 0xFFFFFF, alpha: opacity)
    }

    /// The panel ground: always black. See the note on `ink` above.
    static let panelGround = Color.black

    // MARK: Appearance-aware construction

    /// Pinned to the dark value — light mode reverted (see `ink`). The `light`
    /// argument is retained only to document the intended palette.
    static func dynamic(dark: Int, light: Int) -> Color {
        Color(hex: dark)
    }

    static func dynamicA(dark: (Int, CGFloat), light: (Int, CGFloat)) -> Color {
        Color(hex: dark.0, alpha: dark.1)
    }
}

extension Color {
    init(hex: Int, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

extension NSColor {
    convenience init(hex: Int, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
