// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI
import XCTest
@testable import NotchShot

final class NotchThemeTests: XCTestCase {
    @MainActor
    func testMissingAndUnknownPreferencesKeepOriginalMintTheme() {
        let (preferences, clipboard) = isolatedStoreDependencies()
        let defaultStore = CaptureStore(preferences: preferences, clipboard: clipboard)
        defer { defaultStore.stop() }
        XCTAssertEqual(defaultStore.theme, .mint)

        for invalidValue in ["future-theme", "", "MINT"] {
            preferences.set(invalidValue, forKey: "notchTheme")
            let restored = CaptureStore(preferences: preferences, clipboard: clipboard)
            XCTAssertEqual(restored.theme, .mint)
            restored.stop()
        }
    }

    @MainActor
    func testEveryThemePersistsAndRestoresWithoutChangingClipboardOrShelf() {
        let (preferences, clipboard) = isolatedStoreDependencies()
        clipboard.setString("Existing clipboard", forType: .string)
        let version = clipboard.changeCount
        let store = CaptureStore(preferences: preferences, clipboard: clipboard)
        defer { store.stop() }

        for theme in NotchTheme.allCases {
            store.theme = theme
            XCTAssertEqual(preferences.string(forKey: "notchTheme"), theme.rawValue)
            let restored = CaptureStore(preferences: preferences, clipboard: clipboard)
            XCTAssertEqual(restored.theme, theme)
            restored.stop()
            XCTAssertEqual(clipboard.changeCount, version)
            XCTAssertEqual(clipboard.string(forType: .string), "Existing clipboard")
            XCTAssertFalse(store.isExpanded)
            XCTAssertEqual(store.page, .shelf)
            XCTAssertTrue(store.captures.isEmpty)
        }
    }

    func testEnvironmentUsesMintUntilOverridden() {
        var environment = EnvironmentValues()
        XCTAssertEqual(environment.notchTheme, .mint)
        environment.notchTheme = .rose
        XCTAssertEqual(environment.notchTheme, .rose)
    }

    func testOriginalMintAccentIsPreserved() {
        let rgb = NotchTheme.mint.accentRGB
        XCTAssertEqual(rgb.red, 0.54)
        XCTAssertEqual(rgb.green, 0.91)
        XCTAssertEqual(rgb.blue, 0.77)
    }

    func testAccentsMeetTextContrastOnButtonsAndDarkSurfaces() {
        // Covers black labels on accent buttons and accent text on the notch,
        // screenshot card, and the lighter dark surfaces used inside it.
        let darkBackgrounds: [(red: Double, green: Double, blue: Double)] = [
            (0, 0, 0),
            (0.065, 0.078, 0.073),
            (0.18, 0.18, 0.18)
        ]
        for theme in NotchTheme.allCases {
            let accentLuminance = luminance(theme.accentRGB)
            XCTAssertGreaterThanOrEqual((accentLuminance + 0.05) / 0.05, 4.5,
                                        "\(theme.name): black text on an accent button")
            for background in darkBackgrounds {
                XCTAssertGreaterThanOrEqual((accentLuminance + 0.05) / (luminance(background) + 0.05), 4.5,
                                            "\(theme.name): accent text on a dark surface")
            }
        }
    }

    @MainActor
    func testNativeAccentUsesSameSRGBComponents() throws {
        for theme in NotchTheme.allCases {
            let color = try XCTUnwrap(theme.nsAccent.usingColorSpace(.sRGB))
            let rgb = theme.accentRGB
            XCTAssertEqual(color.redComponent, rgb.red, accuracy: 0.00001)
            XCTAssertEqual(color.greenComponent, rgb.green, accuracy: 0.00001)
            XCTAssertEqual(color.blueComponent, rgb.blue, accuracy: 0.00001)
            XCTAssertEqual(color.alphaComponent, 1, accuracy: 0.00001)
        }
    }

    private func luminance(_ rgb: (red: Double, green: Double, blue: Double)) -> Double {
        func linearize(_ component: Double) -> Double {
            component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(rgb.red) + 0.7152 * linearize(rgb.green) + 0.0722 * linearize(rgb.blue)
    }
}
