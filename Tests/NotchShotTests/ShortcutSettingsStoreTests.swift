// SPDX-License-Identifier: MIT
import AppKit
import XCTest
@testable import NotchShot

final class ShortcutSettingsStoreTests: XCTestCase {
    @MainActor
    func testFreshPreferencesDefaultToBothShiftAndKeepKeyboardAlternative() throws {
        try withPreferences { defaults, clipboard in
            let store = CaptureStore(preferences: defaults, clipboard: clipboard)
            XCTAssertEqual(store.captureShortcut, .defaultShortcut)
            XCTAssertTrue(CaptureStore(preferences: defaults, clipboard: clipboard).bothShiftEnabled)
            store.bothShiftEnabled = false
            XCTAssertFalse(CaptureStore(preferences: defaults, clipboard: clipboard).bothShiftEnabled)
        }
    }

    @MainActor
    func testPrimaryHintTracksWorkingShiftGestureAndFallsBackWithoutLosingCustomShortcut() throws {
        try withPreferences { defaults, clipboard in
            let custom = try XCTUnwrap(CaptureShortcut(keyCode: 0, modifierFlags: [.control, .option]))
            custom.save(to: defaults)
            let store = CaptureStore(preferences: defaults, clipboard: clipboard)
            store.accessibilityGranted = true
            store.bothShiftAvailable = true
            XCTAssertEqual(store.captureHintLabel, "⇧ + ⇧")
            XCTAssertTrue(store.captureHintHelp.contains("left Shift + right Shift together"))
            XCTAssertEqual(store.captureShortcut, custom)
            XCTAssertEqual(store.captureShortcutLabel, custom.displayString)
            store.shortcutAvailable = false
            XCTAssertTrue(store.hasAvailableCaptureShortcut, "A backup conflict must not hide a working Shift gesture.")
            store.bothShiftAvailable = false
            XCTAssertFalse(store.hasAvailableCaptureShortcut)
            XCTAssertEqual(store.captureHintLabel, custom.displayString)
            store.shortcutAvailable = true
            XCTAssertTrue(store.hasAvailableCaptureShortcut)
            store.bothShiftAvailable = true
            store.bothShiftEnabled = false
            XCTAssertEqual(store.captureHintLabel, custom.displayString)
            XCTAssertEqual(CaptureStore(preferences: defaults, clipboard: clipboard).captureShortcut, custom)
        }
    }

    @MainActor
    func testExplicitAndLegacyDisabledChoicesSurviveNewDefault() throws {
        for key in ["bothShiftEnabled", "doubleShiftEnabled", "doubleCommandEnabled"] {
            try withPreferences { defaults, clipboard in
                defaults.set(false, forKey: key)
                XCTAssertFalse(CaptureStore(preferences: defaults, clipboard: clipboard).bothShiftEnabled)
                defaults.set(true, forKey: "doubleCommandEnabled")
                defaults.set(true, forKey: "doubleShiftEnabled")
                XCTAssertFalse(CaptureStore(preferences: defaults, clipboard: clipboard).bothShiftEnabled,
                               "The migrated explicit choice wins over legacy keys.")
            }
        }
    }

    @MainActor
    func testLegacyGesturePreferenceMigratesOnceAndDoesNotOverrideNewChoice() throws {
        for oldKey in ["doubleCommandEnabled", "doubleShiftEnabled"] {
            try withPreferences { defaults, clipboard in
                defaults.set(true, forKey: oldKey)
                let store = CaptureStore(preferences: defaults, clipboard: clipboard)
                XCTAssertTrue(store.bothShiftEnabled)
                store.bothShiftEnabled = false
                XCTAssertFalse(CaptureStore(preferences: defaults, clipboard: clipboard).bothShiftEnabled)
            }
        }
    }

    @MainActor
    func testSuccessfulRegistrationPersistsAndReloadsChosenShortcut() throws {
        try withPreferences { defaults, clipboard in
            let store = CaptureStore(preferences: defaults, clipboard: clipboard)
            let chosen = try XCTUnwrap(CaptureShortcut(keyCode: 0, modifierFlags: [.control, .option]))
            var registered: CaptureShortcut?
            store.onRegisterShortcut = { shortcut in registered = shortcut; return .success }
            store.setCaptureShortcut(chosen)
            XCTAssertEqual(registered, chosen)
            XCTAssertEqual(store.captureShortcut, chosen)
            XCTAssertEqual(CaptureStore(preferences: defaults, clipboard: clipboard).captureShortcut, chosen)
            XCTAssertNil(store.shortcutError)
            XCTAssertTrue(store.shortcutAvailable)
        }
    }

    @MainActor
    func testFailedRegistrationRetainsPreviousPersistedShortcut() throws {
        try withPreferences { defaults, clipboard in
            let original = try XCTUnwrap(CaptureShortcut(keyCode: 1, modifierFlags: [.command, .option]))
            original.save(to: defaults)
            let store = CaptureStore(preferences: defaults, clipboard: clipboard)
            store.onRegisterShortcut = { _ in .failure(-9878) }
            store.setCaptureShortcut(.defaultShortcut)
            XCTAssertEqual(store.captureShortcut, original)
            XCTAssertEqual(CaptureShortcut.load(from: defaults), original)
            XCTAssertNotNil(store.shortcutError)
        }
    }

    @MainActor
    func testLeavingSettingsOrCollapsingEndsRecordingAndRecordingCannotCapture() throws {
        try withPreferences { defaults, clipboard in
            let store = CaptureStore(preferences: defaults, clipboard: clipboard)
            var states: [Bool] = []
            store.onShortcutRecordingChanged = { states.append($0) }
            store.showingSettings = true
            store.isRecordingShortcut = true
            store.captureFrontmost()
            XCTAssertFalse(store.isCapturing)
            XCTAssertNil(store.statusMessage)
            store.showingSettings = false
            XCTAssertFalse(store.isRecordingShortcut)
            store.showingSettings = true
            store.isRecordingShortcut = true
            store.collapse()
            XCTAssertEqual(states, [true, false, true, false])
            XCTAssertFalse(store.isRecordingShortcut)
        }
    }

    @MainActor
    private func withPreferences(_ body: (UserDefaults, NSPasteboard) throws -> Void) throws {
        let (defaults, clipboard) = isolatedStoreDependencies()
        try body(defaults, clipboard)
    }
}
