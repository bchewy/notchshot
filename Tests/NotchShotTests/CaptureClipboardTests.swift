// SPDX-License-Identifier: MIT
import AppKit
import XCTest
@testable import NotchShot

final class CaptureClipboardTests: XCTestCase {
    @MainActor
    func testIncompleteTreeCopyDisclosesCaptureLimitsWithoutDuplicatingOtherSources() throws {
        var capture = try makeCapture()
        capture.accessibilityTreeIncomplete = true
        let item = CaptureClipboardService.makeItem(for: capture)
        let text = try XCTUnwrap(item.string(forType: .string))
        XCTAssertTrue(text.hasPrefix(CapturedContext.opening + "\n[Accessibility tree is incomplete:"))
        XCTAssertTrue(text.hasSuffix(capture.treeText + "\n" + CapturedContext.closing))
        XCTAssertFalse(text.contains(capture.ocrText))
        XCTAssertFalse(text.contains(capture.accessibilityText))
        XCTAssertEqual(item.data(forType: .png), capture.pngData)
    }

    @MainActor
    func testNativeRichTextPasteReceivesScreenshotThenExactAccessibilityTree() throws {
        let capture = try makeCapture()
        let clipboard = makeClipboard()
        XCTAssertTrue(clipboard.writeObjects([CaptureClipboardService.makeItem(for: capture)]))

        let receiver = makeRichTextReceiver()
        XCTAssertTrue(receiver.readSelection(from: clipboard))

        try assertCombinedPaste(receiver, matches: capture)
        XCTAssertFalse(receiver.string.contains(capture.accessibilityText))
        XCTAssertFalse(receiver.string.contains(capture.ocrText))
        XCTAssertFalse(receiver.string.contains(capture.importedText))
        XCTAssertFalse(receiver.string.contains("## Capture notes"))
    }

    @MainActor
    func testPlainTextReceiverFallsBackToExactContextWithoutAttachmentPlaceholder() throws {
        let capture = try makeCapture()
        let clipboard = makeClipboard()
        XCTAssertTrue(clipboard.writeObjects([CaptureClipboardService.makeItem(for: capture)]))
        let receiver = NSTextView(frame: .zero)
        receiver.isRichText = false
        receiver.importsGraphics = false

        XCTAssertTrue(receiver.readSelection(from: clipboard))
        XCTAssertEqual(receiver.string, capture.clipboardText)
        XCTAssertFalse(receiver.string.contains("\u{FFFC}"))
    }

    @MainActor
    func testOneClipboardItemOffersRichContentAndOriginalImageAndTextFallbacks() throws {
        let capture = try makeCapture()
        let clipboard = makeClipboard()
        XCTAssertTrue(clipboard.writeObjects([CaptureClipboardService.makeItem(for: capture)]))

        let items = try XCTUnwrap(clipboard.pasteboardItems)
        XCTAssertEqual(items.count, 1, "The screenshot and context must remain one shot, including when re-imported.")
        let item = try XCTUnwrap(items.first)
        XCTAssertNotNil(item.data(forType: .rtfd))
        XCTAssertNotNil(item.string(forType: .html))
        XCTAssertEqual(item.data(forType: .png), capture.pngData)
        XCTAssertEqual(item.string(forType: .string), capture.clipboardText)
        let tiff = try XCTUnwrap(item.data(forType: .tiff))
        let decoded = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        XCTAssertEqual(decoded.pixelsWide, 3)
        XCTAssertEqual(decoded.pixelsHigh, 2)
        XCTAssertNil(item.string(forType: .fileURL), "A shot must not depend on a temporary file surviving until paste.")
    }

    @MainActor
    func testHTMLContainsSelfContainedImageAndEscapesCapturedMarkup() throws {
        let capture = try makeCapture()
        let item = CaptureClipboardService.makeItem(for: capture)
        let html = try XCTUnwrap(item.string(forType: .html))
        let imagePattern = try NSRegularExpression(pattern: "data:image/png;base64,([A-Za-z0-9+/=]+)")
        let fullRange = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = imagePattern.matches(in: html, range: fullRange)
        XCTAssertEqual(matches.count, 1)
        let match = try XCTUnwrap(matches.first)
        let base64Range = try XCTUnwrap(Range(match.range(at: 1), in: html))
        XCTAssertEqual(Data(base64Encoded: String(html[base64Range])), capture.pngData)

        XCTAssertFalse(html.contains("<script>alert(\"capture\")</script>"), "Captured app text must remain text, never executable markup.")
        XCTAssertTrue(html.contains("&lt;script&gt;"))
        XCTAssertTrue(html.contains("&lt;/script&gt;"))
        XCTAssertTrue(html.contains("A &amp; B"))
        XCTAssertTrue(html.contains("&quot;capture&quot;"))
        XCTAssertFalse(html.contains("## Accessibility tree"))
        XCTAssertTrue(html.contains("button Save &amp; close"))
        let imagePosition = try XCTUnwrap(html.range(of: "data:image/png;base64,"))
        let contextPosition = try XCTUnwrap(html.range(of: "Window: &quot;Window"))
        XCTAssertLessThan(imagePosition.lowerBound, contextPosition.lowerBound)
    }

    @MainActor
    func testMissingTreeIsExplicitAndDoesNotMislabelOCRAsAccessibilityContent() throws {
        var capture = try makeCapture()
        capture.axTree = []
        let item = CaptureClipboardService.makeItem(for: capture)
        let text = try XCTUnwrap(item.string(forType: .string))
        XCTAssertEqual(text, CapturedContext.opening
                       + "\nWindow: \"\(capture.windowTitle)\", App: \(capture.appName).\nNo accessibility tree was available for this shot.\n"
                       + CapturedContext.closing)
        XCTAssertFalse(text.contains(capture.ocrText))
        XCTAssertFalse(text.contains(capture.accessibilityText))
        XCTAssertFalse(text.contains(capture.importedText))
        XCTAssertEqual(item.data(forType: .png), capture.pngData)
        // Detailed source data remains available to explicit text copies/exports.
        XCTAssertTrue(capture.contextText.contains(capture.ocrText))
        XCTAssertTrue(capture.contextText.contains(capture.accessibilityText))
        XCTAssertTrue(capture.contextText.contains(capture.importedText))
    }

    @MainActor
    func testMissingScreenshotKeepsCompleteContextPasteable() throws {
        var capture = try makeCapture()
        capture.pngData = nil
        try assertTextOnlyFallback(capture)
    }

    @MainActor
    func testCorruptScreenshotDoesNotPublishBrokenImageOrLoseContext() throws {
        var capture = try makeCapture()
        capture.pngData = Data("not an image".utf8)
        try assertTextOnlyFallback(capture)
    }

    @MainActor
    func testManualHoveredShotCopyPublishesCombinedContentForTheHoveredID() throws {
        let fixture = makeStore()
        defer { fixture.store.stop() }
        var selected = try makeCapture()
        selected.appName = "Selected shot that must not be copied"
        selected.accessibilityText = "Wrong selected content"
        let hovered = try makeCapture()
        fixture.store.captures = [selected, hovered]
        fixture.store.selectedID = selected.id
        fixture.store.page = .detail

        XCTAssertTrue(fixture.store.copyCapture(hovered.id))

        let receiver = makeRichTextReceiver()
        XCTAssertTrue(receiver.readSelection(from: fixture.clipboard))
        try assertCombinedPaste(receiver, matches: hovered)
        XCTAssertFalse(receiver.string.contains(selected.appName))
        XCTAssertEqual(fixture.store.selectedID, selected.id)
        XCTAssertEqual(fixture.store.page, .detail)
    }

    @MainActor
    func testAutomaticCopyPublishesCombinedContentWhenCaptureIsComplete() throws {
        let fixture = makeStore()
        defer { fixture.store.stop() }
        let capture = try makeCapture()
        fixture.store.autoCopyCapture = true
        fixture.store.isCapturing = false

        fixture.store.autoCopyCompletedCapture(capture)

        let receiver = makeRichTextReceiver()
        XCTAssertTrue(receiver.readSelection(from: fixture.clipboard))
        try assertCombinedPaste(receiver, matches: capture)
        XCTAssertNotNil(fixture.clipboard.string(forType: .html))
    }

    @MainActor
    private func assertCombinedPaste(_ receiver: NSTextView, matches capture: CaptureResult,
                                     file: StaticString = #filePath, line: UInt = #line) throws {
        let content = receiver.attributedString()
        XCTAssertTrue(content.string.hasSuffix(capture.clipboardText), "A rich paste must end with the exact copied context.", file: file, line: line)
        XCTAssertTrue(content.string.contains(capture.treeText), "A rich paste must retain the hierarchy exactly.", file: file, line: line)
        let prefixLength = content.string.count - capture.clipboardText.count
        XCTAssertGreaterThan(prefixLength, 0, file: file, line: line)
        if prefixLength > 0 {
            let prefix = String(content.string.prefix(prefixLength))
            XCTAssertEqual(prefix.trimmingCharacters(in: .whitespacesAndNewlines), "\u{FFFC}", "Only the image and spacing may precede the exact context.", file: file, line: line)
        }
        var attachments: [(NSTextAttachment, NSRange)] = []
        content.enumerateAttribute(.attachment, in: NSRange(location: 0, length: content.length)) { value, range, _ in
            if let attachment = value as? NSTextAttachment { attachments.append((attachment, range)) }
        }
        XCTAssertEqual(attachments.count, 1, file: file, line: line)
        let attachment = try XCTUnwrap(attachments.first, file: file, line: line)
        XCTAssertEqual(attachment.1.location, 0, file: file, line: line)
        XCTAssertEqual(attachment.0.fileWrapper?.regularFileContents, capture.pngData,
                       "The rich attachment must retain the original screenshot bytes.", file: file, line: line)
    }

    @MainActor
    private func assertTextOnlyFallback(_ capture: CaptureResult,
                                       file: StaticString = #filePath, line: UInt = #line) throws {
        let item = CaptureClipboardService.makeItem(for: capture)
        let clipboard = makeClipboard()
        XCTAssertTrue(clipboard.writeObjects([item]), file: file, line: line)
        XCTAssertNil(item.data(forType: .png), file: file, line: line)
        XCTAssertNil(item.data(forType: .tiff), file: file, line: line)
        XCTAssertNil(item.data(forType: .rtfd), file: file, line: line)
        XCTAssertEqual(item.string(forType: .string), capture.clipboardText, file: file, line: line)
        let html = try XCTUnwrap(item.string(forType: .html), file: file, line: line)
        XCTAssertFalse(html.contains("data:image/"), file: file, line: line)
        XCTAssertFalse(html.contains("<script>"), file: file, line: line)
        let receiver = NSTextView(frame: .zero)
        receiver.isRichText = false
        receiver.importsGraphics = false
        XCTAssertTrue(receiver.readSelection(from: clipboard), file: file, line: line)
        XCTAssertEqual(receiver.string, capture.clipboardText, file: file, line: line)
    }

    @MainActor
    private func makeRichTextReceiver() -> NSTextView {
        let receiver = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 500))
        receiver.isRichText = true
        receiver.importsGraphics = true
        return receiver
    }

    @MainActor
    private func makeClipboard() -> NSPasteboard {
        let clipboard = NSPasteboard(name: .init("NotchShotCaptureClipboardTests-\(UUID())"))
        addTeardownBlock { clipboard.releaseGlobally() }
        return clipboard
    }

    @MainActor
    private func makeStore() -> (store: CaptureStore, clipboard: NSPasteboard) {
        let suite = "NotchShotCaptureClipboardTests-\(UUID())"
        let preferences = UserDefaults(suiteName: suite)!
        preferences.set(false, forKey: "copySoundEnabled")
        preferences.set(false, forKey: "collapseAfterCopy")
        addTeardownBlock { preferences.removePersistentDomain(forName: suite) }
        let clipboard = makeClipboard()
        return (CaptureStore(preferences: preferences, clipboard: clipboard), clipboard)
    }

    @MainActor
    private func makeCapture() throws -> CaptureResult {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 3, pixelsHigh: 2,
                                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let mint = NSColor(deviceRed: 0.2, green: 0.8, blue: 0.6, alpha: 1)
        let orange = NSColor(deviceRed: 1, green: 0.5, blue: 0.1, alpha: 1)
        for x in 0..<3 {
            for y in 0..<2 { bitmap.setColor(x == y ? mint : orange, atX: x, y: y) }
        }
        return CaptureResult(date: Date(timeIntervalSince1970: 1_700_000_000),
                             appName: "Clipboard fixture — A & B", bundleIdentifier: "com.example.clipboard-fixture",
                             windowTitle: "Window <name> \"quoted\"",
                             pngData: try XCTUnwrap(bitmap.representation(using: .png, properties: [:])),
                             axTree: [AXNode(id: 1, role: "AXGroup", roleDescription: "group", title: "Root",
                                             children: [AXNode(id: 2, role: "AXButton", roleDescription: "button", title: "Save & close"),
                                                        AXNode(id: 3, role: "AXStaticText", roleDescription: "text", value: "<script>alert(\"capture\")</script> — 你好 📷")])],
                             accessibilityText: "First line\n<script>alert(\"capture\")</script>\nLast line — 你好 📷",
                             ocrText: "OCR text <with> symbols", importedText: "Imported 'context'",
                             warnings: ["Fixture note & complete context"])
    }
}
