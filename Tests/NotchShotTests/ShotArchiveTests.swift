// SPDX-License-Identifier: MIT
import AppKit
import XCTest
@testable import NotchShot

final class ShotArchiveTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchShotArchiveTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("History", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    func testSavedShotRoundTripsEverythingButItsWindowPlacement() async throws {
        let archive = ShotArchive(root: root)
        var capture = makeHistoryCapture(appName: "Notes", title: "Weekend", text: "Coffee spot", png: historyPNG(width: 1200, height: 800))
        capture.windowID = 42
        capture.ocrText = "OCR words"
        capture.importedText = "Imported words"
        capture.warnings = ["Tree truncated"]
        capture.accessibilityTreeIncomplete = true
        capture.sourceWindowFrame = CGRect(x: 1, y: 2, width: 3, height: 4)

        let entry = try await archive.save(capture)
        XCTAssertEqual(entry.id, capture.id)
        XCTAssertEqual(entry.capturedAt, capture.date)
        XCTAssertTrue(entry.hasScreenshot)
        XCTAssertEqual(entry.elementCount, 3)
        XCTAssertFalse(entry.isPinned)
        let listed = await archive.entries()
        XCTAssertEqual(listed, [entry])

        let restored = try await archive.capture(capture.id)
        XCTAssertEqual(StoredCapture(restored), StoredCapture(capture))
        XCTAssertEqual(restored.pngData, capture.pngData)
        XCTAssertNil(restored.sourceWindowFrame, "Window placement is runtime-only.")

        let thumbnailData = await archive.thumbnail(capture.id)
        let thumbnail = try XCTUnwrap(NSImage(data: XCTUnwrap(thumbnailData)))
        let pixels = try XCTUnwrap(thumbnail.representations.first)
        XCTAssertEqual(max(pixels.pixelsWide, pixels.pixelsHigh), 320)
    }

    func testShotWithoutScreenshotSavesItsText() async throws {
        let archive = ShotArchive(root: root)
        let capture = makeHistoryCapture(appName: "Dropped text", title: "Clipboard", text: "Only words", png: nil)
        let entry = try await archive.save(capture)
        XCTAssertFalse(entry.hasScreenshot)
        let thumbnail = await archive.thumbnail(capture.id)
        XCTAssertNil(thumbnail)
        let restored = try await archive.capture(capture.id)
        XCTAssertNil(restored.pngData)
        XCTAssertEqual(restored.accessibilityText, "Only words")
    }

    func testOnlyCompleteShotsAreListedAndInterruptedSavesAreCleanedUp() async throws {
        let archive = ShotArchive(root: root)
        let kept = makeHistoryCapture(appName: "Kept", title: "One", text: "a", png: historyPNG())
        let first = try await archive.save(kept)
        let again = try await archive.save(kept)
        XCTAssertEqual(first, again, "A shot is saved once.")

        let staging = root.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        let entryless = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let corrupt = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        for folder in [staging, entryless, corrupt] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        }
        try Data("{".utf8).write(to: corrupt.appendingPathComponent("entry.json"))
        try Data("x".utf8).write(to: root.appendingPathComponent("notes.txt"))

        let entries = await archive.entries()
        XCTAssertEqual(entries.map(\.id), [kept.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path), "Leftovers from an interrupted save are removed.")
    }

    func testPinsDeletionAndClearingPersist() async throws {
        let archive = ShotArchive(root: root)
        let a = makeHistoryCapture(appName: "A", title: "a", text: "a", png: historyPNG(), date: Date(timeIntervalSince1970: 100))
        let b = makeHistoryCapture(appName: "B", title: "b", text: "b", png: nil, date: Date(timeIntervalSince1970: 200))
        _ = try await archive.save(a)
        _ = try await archive.save(b)
        let pinned = try await archive.setPinned(true, for: a.id)
        XCTAssertTrue(pinned.isPinned)

        let reopened = ShotArchive(root: root)
        let listed = await reopened.entries()
        XCTAssertEqual(listed.map(\.id), [b.id, a.id], "Newest first.")
        XCTAssertEqual(listed.map(\.isPinned), [false, true])

        try await reopened.delete(b.id)
        try await reopened.delete(b.id)
        let afterDelete = await reopened.entries()
        XCTAssertEqual(afterDelete.map(\.id), [a.id])
        let bytes = await reopened.storageBytes()
        XCTAssertGreaterThan(bytes, 0)

        try await reopened.deleteAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        let empty = await reopened.entries()
        let emptyBytes = await reopened.storageBytes()
        XCTAssertEqual(empty, [])
        XCTAssertEqual(emptyBytes, 0)
    }

    func testShelfOrderRoundTripsAndHistoryIsPrivateToThisUser() async throws {
        let archive = ShotArchive(root: root)
        let emptyShelf = await archive.shelf()
        XCTAssertEqual(emptyShelf, [])
        let order = [UUID(), UUID(), UUID()]
        try await archive.saveShelf(order)
        let restored = await ShotArchive(root: root).shelf()
        XCTAssertEqual(restored, order)

        let permissions = try FileManager.default.attributesOfItem(atPath: root.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o700)
    }

    func testSearchNeedsEveryWordAndIgnoresCaseAccentsAndWidth() {
        let entry = ShotHistoryEntry(capture: makeHistoryCapture(
            appName: "Notes", title: "Café Résumé", text: "Find a new coffee spot. ＦＵＬＬ width", png: nil))
        for query in ["", "   ", "cafe", "CAFÉ résume", "coffee notes", "full", "spot find"] {
            XCTAssertTrue(entry.matches(ShotHistoryEntry.terms(in: query)), query)
        }
        for query in ["tea", "coffee tea", "safari"] {
            XCTAssertFalse(entry.matches(ShotHistoryEntry.terms(in: query)), query)
        }

        let huge = ShotHistoryEntry(capture: makeHistoryCapture(
            appName: "Big", title: "Tree", text: String(repeating: "x", count: 150_000) + " needle", png: nil))
        XCTAssertEqual(huge.searchText.count, ShotHistoryEntry.maximumSearchCharacters)
        XCTAssertFalse(huge.matches(["needle"]), "Search covers the first part of very large windows.")
    }
}

func makeHistoryCapture(appName: String, title: String, text: String, png: Data?,
                        date: Date = Date(timeIntervalSince1970: 1_000_000)) -> CaptureResult {
    var capture = CaptureResult(appName: appName, bundleIdentifier: "com.example.\(appName.lowercased())", windowTitle: title)
    capture.date = date
    capture.pngData = png
    capture.accessibilityText = text
    capture.axTree = [AXNode(id: 1, role: "AXWindow", roleDescription: "window", title: title, children: [
        AXNode(id: 2, role: "AXStaticText", roleDescription: "text", value: text),
        AXNode(id: 3, role: "AXLink", roleDescription: "link", title: "Docs", url: "https://example.com", isSettable: true),
    ])]
    return capture
}

func historyPNG(width: Int = 40, height: Int = 30) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                  samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                  bytesPerRow: 0, bitsPerPixel: 0)!
    return bitmap.representation(using: .png, properties: [:])!
}
