import SwiftUI
import UIKit
import SarfiCore

/// Colours and helpers used across screens. Arabic and right-to-left layout come from the
/// system language; amounts use Western digits, as UAE bank messages do.
///
/// Palette "Gulf dusk" (docs/PRODUCT_SPEC.md §6): a calm indigo brand, warm sand card surfaces, and
/// status colours that don't shame. Status colours are for the ring, bars and icons; text stays in the
/// system label colours (mint and amber on white are below AA contrast for text). Hex values are a
/// starting point, to be contrast-checked on a device.
enum Theme {
    static let accent = dynamic(light: 0x3A4FE0, dark: 0x7C8CFF)     // indigo
    /// Card surfaces over the system grouped background; never a full-screen colour.
    static let surface = dynamic(light: 0xF6EFE4, dark: 0x1C1A24)    // sand
    static let relaxed = dynamic(light: 0x2BB59A, dark: 0x45D3B5)    // mint
    static let onTrack = accent
    static let careful = dynamic(light: 0xF2A33A, dark: 0xFFB95C)    // amber
    static let over = dynamic(light: 0xF0625A, dark: 0xFF7B73)       // coral: "adjust", not "fail"

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
        Color(UIColor { $0.userInterfaceStyle == .dark ? uiColor(dark) : uiColor(light) })
    }

    private static func uiColor(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
