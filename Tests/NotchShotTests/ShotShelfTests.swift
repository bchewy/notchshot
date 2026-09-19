// SPDX-License-Identifier: MIT
import AppKit
import XCTest
@testable import NotchShot

final class ShotShelfTests: XCTestCase {
    @MainActor
    func testPartialCaptureCannotBeCollectedOrDroppedUntilCaptureFinishes() {
        let store = makeStore()
        defer { store.stop() }
        var partial = makeCapture()
        partial.axTree = []
        partial.accessibilityText = ""
        store.pendingCapture = partial
        store.isCapturing = true
        let pasteboard = makeInternalPasteboard(for: partial.id)
        defer { pasteboard.releaseGlobally() }

        store.acceptPendingCapture()
        XCTAssertFalse(store.canReceiveDrop(pasteboard))
        XCTAssertFalse(store.receiveDrop(pasteboard))
        store.beginCardDrag()
        store.endCardDrag(accepted: true)

        XCTAssertTrue(store.captures.isEmpty)
        XCTAssertEqual(store.pendingCapture?.id, partial.id)
        XCTAssertNil(store.selectedID)

        var complete = makeCapture()
        complete.id = partial.id
        store.pendingCapture = complete
        store.isCapturing = false
        store.acceptPendingCapture()
        XCTAssertNil(store.pendingCapture)
        XCTAssertEqual(store.captures.count, 1)
        XCTAssertEqual(store.selectedCapture?.elementCount, complete.elementCount)
        XCTAssertEqual(store.selectedCapture?.accessibilityText, complete.accessibilityText)
    }

    @MainActor
    func testInternalUUIDDropPreservesFullCaptureAndDoesNotDuplicateIt() throws {
        let store = makeStore()
        defer { store.stop() }
        let original = makeCapture()
        store.pendingCapture = original
        let pasteboard = makeInternalPasteboard(for: original.id)
        defer { pasteboard.releaseGlobally() }
        // Alternate representations must not replace the existing structured
        // capture or turn its full accessibility tree into flattened text.
        pasteboard.addTypes([.png, .string], owner: nil)
        XCTAssertTrue(pasteboard.setData(Data([1, 2, 3]), forType: .png))
        XCTAssertTrue(pasteboard.setString("Flattened alternate representation", forType: .string))

        store.beginCardDrag()
        XCTAssertTrue(store.canReceiveDrop(pasteboard))
        XCTAssertTrue(store.receiveDrop(pasteboard))
        store.endCardDrag(accepted: true)

        let collected = try XCTUnwrap(store.selectedCapture)
        XCTAssertEqual(collected.id, original.id)
        XCTAssertEqual(collected.date, original.date)
        XCTAssertEqual(collected.appName, original.appName)
        XCTAssertEqual(collected.bundleIdentifier, original.bundleIdentifier)
        XCTAssertEqual(collected.windowTitle, original.windowTitle)
        XCTAssertEqual(collected.windowID, original.windowID)
        XCTAssertEqual(collected.pngData, original.pngData)
        XCTAssertEqual(collected.accessibilityText, original.accessibilityText)
        XCTAssertEqual(collected.ocrText, original.ocrText)
        XCTAssertEqual(collected.warnings, original.warnings)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(try encoder.encode(collected.axTree), try encoder.encode(original.axTree))
        XCTAssertNil(store.pendingCapture)

        XCTAssertTrue(store.receiveDrop(pasteboard))
        XCTAssertEqual(store.captures.map(\.id), [original.id])
        XCTAssertEqual(store.selectedID, original.id)
    }

    @MainActor
    func testUnknownInternalUUIDIsRejectedEvenWithImportableAlternateText() {
        let store = makeStore()
        defer { store.stop() }
        let pending = makeCapture()
        store.pendingCapture = pending
        let pasteboard = makeInternalPasteboard(for: UUID())
        defer { pasteboard.releaseGlobally() }
        pasteboard.addTypes([.string], owner: nil)
        XCTAssertTrue(pasteboard.setString("This alternate text must not become a new capture", forType: .string))

        XCTAssertFalse(store.canReceiveDrop(pasteboard))
        XCTAssertFalse(store.receiveDrop(pasteboard))
        XCTAssertEqual(store.pendingCapture?.id, pending.id)
        XCTAssertTrue(store.captures.isEmpty)
        XCTAssertFalse(store.isImporting)
    }

    @MainActor
    func testClearHistoryPreventsLateDragCompletionFromResurrectingCapture() {
        for accepted in [true, false] {
            let store = makeStore()
            defer { store.stop() }
            let previous = makeCapture()
            store.pendingCapture = previous
            store.acceptPendingCapture()
            let pending = makeCapture()
            store.pendingCapture = pending
            let pasteboard = makeInternalPasteboard(for: pending.id)
            defer { pasteboard.releaseGlobally() }
            var dismissCount = 0
            store.onDismissCard = { dismissCount += 1 }
            store.beginCardDrag()
            store.isDropTargeted = true

            store.clearHistory()
            XCTAssertNil(store.pendingCapture)
            XCTAssertTrue(store.captures.isEmpty)
            XCTAssertNil(store.selectedID)
            XCTAssertEqual(dismissCount, 1)

            store.endCardDrag(accepted: accepted)
            XCTAssertNil(store.pendingCapture)
            XCTAssertTrue(store.captures.isEmpty)
            XCTAssertNil(store.selectedID)
            XCTAssertFalse(store.isDropTargeted)
            XCTAssertFalse(store.canReceiveDrop(pasteboard))
            XCTAssertFalse(store.receiveDrop(pasteboard))
        }
    }

    @MainActor
    func testDismissingPendingCardKeepsHistoryAndIgnoresLateAcceptedDrag() {
        let store = makeStore()
        defer { store.stop() }
        let previous = makeCapture()
        store.pendingCapture = previous
        store.acceptPendingCapture()
        store.pendingCapture = makeCapture()
        var dismissCount = 0
        store.onDismissCard = { dismissCount += 1 }

        store.beginCardDrag()
        store.dismissPendingCapture()
        store.endCardDrag(accepted: true)

        XCTAssertNil(store.pendingCapture)
        XCTAssertEqual(store.captures.map(\.id), [previous.id])
        XCTAssertEqual(store.selectedID, previous.id)
        XCTAssertEqual(dismissCount, 1)
    }

    func testImportedTextKeepsItsOwnContextAndExportLabel() throws {
        let text = "A dropped note\nwith a second line."
        let capture = CaptureResult(appName: "Imported Appshot", bundleIdentifier: "",
                                    windowTitle: "Imported Appshot", importedText: text)
        XCTAssertEqual(capture.readableText, text)
        XCTAssertTrue(capture.contextText.contains("## Imported text\n" + text))
        XCTAssertFalse(capture.contextText.contains("## Accessibility text"))
        XCTAssertFalse(capture.contextText.contains("## Accessibility tree"))
        XCTAssertFalse(capture.contextText.contains("(OCR)"))

        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("NotchShot-ShelfTest-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let folder = try ExportService.export(capture, to: parent)

        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("imported-text.txt"), encoding: .utf8), text)
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("context.md"), encoding: .utf8), capture.contextText)
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("accessibility.txt"), encoding: .utf8), "")
        let tree = try JSONDecoder().decode([AXNode].self, from: Data(contentsOf: folder.appendingPathComponent("accessibility-tree.json")))
        XCTAssertTrue(tree.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("ocr.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("screenshot.png").path))
    }

    @MainActor
    private func makeStore() -> CaptureStore {
        let (preferences, clipboard) = isolatedStoreDependencies()
        let store = CaptureStore(preferences: preferences, clipboard: clipboard)
        store.autoCollectCaptures = false
        return store
    }

    @MainActor
    private func makeInternalPasteboard(for id: UUID) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: .init("NotchShot-ShelfTest-\(UUID())"))
        pasteboard.declareTypes([CaptureCardPasteboard.captureID], owner: nil)
        XCTAssertTrue(pasteboard.setString(id.uuidString, forType: CaptureCardPasteboard.captureID))
        return pasteboard
    }

    private func makeCapture() -> CaptureResult {
        let field = AXNode(id: 3, role: "AXTextField", roleDescription: "text field", title: "Address",
                           value: "https://example.com", help: "Enter a URL", url: "https://example.com",
                           placeholder: "Search", isSettable: true)
        let group = AXNode(id: 2, role: "AXGroup", roleDescription: "toolbar", children: [field])
        let root = AXNode(id: 1, role: "AXWindow", roleDescription: "standard window", title: "Example", children: [group])
        // A real 1×1 PNG; internal drops should preserve these exact bytes.
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")!
        return CaptureResult(date: Date(timeIntervalSince1970: 1_700_000_000), appName: "Browser",
                             bundleIdentifier: "com.example.browser", windowTitle: "Example", windowID: 42,
                             pngData: png, axTree: [root], accessibilityText: "Example\nAddress\nhttps://example.com",
                             ocrText: "Recognized screenshot text", warnings: ["Fixture capture note"])
    }
}
