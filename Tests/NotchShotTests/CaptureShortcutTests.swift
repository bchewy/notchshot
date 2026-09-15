// SPDX-License-Identifier: MIT
import AppKit
import Carbon.HIToolbox
import XCTest
@testable import NotchShot

final class CaptureShortcutTests: XCTestCase {
    func testDefaultUsesCommandShiftTwo() {
        XCTAssertEqual(CaptureShortcut.defaultShortcut.keyCode, UInt16(kVK_ANSI_2))
        XCTAssertEqual(CaptureShortcut.defaultShortcut.modifierFlags, [.command, .shift])
    }

    func testRecorderRequiresDeliberateModifierAndLeavesNavigationKeysAvailable() {
        for flags: NSEvent.ModifierFlags in [[], [.shift], [.capsLock], [.shift, .function]] {
            XCTAssertNil(CaptureShortcut(keyCode: UInt16(kVK_ANSI_A), modifierFlags: flags))
        }
        for key in [kVK_Escape, kVK_Tab, kVK_Command, kVK_RightCommand, kVK_Shift,
                    kVK_RightShift, kVK_Control, kVK_Option, kVK_CapsLock, kVK_Function] {
            XCTAssertNil(CaptureShortcut(keyCode: UInt16(key), modifierFlags: [.command]))
        }
        XCTAssertNil(CaptureShortcut(keyCode: 255, modifierFlags: [.command]))
        for modifier: NSEvent.ModifierFlags in [.command, .control, .option] {
            XCTAssertNotNil(CaptureShortcut(keyCode: UInt16(kVK_ANSI_A), modifierFlags: modifier))
        }
    }

    func testIncidentalModifierFlagsNormalizeWithoutChangingShortcut() throws {
        let shortcut = try XCTUnwrap(CaptureShortcut(keyCode: UInt16(kVK_ANSI_K),
            modifierFlags: [.command, .option, .shift, .control, .capsLock, .numericPad, .function]))
        XCTAssertEqual(shortcut.modifierFlags, [.command, .option, .shift, .control])
        XCTAssertEqual(shortcut.carbonModifiers, UInt32(cmdKey | optionKey | shiftKey | controlKey))
        let carbon = CaptureShortcut(keyCode: shortcut.keyCode, carbonModifiers: shortcut.carbonModifiers | UInt32(alphaLock))
        XCTAssertEqual(carbon, shortcut)
    }

    func testStableSpecialKeyNamesAndModifierOrder() throws {
        let arrow = try XCTUnwrap(CaptureShortcut(keyCode: UInt16(kVK_RightArrow), modifierFlags: [.command, .shift, .option, .control]))
        XCTAssertEqual(arrow.displayString, "⌃⌥⇧⌘→")
        XCTAssertEqual(CaptureShortcut(keyCode: UInt16(kVK_F19), modifierFlags: [.control])?.displayString, "⌃F19")
        XCTAssertEqual(CaptureShortcut(keyCode: UInt16(kVK_Space), modifierFlags: [.option])?.displayString, "⌥Space")
        XCTAssertFalse(CaptureShortcut.defaultShortcut.keyDisplayName.isEmpty)
    }

    func testCodableRoundTripAndInvalidPayloadValidation() throws {
        let shortcut = try XCTUnwrap(CaptureShortcut(keyCode: UInt16(kVK_ANSI_K), modifierFlags: [.control, .option]))
        XCTAssertEqual(try JSONDecoder().decode(CaptureShortcut.self, from: JSONEncoder().encode(shortcut)), shortcut)
        for payload in [
            #"{"keyCode":0,"carbonModifiers":0}"#,
            #"{"keyCode":53,"carbonModifiers":256}"#,
            #"{"keyCode":999,"carbonModifiers":256}"#,
            #"{"keyCode":-1,"carbonModifiers":256}"#
        ] {
            XCTAssertThrowsError(try JSONDecoder().decode(CaptureShortcut.self, from: Data(payload.utf8)))
        }
    }

    func testIsolatedPersistenceRecoversFromMissingMalformedAndInvalidPreferences() throws {
        let suiteName = "NotchShotShortcutTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        XCTAssertEqual(CaptureShortcut.load(from: defaults), .defaultShortcut)
        let custom = try XCTUnwrap(CaptureShortcut(keyCode: UInt16(kVK_ANSI_J), modifierFlags: [.command, .option]))
        custom.save(to: defaults)
        XCTAssertEqual(CaptureShortcut.load(from: defaults), custom)

        defaults.set(Data("broken JSON".utf8), forKey: CaptureShortcut.storageKey)
        XCTAssertEqual(CaptureShortcut.load(from: defaults), .defaultShortcut)
        defaults.set(Data(#"{"keyCode":0,"carbonModifiers":0}"#.utf8), forKey: CaptureShortcut.storageKey)
        XCTAssertEqual(CaptureShortcut.load(from: defaults), .defaultShortcut)
        defaults.set("wrong preference type", forKey: CaptureShortcut.storageKey)
        XCTAssertEqual(CaptureShortcut.load(from: defaults), .defaultShortcut)
    }
}
