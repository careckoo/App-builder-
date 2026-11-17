import SwiftUI
import MasroofiCore

/// Colours and helpers used across screens. Arabic and right-to-left layout come from the
/// system language; amounts use Western digits, as UAE bank messages do.
enum Theme {
    static let accent = Color(red: 0.05, green: 0.55, blue: 0.48)     // deep teal
    static let relaxed = Color(red: 0.16, green: 0.68, blue: 0.43)
    static let onTrack = Color(red: 0.05, green: 0.55, blue: 0.48)
    static let careful = Color(red: 0.93, green: 0.6, blue: 0.13)
    static let over = Color(red: 0.86, green: 0.25, blue: 0.24)

    static func color(for status: SafeToSpend.Status) -> Color {
        switch status {
        case .relaxed: relaxed
        case .onTrack: onTrack
        case .careful: careful
        case .over: over
        }
    }

    static func aed(_ value: Decimal, decimals: Int = 0) -> String {
        "AED " + value.formatted(.number.precision(.fractionLength(decimals)).locale(Locale(identifier: "en_AE")))
    }
}
