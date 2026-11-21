import SwiftUI
import UIKit
import KhurdaCore

/// Colours and helpers used across screens. Arabic and right-to-left layout come from the
/// system language; amounts use Western digits, as UAE bank messages do.
///
/// Palette "Gulf morning": light, bright and uplifting. Light values are the primary design; dark
/// values keep Dark Mode working. Status colours are for the ring, bars and icons; text uses
/// `textPrimary` / `textSecondary`. Hex values are a starting point, to be contrast-checked on a device.
enum Theme {
    /// Screen background: warm white.
    static let background = dynamic(light: 0xFFFCF6, dark: 0x12161C)
    /// Cards.
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x1B2129)
    /// Secondary surface and the ring's track: soft sand.
    static let surfaceSecondary = dynamic(light: 0xF6EFE3, dark: 0x232A33)
    static let ringTrack = surfaceSecondary
    /// Primary accent: Gulf sea blue.
    static let accent = dynamic(light: 0x2E8BEF, dark: 0x5AA9FF)
    /// Sunny yellow, for small highlights only (the payday crescent, achievements).
    static let highlight = dynamic(light: 0xFFC53D, dark: 0xFFD36B)

    static let relaxed = dynamic(light: 0x22B573, dark: 0x3DD68C)    // fresh green
    static let onTrack = accent
    static let careful = dynamic(light: 0xF5A524, dark: 0xFFB84D)    // warm amber
    static let over = dynamic(light: 0xF2545B, dark: 0xFF7A80)       // soft coral: "adjust", not "fail"

    static let textPrimary = dynamic(light: 0x1E2A36, dark: 0xEEF2F6)
    static let textSecondary = dynamic(light: 0x6B7785, dark: 0x9AA6B2)

    static func color(for status: SafeToSpend.Status) -> Color {
        switch status {
        case .relaxed: relaxed
        case .onTrack: onTrack
        case .careful: careful
        case .over: over
        }
    }

    /// SF Pro Rounded with fixed-width digits, so the big number doesn't jump as it changes.
    static func bigNumber(size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded).monospacedDigit()
    }

    static func aed(_ value: Decimal, decimals: Int = 0) -> String {
        "AED " + value.formatted(.number.precision(.fractionLength(decimals)).locale(Locale(identifier: "en_AE")))
    }

    /// One colour for light mode and one for dark, from 0xRRGGBB.
    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? Theme.uiColor(dark) : Theme.uiColor(light) })
    }

    private static func uiColor(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// Light by default: the app opens bright even when the iPhone is in Dark Mode. Settings can switch
/// to Dark or to following the iPhone.
enum Appearance: String, CaseIterable, Identifiable {
    case light, dark, system
    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .system: "Match iPhone"
        }
    }
}

extension View {
    /// Warm-white screen background behind lists, forms and scroll views.
    func themedBackground() -> some View {
        scrollContentBackground(.hidden).background(Theme.background)
    }
}
