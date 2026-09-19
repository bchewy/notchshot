// SPDX-License-Identifier: MIT
import AppKit
import XCTest
@testable import NotchShot

final class CapturePasteSettingsTests: XCTestCase {
    @MainActor
    func testOptInPersistsAndManualCopyArmsTheExactHoveredShot() throws {
        let defaults = UserDefaults(suiteName: "CapturePasteSettingsTests.\(UUID())")!
        let board = NSPasteboard.withUniqueName()
        let spy = PasteArmSpy()
        let store = CaptureStore(preferences: defaults, clipboard: board, assistedPaste: spy)
        defer { store.stop(); board.releaseGlobally() }
        let selected = try shot("Selected")
        let hovered = try shot("Hovered")
        store.captures = [selected, hovered]
        store.selectedID = selected.id
        XCTAssertFalse(store.pasteImageThenText)
        XCTAssertTrue(store.copyCapture(hovered.id))
        XCTAssertTrue(spy.armed.isEmpty)
        store.pasteImageThenText = true
        XCTAssertTrue(store.copyCapture(hovered.id))
        XCTAssertEqual(spy.armed, [hovered.id])
        XCTAssertEqual(spy.contexts, [hovered.clipboardText])
        XCTAssertEqual(store.selectedID, selected.id)
        XCTAssertEqual(board.string(forType: .string), hovered.clipboardText)
        XCTAssertNotNil(board.data(forType: .rtfd))
        let restored = CaptureStore(preferences: defaults, clipboard: board, assistedPaste: PasteArmSpy())
        defer { restored.stop() }
        XCTAssertTrue(restored.pasteImageThenText)
        let cancellations = spy.cancelCount
        store.pasteImageThenText = false
        XCTAssertGreaterThan(spy.cancelCount, cancellations)
    }

    @MainActor
    func testAutomaticCopyArmsOnceAndIndividualCopyCancels() throws {
        let defaults = UserDefaults(suiteName: "CapturePasteSettingsTests.\(UUID())")!
        let board = NSPasteboard.withUniqueName()
        let spy = PasteArmSpy()
        let store = CaptureStore(preferences: defaults, clipboard: board, assistedPaste: spy)
        defer { store.stop(); board.releaseGlobally() }
        let capture = try shot("Automatic")
        store.pasteImageThenText = true
        store.autoCopyCapture = true
        store.captures = [capture]
        store.selectedID = capture.id
        store.autoCopyCompletedCapture(capture)
        store.autoCopyCompletedCapture(capture)
        XCTAssertEqual(spy.armed, [capture.id])
        var cancellations = spy.cancelCount
        store.copyImage()
        XCTAssertGreaterThan(spy.cancelCount, cancellations)
        XCTAssertNil(board.string(forType: .string))
        cancellations = spy.cancelCount
        store.copyText()
        XCTAssertGreaterThan(spy.cancelCount, cancellations)
        XCTAssertNil(board.data(forType: .png))
        cancellations = spy.cancelCount
        store.isRecordingShortcut = true
        XCTAssertGreaterThan(spy.cancelCount, cancellations)
    }

    @MainActor
    func testCaptureShortcutConflictLeavesRichClipboardAndDoesNotArm() throws {
        let defaults = UserDefaults(suiteName: "CapturePasteSettingsTests.\(UUID())")!
        CaptureShortcut(keyCode: 9, modifierFlags: .command)!.save(to: defaults)
        let board = NSPasteboard.withUniqueName()
        let spy = PasteArmSpy()
        let store = CaptureStore(preferences: defaults, clipboard: board, assistedPaste: spy)
        defer { store.stop(); board.releaseGlobally() }
        let capture = try shot("Conflict")
        store.captures = [capture]
        store.pasteImageThenText = true
        XCTAssertTrue(store.copyCapture(capture.id))
        XCTAssertTrue(spy.armed.isEmpty)
        XCTAssertNotNil(board.data(forType: .rtfd))
        XCTAssertTrue(store.statusNotice?.message.contains("capture shortcut other than ⌘V") == true)
    }

    @MainActor
    private func shot(_ name: String) throws -> CaptureResult {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 8, bitsPerPixel: 32)!
        rep.bitmapData?.initialize(repeating: 255, count: 16)
        return CaptureResult(appName: name, bundleIdentifier: "test.clipboard", windowTitle: name,
                             pngData: try XCTUnwrap(rep.representation(using: .png, properties: [:])),
                             accessibilityText: "Context for \(name)")
    }
}

@MainActor
private final class PasteArmSpy: AssistedPasteServing {
    var onResult: ((AssistedPasteResult) -> Void)?
    var armed: [UUID] = []
    var contexts: [String] = []
    var cancelCount = 0
    func arm(capture: CaptureResult, clipboard: NSPasteboard) -> Bool {
        armed.append(capture.id)
        contexts.append(capture.clipboardText)
        return true
    }
    func cancel() { cancelCount += 1 }
    func stop() { cancel() }
}
