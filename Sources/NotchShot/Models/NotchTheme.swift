// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI

/// Bright accents keep both black button labels and colored text on the dark
/// notch readable. Raw values are stable keys for the saved preference.
enum NotchTheme: String, CaseIterable, Identifiable, Sendable {
    case mint
    case sky
    case lavender
    case rose
    case peach
    case gold

    var id: Self { self }

    var name: String {
        switch self {
        case .mint: "Mint"
        case .sky: "Sky"
        case .lavender: "Lavender"
        case .rose: "Rose"
        case .peach: "Peach"
        case .gold: "Gold"
        }
    }

    var accentRGB: (red: Double, green: Double, blue: Double) {
        switch self {
        case .mint: (0.54, 0.91, 0.77)
        case .sky: (0.55, 0.79, 1.00)
        case .lavender: (0.76, 0.67, 1.00)
        case .rose: (1.00, 0.64, 0.77)
        case .peach: (1.00, 0.73, 0.55)
        case .gold: (0.98, 0.84, 0.48)
        }
    }

    var accent: Color {
        let rgb = accentRGB
        return Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    var nsAccent: NSColor {
        let rgb = accentRGB
        return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }

    /// The lighter end of the aperture mark's gradient.
    var apertureHighlight: Color {
        switch self {
        case .mint: Color(.sRGB, red: 0.70, green: 0.98, blue: 0.85)
        case .sky: Color(.sRGB, red: 0.76, green: 0.90, blue: 1.00)
        case .lavender: Color(.sRGB, red: 0.88, green: 0.82, blue: 1.00)
        case .rose: Color(.sRGB, red: 1.00, green: 0.82, blue: 0.89)
        case .peach: Color(.sRGB, red: 1.00, green: 0.87, blue: 0.75)
        case .gold: Color(.sRGB, red: 1.00, green: 0.93, blue: 0.73)
        }
    }
}

private struct NotchThemeKey: EnvironmentKey {
    static let defaultValue = NotchTheme.mint
}

extension EnvironmentValues {
    var notchTheme: NotchTheme {
        get { self[NotchThemeKey.self] }
        set { self[NotchThemeKey.self] = newValue }
    }
}
