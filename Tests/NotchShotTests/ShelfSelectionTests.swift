// SPDX-License-Identifier: MIT
import AppKit
import XCTest
@testable import NotchShot

final class ShelfSelectionTests: XCTestCase {
    func testToggleRangeAndArrivalUseStableShotIDs() {
        var selection = ShelfSelection()
        let ids = (0..<5).map { _ in UUID() }
        selection.toggle(ids[1], orderedIDs: ids)
        selection.extend(to: ids[3], orderedIDs: ids)
        XCTAssertEqual(selection.ids, Set(ids[1...3]))
        selection.toggle(ids[2], orderedIDs: ids)
        XCTAssertEqual(selection.ids, [ids[1], ids[3]])
        let arriving = UUID()
        selection.reconcile(orderedIDs: [arriving] + ids)
        XCTAssertEqual(selection.ids, [ids[1], ids[3]], "Arrival must not change the selected batch.")
        selection.reconcile(orderedIDs: [arriving, ids[3]])
        XCTAssertEqual(selection.ids, [ids[3]])
        XCTAssertNil(selection.anchor)
        selection.extend(to: arriving, orderedIDs: [arriving, ids[3]])
        XCTAssertEqual(selection.ids, [arriving, ids[3]])
        selection.reconcile(orderedIDs: [])
        XCTAssertFalse(selection.isActive)
        XCTAssertTrue(selection.ids.isEmpty)
    }

    @MainActor
    func testSelectionDoesNotNavigateOrOverwriteDetailSelectionAndCopiesInShelfOrder() {
        let f = fixture()
        defer { f.store.stop() }
        let shots = [shot("First"), shot("Second"), shot("Third")]
        f.store.captures = shots
        f.store.selectedID = shots[1].id
        f.store.isExpanded = true
        f.store.handleShelfClick(shots[2].id, commandPressed: true)
        f.store.handleShelfClick(shots[0].id, commandPressed: true)
        XCTAssertTrue(f.store.isSelectingShots)
        XCTAssertEqual(f.store.page, .shelf)
        XCTAssertEqual(f.store.selectedID, shots[1].id)
        XCTAssertEqual(f.store.selectedShelfCaptures.map(\.id), [shots[0].id, shots[2].id])
        f.store.batchContextStyle = .full
        let expected = f.store.selectedBatch!.contextText
        XCTAssertTrue(f.store.copyShelfSelection())
        XCTAssertEqual(f.board.string(forType: .string), expected)
        XCTAssertTrue(expected.contains(shots[0].contextText))
        XCTAssertTrue(expected.contains(shots[2].contextText))
        XCTAssertFalse(expected.contains(shots[1].contextText))
        XCTAssertEqual(f.sound.plays, 1, "One copy confirms the whole batch once.")
    }

    @MainActor
    func testHoverDuringSelectionCopiesBatchEvenOverUnselectedThumbnailAndEmptySelectionDoesNotCopy() {
        let f = fixture()
        defer { f.store.stop() }
        let shots = [shot("Selected"), shot("Hovered")]
        f.store.captures = shots
        f.store.handleShelfClick(shots[0].id, commandPressed: true)
        XCTAssertTrue(f.store.copyShelfShot(shots[1].id))
        XCTAssertEqual(f.board.string(forType: .string), f.store.selectedBatch?.contextText)
        XCTAssertFalse(f.board.string(forType: .string)!.contains("Content for Hovered"))
        f.store.handleShelfClick(shots[0].id)
        let token = f.board.changeCount
        XCTAssertFalse(f.store.copyShelfSelection())
        XCTAssertFalse(f.store.copyShelfShot(shots[1].id))
        XCTAssertFalse(f.store.copyShelfShot(UUID()))
        XCTAssertEqual(f.board.changeCount, token)
        f.store.endShelfSelection()
        XCTAssertTrue(f.store.copyShelfShot(shots[1].id))
        XCTAssertEqual(f.board.string(forType: .string), shots[1].contextText)
    }

    @MainActor
    func testRemovalAndClearingCannotCopyStaleSelectedShots() {
        let f = fixture()
        defer { f.store.stop() }
        let shots = [shot("Retained"), shot("Removed")]
        f.store.captures = shots
        f.store.selectAllShelfShots()
        f.store.removeCapture(shots[1].id)
        XCTAssertEqual(f.store.selectedShotCount, 1)
        XCTAssertEqual(f.store.selectedBatch?.captures.map(\.id), [shots[0].id])
        XCTAssertTrue(f.store.copyShelfSelection())
        XCTAssertFalse(f.board.string(forType: .string)!.contains("Content for Removed"))
        f.store.clearHistory()
        XCTAssertFalse(f.store.isSelectingShots)
        XCTAssertNil(f.store.selectedBatch)
        XCTAssertFalse(f.store.copyShelfSelection())
    }

    @MainActor
    func testModePreferencePersistsAndRebuildsContextWithoutMutatingOriginals() {
        let f = fixture()
        defer { f.store.stop() }
        var large = shot("Long")
        large.accessibilityText = String(repeating: "A long unique paragraph with useful context.\n", count: 2_000)
        f.store.captures = [large]
        f.store.selectAllShelfShots()
        XCTAssertEqual(f.store.batchContextStyle, .compact)
        XCTAssertTrue(f.store.selectedBatch!.isShortened)
        f.store.batchContextStyle = .full
        XCTAssertTrue(f.store.selectedBatch!.contextText.contains(large.contextText))
        XCTAssertEqual(f.store.captures[0].accessibilityText, large.accessibilityText)
        let restored = CaptureStore(preferences: f.preferences,
                                    captureSound: SilentBatchSelectionCaptureSound(), clipboard: f.board,
                                    copySound: BatchSelectionSound(), assistedPaste: BatchSelectionPasteSpy())
        defer { restored.stop() }
        XCTAssertEqual(restored.batchContextStyle, .full)
    }

    @MainActor
    func testPlainClickStillOpensDetailsAndClosingRetainsBatchSelection() {
        let f = fixture()
        defer { f.store.stop() }
        let shot = shot("Open")
        f.store.captures = [shot]
        f.store.handleShelfClick(shot.id)
        XCTAssertEqual(f.store.page, .detail)
        XCTAssertEqual(f.store.selectedID, shot.id)
        f.store.showShelf()
        f.store.beginShelfSelection()
        f.store.handleShelfClick(shot.id)
        f.store.collapse()
        f.store.showShelf()
        XCTAssertEqual(f.store.selectedShotIDs, [shot.id])
        f.store.endShelfSelection()
        XCTAssertEqual(f.store.selectedShotCount, 0)
        XCTAssertNil(f.store.selectedBatch)
        XCTAssertEqual(f.store.captures.map(\.id), [shot.id])
    }

    @MainActor
    func testCopyingThenDismissingReviewKeepsTheSuccessfulCopyCollapse() async throws {
        let f = fixture()
        defer { f.store.stop() }
        let shot = shot("Review")
        f.store.captures = [shot]
        f.store.selectAllShelfShots()
        f.store.isExpanded = true
        f.store.collapseAfterCopy = true
        let owner = UUID()
        f.store.setAutoCollapseProtection(owner: owner, active: true)
        XCTAssertTrue(f.store.copyShelfSelection())
        f.store.setAutoCollapseProtection(owner: owner, active: false)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertFalse(f.store.isExpanded)
        XCTAssertEqual(f.store.selectedShotIDs, [shot.id])
        XCTAssertEqual(f.board.string(forType: .string), f.store.selectedBatch?.contextText)
    }

    @MainActor
    func testKeyboardCommandsAreScopedToTheKeyShelfAndRespectTextEditing() {
        _ = NSApplication.shared
        let f = fixture()
        defer { f.store.stop() }
        f.store.captures = [shot("One"), shot("Two")]
        f.store.isExpanded = true
        let panel = SelectionTestPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                                       styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        let view = ShelfSelectionKeyboardNSView(frame: .zero)
        view.store = f.store
        panel.contentView = view
        defer { view.stop() }
        func event(_ code: UInt16, flags: NSEvent.ModifierFlags = .command) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                            windowNumber: panel.windowNumber, context: nil, characters: "",
                            charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
        }
        XCTAssertFalse(view.handle(event(0)), "Normal browsing must not take over Select All.")
        f.store.beginShelfSelection()
        XCTAssertTrue(view.handle(event(0)))
        XCTAssertEqual(f.store.selectedShotCount, 2)
        XCTAssertTrue(view.handle(event(8)))
        let token = f.board.changeCount
        XCTAssertFalse(view.handle(event(8, flags: [.command, .shift])))
        panel.simulatesKey = false
        XCTAssertFalse(view.handle(event(8)))
        panel.simulatesKey = true
        let editor = NSTextView(frame: .zero)
        view.addSubview(editor)
        XCTAssertTrue(panel.makeFirstResponder(editor))
        XCTAssertFalse(view.handle(event(8)), "Copy in an editable/review text view must use its own selection.")
        XCTAssertFalse(view.handle(event(0)))
        XCTAssertEqual(f.board.changeCount, token)
        XCTAssertFalse(panel.isVisible, "Keyboard tests must never put windows on screen.")
    }

    @MainActor
    func testLargePreparationCannotReplaceANewerSelectionOrCopyPartialContext() async throws {
        let f = fixture()
        defer { f.store.stop() }
        var large = shot("Large")
        large.accessibilityText = String(repeating: "Lengthy captured source with Unicode 你好 👩🏽‍💻.\n", count: 20_000)
        let small = shot("Current selection")
        f.store.captures = [large, small]
        f.store.handleShelfClick(large.id, commandPressed: true)
        XCTAssertTrue(f.store.isPreparingBatch)
        let token = f.board.changeCount
        XCTAssertFalse(f.store.copyShelfSelection())
        XCTAssertEqual(f.board.changeCount, token)
        f.store.handleShelfClick(large.id)
        f.store.handleShelfClick(small.id)
        XCTAssertFalse(f.store.isPreparingBatch)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(f.store.selectedBatch?.captures.map(\.id), [small.id])
        XCTAssertTrue(f.store.copyShelfSelection())
        XCTAssertFalse(f.board.string(forType: .string)!.contains("App: Large"))
    }

    @MainActor
    func testValidatedReviewContextAndCopiedStatusDiscloseRejectedScreenshot() async throws {
        let f = fixture()
        defer { f.store.stop() }
        var capture = shot("Text survives")
        capture.pngData = Data("broken PNG".utf8)
        f.store.captures = [capture]
        f.store.selectAllShelfShots()
        XCTAssertTrue(f.store.isPreparingBatch)
        for _ in 0..<100 {
            if !f.store.isPreparingBatch { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let batch = try XCTUnwrap(f.store.selectedBatch)
        XCTAssertTrue(batch.imagePNGs.isEmpty)
        XCTAssertEqual(batch.omittedScreenshotNumbers, [1])
        XCTAssertTrue(batch.contextText.contains("unavailable"))
        XCTAssertTrue(f.store.copyShelfSelection())
        XCTAssertEqual(f.board.string(forType: .string), batch.contextText)
        XCTAssertNil(f.board.data(forType: .png))
        XCTAssertTrue(f.store.statusNotice?.message.contains("Screenshots unavailable for shots 1") == true)
    }

    @MainActor
    private func fixture() -> (store: CaptureStore, board: NSPasteboard, preferences: UserDefaults, sound: BatchSelectionSound) {
        let name = "ShelfSelectionTests.\(UUID())"
        let preferences = UserDefaults(suiteName: name)!
        let board = NSPasteboard.withUniqueName()
        let sound = BatchSelectionSound()
        addTeardownBlock { preferences.removePersistentDomain(forName: name); board.releaseGlobally() }
        let store = CaptureStore(preferences: preferences, captureSound: SilentBatchSelectionCaptureSound(),
                                 clipboard: board, copySound: sound, assistedPaste: BatchSelectionPasteSpy())
        store.collapseAfterCopy = false
        return (store, board, preferences, sound)
    }

    private func shot(_ name: String) -> CaptureResult {
        CaptureResult(appName: name, bundleIdentifier: "test.batch", windowTitle: "Window \(name)",
                      accessibilityText: "Content for \(name)")
    }
}

@MainActor private final class SelectionTestPanel: NSPanel {
    var simulatesKey = true
    override var isKeyWindow: Bool { simulatesKey }
}

@MainActor private final class SilentBatchSelectionCaptureSound: CaptureSoundPlaying { func play() {} }
@MainActor private final class BatchSelectionSound: CopySoundPlaying {
    var plays = 0
    func play() { plays += 1 }
}
@MainActor private final class BatchSelectionPasteSpy: AssistedPasteServing {
    var onResult: ((AssistedPasteResult) -> Void)?
    func arm(capture: CaptureResult, clipboard: NSPasteboard) -> Bool { false }
    func cancel() {}
    func stop() {}
}
