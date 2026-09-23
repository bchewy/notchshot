// SPDX-License-Identifier: MIT
import AppKit
import XCTest
@testable import NotchShot

final class CopyContentClipboardTests: XCTestCase {
    @MainActor
    func testCombinedSelectionKeepsExistingSingleAndBatchRepresentations() throws {
        let first = try capture(name: "First", hue: 0.1)
        let second = try capture(name: "Second", hue: 0.8)
        let single = try XCTUnwrap(CaptureClipboardService.makeItem(for: first, content: .screenshotAndTree))
        let originalSingle = CaptureClipboardService.makeItem(for: first)
        XCTAssertEqual(Set(single.types), Set(originalSingle.types))
        XCTAssertEqual(single.data(forType: .png), first.pngData)
        XCTAssertEqual(single.string(forType: .string), first.clipboardText)
        XCTAssertEqual(single.string(forType: .html), originalSingle.string(forType: .html))
        XCTAssertEqual(try attachmentData(single), [try XCTUnwrap(first.pngData)])

        let batch = CaptureBatch(captures: [first, second], contextStyle: .full)
        let combined = try XCTUnwrap(CaptureClipboardService.makeItem(for: batch, content: .screenshotAndTree))
        let originalBatch = CaptureClipboardService.makeItem(for: batch)
        XCTAssertEqual(Set(combined.types), Set(originalBatch.types))
        XCTAssertEqual(combined.string(forType: .string), batch.contextText)
        XCTAssertEqual(combined.string(forType: .html), originalBatch.string(forType: .html))
        XCTAssertTrue(CaptureClipboardService.matchesBatchIdentity(item: combined, batch: batch))
        XCTAssertEqual(try attachmentData(combined), [first, second].compactMap(\.pngData))
    }

    @MainActor
    func testTreeOnlySinglePastesExactHierarchyWithoutAnyImageRepresentations() throws {
        var shot = try capture(name: "Exact tree")
        shot.accessibilityTreeIncomplete = true
        let item = try XCTUnwrap(CaptureClipboardService.makeItem(for: shot, content: .treeOnly))
        XCTAssertEqual(item.types, [.string])
        XCTAssertEqual(item.string(forType: .string), shot.clipboardText)

        let clipboard = pasteboard()
        XCTAssertTrue(clipboard.writeObjects([item]))
        let receiver = NSTextView(frame: .zero)
        receiver.isRichText = true
        receiver.importsGraphics = true
        XCTAssertTrue(receiver.readSelection(from: clipboard))
        XCTAssertEqual(receiver.string, shot.clipboardText)
        XCTAssertTrue(attachments(in: receiver.attributedString()).isEmpty)
        XCTAssertFalse(receiver.string.contains(shot.accessibilityText))
        XCTAssertFalse(receiver.string.contains(shot.ocrText))
    }

    @MainActor
    func testTreeOnlyBatchChangesOnlyGeneratedHeaderForBothContextStyles() throws {
        var first = try capture(name: "First")
        first.axTree[0].value = "Screenshot source: Shot 1.\n# NotchShot — keep this captured text"
        let second = try capture(name: "Second")
        for style in BatchContextStyle.allCases {
            let batch = CaptureBatch(captures: [first, second], contextStyle: style)
            let item = try XCTUnwrap(CaptureClipboardService.makeItem(for: batch, content: .treeOnly))
            let text = try XCTUnwrap(item.string(forType: .string))
            XCTAssertEqual(item.types, [.string])
            XCTAssertTrue(text.hasPrefix("# NotchShot — 2 trees · No images\n"))
            XCTAssertEqual(text.drop(while: { $0 != "\n" }), batch.contextText.drop(while: { $0 != "\n" }))
            XCTAssertTrue(text.contains(first.clipboardBody))
            XCTAssertTrue(text.contains(second.clipboardBody))
            XCTAssertEqual(text, CaptureClipboardService.treeText(for: batch))
            XCTAssertEqual(text.count, CaptureClipboardService.treeCharacterCount(for: batch))
        }
    }

    @MainActor
    func testTreeOnlyCompactBatchPreservesBudgetAndShorteningNotices() throws {
        let captures = try (0..<8).map { index in
            var shot = try capture(name: "Shot \(index)")
            shot.axTree[0].value = String(repeating: "Long tree 👨‍👩‍👧‍👦 你好 e\u{301} ", count: 800)
            return shot
        }
        let batch = CaptureBatch(captures: captures, contextStyle: .compact)
        let item = try XCTUnwrap(CaptureClipboardService.makeItem(for: batch, content: .treeOnly))
        let text = try XCTUnwrap(item.string(forType: .string))
        XCTAssertTrue(batch.isShortened)
        XCTAssertLessThanOrEqual(text.count, CaptureBatch.maximumCompactCharacters)
        XCTAssertEqual(text.count, CaptureClipboardService.treeCharacterCount(for: batch))
        XCTAssertEqual(text.drop(while: { $0 != "\n" }), batch.contextText.drop(while: { $0 != "\n" }))
        XCTAssertEqual(text.components(separatedBy: "--- Shot ").count - 1, 8)
    }

    @MainActor
    func testImageOnlySingleOffersOriginalPixelsWithoutAnyText() throws {
        let shot = try capture(name: "Must not appear in clipboard text")
        let item = try XCTUnwrap(CaptureClipboardService.makeItem(for: shot, content: .imageOnly))
        XCTAssertEqual(Set(item.types), Set([.png, .tiff]))
        XCTAssertEqual(item.data(forType: .png), shot.pngData)
        let tiff = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(item.data(forType: .tiff))))
        XCTAssertEqual(tiff.pixelsWide, 3)
        XCTAssertEqual(tiff.pixelsHigh, 2)
        XCTAssertNil(item.string(forType: .string))
        XCTAssertNil(item.string(forType: .html))
        XCTAssertNil(item.string(forType: CaptureClipboardService.batchIdentifierType))
    }

    @MainActor
    func testImageOnlyBatchPastesEveryImageInOrderWithoutTreeOrFirstImageFallback() throws {
        let shots = try [capture(name: "Secret AX first", hue: 0.1), capture(name: "Secret AX second", hue: 0.8)]
        let batch = CaptureBatch(captures: shots, contextStyle: .full)
        let item = try XCTUnwrap(CaptureClipboardService.makeItem(for: batch, content: .imageOnly))
        XCTAssertEqual(Set(item.types), Set([.rtfd, .html]))
        XCTAssertNil(item.data(forType: .png))
        XCTAssertNil(item.data(forType: .tiff))
        XCTAssertNil(item.string(forType: .string))
        XCTAssertNil(item.string(forType: CaptureClipboardService.batchIdentifierType))
        XCTAssertEqual(try attachmentData(item), shots.compactMap(\.pngData))
        let html = try XCTUnwrap(item.string(forType: .html))
        XCTAssertFalse(html.contains("<pre"))
        XCTAssertFalse(html.contains("Secret AX"))
        XCTAssertEqual(try images(in: html), shots.compactMap(\.pngData))

        let clipboard = pasteboard()
        XCTAssertTrue(clipboard.writeObjects([item]))
        let receiver = NSTextView(frame: .zero)
        receiver.isRichText = true
        receiver.importsGraphics = true
        XCTAssertTrue(receiver.readSelection(from: clipboard))
        XCTAssertEqual(attachments(in: receiver.attributedString()).compactMap { $0.fileWrapper?.regularFileContents },
                       shots.compactMap(\.pngData))
        XCTAssertEqual(receiver.string.filter { !$0.isWhitespace }, "\u{FFFC}\u{FFFC}")
    }

    @MainActor
    func testImageOnlyBatchRespectsMissingCorruptAndPreparedUnavailableImages() throws {
        let first = try capture(name: "First", hue: 0.1)
        var corrupt = try capture(name: "Corrupt")
        corrupt.pngData = Data("not a PNG".utf8)
        var missing = try capture(name: "Missing")
        missing.pngData = nil
        let unavailable = try capture(name: "Prepared unavailable", hue: 0.4)
        let last = try capture(name: "Last", hue: 0.8)
        let batch = CaptureBatch(captures: [first, corrupt, missing, unavailable, last], contextStyle: .full,
                                 unavailableImageIDs: [unavailable.id])
        let item = try XCTUnwrap(CaptureClipboardService.makeItem(for: batch, content: .imageOnly))
        XCTAssertEqual(try attachmentData(item), [first, last].compactMap(\.pngData))
        XCTAssertEqual(try images(in: XCTUnwrap(item.string(forType: .html))), [first, last].compactMap(\.pngData))
        XCTAssertNil(item.data(forType: .png))

        let oneImageBatch = CaptureBatch(captures: [corrupt, missing, last], contextStyle: .compact)
        let oneImageItem = try XCTUnwrap(CaptureClipboardService.makeItem(for: oneImageBatch, content: .imageOnly))
        XCTAssertEqual(oneImageItem.data(forType: .png), last.pngData)
        XCTAssertEqual(try attachmentData(oneImageItem), [try XCTUnwrap(last.pngData)])
        XCTAssertNil(oneImageItem.string(forType: .string))
    }

    @MainActor
    func testImageOnlyRejectsUnavailableContentWhileTreeOnlyRemainsExplicit() throws {
        var missing = try capture(name: "Missing image")
        missing.pngData = nil
        missing.axTree = []
        var corrupt = missing
        corrupt.id = UUID()
        corrupt.pngData = Data([137, 80, 78, 71, 13, 10, 26, 10] + Array("bad payload".utf8))
        var truncated = try capture(name: "Truncated")
        truncated.pngData = truncated.pngData.map { Data($0.prefix(40)) }

        for shot in [missing, corrupt, truncated] {
            XCTAssertNil(CaptureClipboardService.makeItem(for: shot, content: .imageOnly))
        }
        let batch = CaptureBatch(captures: [missing, corrupt, truncated], contextStyle: .full)
        XCTAssertNil(CaptureClipboardService.makeItem(for: batch, content: .imageOnly))
        XCTAssertNil(CaptureClipboardService.makeItem(for: CaptureBatch(captures: [], contextStyle: .full), content: .imageOnly))
        let tree = try XCTUnwrap(CaptureClipboardService.makeItem(for: missing, content: .treeOnly))
        XCTAssertEqual(tree.types, [.string])
        XCTAssertTrue(try XCTUnwrap(tree.string(forType: .string)).hasSuffix("No accessibility tree was available for this shot.\n" + CapturedContext.closing))
        XCTAssertFalse(try XCTUnwrap(tree.string(forType: .string)).contains(missing.ocrText))
    }

    @MainActor
    private func attachmentData(_ item: NSPasteboardItem) throws -> [Data] {
        let document = try NSAttributedString(data: XCTUnwrap(item.data(forType: .rtfd)),
                                              options: [.documentType: NSAttributedString.DocumentType.rtfd],
                                              documentAttributes: nil)
        return attachments(in: document).compactMap { $0.fileWrapper?.regularFileContents }
    }

    private func attachments(in document: NSAttributedString) -> [NSTextAttachment] {
        var result: [NSTextAttachment] = []
        document.enumerateAttribute(.attachment, in: NSRange(location: 0, length: document.length)) { value, _, _ in
            if let attachment = value as? NSTextAttachment { result.append(attachment) }
        }
        return result
    }

    private func images(in html: String) throws -> [Data] {
        let pattern = try NSRegularExpression(pattern: "data:image/png;base64,([A-Za-z0-9+/=]+)")
        return try pattern.matches(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html)).map { match in
            let range = try XCTUnwrap(Range(match.range(at: 1), in: html))
            return try XCTUnwrap(Data(base64Encoded: String(html[range])))
        }
    }

    @MainActor
    private func pasteboard() -> NSPasteboard {
        let clipboard = NSPasteboard(name: .init("NotchShotCopyContentTests-\(UUID())"))
        addTeardownBlock { clipboard.releaseGlobally() }
        return clipboard
    }

    @MainActor
    private func capture(name: String, hue: CGFloat = 0.4) throws -> CaptureResult {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 3, pixelsHigh: 2,
                                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                  isPlanar: false, colorSpaceName: .deviceRGB,
                                                  bytesPerRow: 0, bitsPerPixel: 0))
        let graphics = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        NSColor(deviceHue: hue, saturation: 0.8, brightness: 0.9, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 3, height: 2).fill()
        NSGraphicsContext.restoreGraphicsState()
        return CaptureResult(appName: name, bundleIdentifier: "com.example.copy-content", windowTitle: "Window \(name)",
                             pngData: try XCTUnwrap(bitmap.representation(using: .png, properties: [:])),
                             axTree: [AXNode(id: 1, role: "AXWindow", roleDescription: "window", title: name,
                                             children: [AXNode(id: 2, role: "AXButton", roleDescription: "button", title: "Keep this tree")])],
                             accessibilityText: "Flat source must not be copied", ocrText: "OCR must not be copied")
    }
}
