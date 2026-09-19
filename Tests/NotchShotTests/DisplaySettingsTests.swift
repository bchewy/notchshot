// SPDX-License-Identifier: MIT
import AppKit
import XCTest
@testable import NotchShot

final class DisplaySettingsTests: XCTestCase {
    @MainActor
    func testMissingOrMalformedPreferenceKeepsExistingScreenPlacement() {
        let (preferences, clipboard) = isolatedStoreDependencies()
        let store = CaptureStore(preferences: preferences, clipboard: clipboard)
        XCTAssertFalse(store.followActiveScreen)
        store.stop()

        for invalidValue: Any in ["enabled", [true], Data([1])] {
            preferences.set(invalidValue, forKey: "followActiveScreen")
            let restored = CaptureStore(preferences: preferences, clipboard: clipboard)
            XCTAssertFalse(restored.followActiveScreen)
            restored.stop()
        }
    }

    @MainActor
    func testFollowActiveScreenPersistsBothChoicesWithoutChangingShelfOrClipboard() {
        let (preferences, clipboard) = isolatedStoreDependencies()
        clipboard.setString("Existing clipboard", forType: .string)
        let clipboardVersion = clipboard.changeCount
        let store = CaptureStore(preferences: preferences, clipboard: clipboard)
        defer { store.stop() }
        let shot = makeCapture()
        store.captures = [shot]
        store.selectedID = shot.id
        store.page = .settings
        store.isExpanded = true

        for isEnabled in [true, false, true] {
            store.followActiveScreen = isEnabled
            XCTAssertEqual(preferences.object(forKey: "followActiveScreen") as? Bool, isEnabled)
            let restored = CaptureStore(preferences: preferences, clipboard: clipboard)
            XCTAssertEqual(restored.followActiveScreen, isEnabled)
            restored.stop()
            XCTAssertEqual(store.captures.map(\.id), [shot.id])
            XCTAssertEqual(store.selectedID, shot.id)
            XCTAssertEqual(store.page, .settings)
            XCTAssertTrue(store.isExpanded)
            XCTAssertEqual(clipboard.changeCount, clipboardVersion)
            XCTAssertEqual(clipboard.string(forType: .string), "Existing clipboard")
        }
    }

    @MainActor
    func testScreenMoveWaitsForBusyWorkAndResumesAfterItFinishes() {
        let operations: [(String, (CaptureStore) -> Void, (CaptureStore) -> Void)] = [
            ("capture", { $0.isCapturing = true }, { $0.isCapturing = false }),
            ("image import", { $0.isImporting = true }, { $0.isImporting = false }),
            ("drop target", { $0.isDropTargeted = true }, { $0.isDropTargeted = false }),
            ("shortcut recording", { $0.isRecordingShortcut = true }, { $0.isRecordingShortcut = false }),
            ("landing", { $0.isLandingCapture = true }, { $0.isLandingCapture = false }),
            ("pending capture", { $0.pendingCapture = self.makeCapture() }, { $0.pendingCapture = nil }),
            ("card drag", { $0.beginCardDrag() }, { $0.endCardDrag(accepted: false) })
        ]
        for (name, begin, end) in operations {
            let (preferences, clipboard) = isolatedStoreDependencies(name)
            preferences.set(false, forKey: "autoCollapseEnabled")
            let store = CaptureStore(preferences: preferences, clipboard: clipboard)
            XCTAssertFalse(store.shouldDeferScreenMove, name)
            begin(store)
            XCTAssertTrue(store.shouldDeferScreenMove, name)
            end(store)
            XCTAssertFalse(store.shouldDeferScreenMove, name)
            store.stop()
        }
    }

    @MainActor
    func testKeyboardMenusAndMousePressesDeferMovesButHoverIsOwnedByController() {
        let (preferences, clipboard) = isolatedStoreDependencies()
        let store = CaptureStore(preferences: preferences, clipboard: clipboard)
        defer { store.stop() }

        for (keyboard, menu, mouse) in [(true, false, false), (false, true, false), (false, false, true)] {
            store.updateNotchAttention(pointerInside: false, keyboardFocused: keyboard,
                                       menuTracking: menu, mouseButtonDown: mouse, surfaceVisible: true)
            XCTAssertTrue(store.shouldDeferScreenMove)
            store.updateNotchAttention(pointerInside: false, keyboardFocused: false,
                                       menuTracking: false, mouseButtonDown: false, surfaceVisible: true)
            XCTAssertFalse(store.shouldDeferScreenMove)
        }

        store.updateNotchAttention(pointerInside: true, keyboardFocused: false,
                                   menuTracking: false, mouseButtonDown: false, surfaceVisible: true)
        XCTAssertFalse(store.shouldDeferScreenMove,
                       "A cached hover state must not strand the notch after the pointer leaves its screen.")
    }

    @MainActor
    func testOverlappingPopoverProtectionsHoldMoveUntilEveryOwnerFinishes() {
        let (preferences, clipboard) = isolatedStoreDependencies()
        let store = CaptureStore(preferences: preferences, clipboard: clipboard)
        defer { store.stop() }
        let firstOwner = UUID()
        let secondOwner = UUID()

        store.setAutoCollapseProtection(owner: firstOwner, active: true)
        store.setAutoCollapseProtection(owner: secondOwner, active: true)
        XCTAssertTrue(store.shouldDeferScreenMove)
        store.setAutoCollapseProtection(owner: firstOwner, active: false)
        XCTAssertTrue(store.shouldDeferScreenMove)
        store.setAutoCollapseProtection(owner: secondOwner, active: false)
        XCTAssertFalse(store.shouldDeferScreenMove)
    }

    private func makeCapture() -> CaptureResult {
        CaptureResult(appName: "Display test", bundleIdentifier: "com.example.display-test",
                      windowTitle: "Existing shot", axTree: [], accessibilityText: "Existing text", ocrText: "")
    }
}
