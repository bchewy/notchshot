// SPDX-License-Identifier: MIT
import AppKit
import XCTest
@testable import NotchShot

final class BatchClipboardTests: XCTestCase {
    @MainActor
    func testNativeRichPasteReceivesEveryOrderedOriginalImageThenExactContext() throws {
        let captures = try [makeCapture(name: "First", hue: 0.1), makeCapture(name: "Second", hue: 0.4),
                            makeCapture(name: "Third", hue: 0.7)]
        let batch = CaptureBatch(captures: captures, contextStyle: .full)
        let clipboard = makeClipboard()
        XCTAssertTrue(clipboard.writeObjects([CaptureClipboardService.makeItem(for: batch)]))
        let receiver = NSTextView(frame: .zero)
        receiver.isRichText = true
        receiver.importsGraphics = true

        XCTAssertTrue(receiver.readSelection(from: clipboard))

        let document = receiver.attributedString()
        let attachments = attachments(in: document)
        XCTAssertEqual(attachments.count, 3)
        XCTAssertEqual(attachments.compactMap { $0.fileWrapper?.regularFileContents }, captures.compactMap(\.pngData))
        XCTAssertTrue(document.string.hasSuffix(batch.contextText))
        let prefix = document.string.dropLast(batch.contextText.count)
        XCTAssertEqual(prefix.filter { !$0.isWhitespace }, "\u{FFFC}\u{FFFC}\u{FFFC}")
        XCTAssertEqual(clipboard.pasteboardItems?.count, 1)
    }

    @MainActor
    func testDistinctImagesHaveUniqueAttachmentFilenames() throws {
        let first = try makeCapture(name: "First")
        let second = try makeCapture(name: "Second", hue: 0.8)
        let batch = CaptureBatch(captures: [first, second], contextStyle: .compact)
        let item = CaptureClipboardService.makeItem(for: batch)
        let document = try readDocument(item)
        let attached = attachments(in: document)
        XCTAssertEqual(attached.count, 2)
        let names = attached.compactMap { $0.fileWrapper?.preferredFilename }
        XCTAssertEqual(names.count, 2)
        XCTAssertEqual(Set(names).count, 2)
        XCTAssertTrue(names[0].contains("NotchShot-1-"))
        XCTAssertTrue(names[1].contains("NotchShot-2-"))
    }

    @MainActor
    func testIdenticalImageBytesStillPasteAsTwoSeparateShotAttachments() throws {
        let first = try makeCapture(name: "First")
        var second = first
        second.id = UUID()
        let batch = CaptureBatch(captures: [first, second], contextStyle: .compact)
        let item = CaptureClipboardService.makeItem(for: batch)
        let document = try readDocument(item)
        let attached = attachments(in: document)
        // AppKit can share the same RTFD resource for byte-identical originals.
        // The rich document must still contain both attachment occurrences.
        XCTAssertEqual(attached.count, 2)
        XCTAssertEqual(attached.compactMap { $0.fileWrapper?.regularFileContents }, [first, second].compactMap(\.pngData))
        XCTAssertEqual(document.string.filter { $0 == "\u{FFFC}" }.count, 2)
        XCTAssertNil(item.data(forType: .png))
    }

    @MainActor
    func testMultipleImagesNeverOfferOnlyFirstImageAsFallback() throws {
        let captures = try [makeCapture(name: "First"), makeCapture(name: "Second", hue: 0.9)]
        let item = CaptureClipboardService.makeItem(for: CaptureBatch(captures: captures, contextStyle: .compact))
        XCTAssertNil(item.data(forType: .png))
        XCTAssertNil(item.data(forType: .tiff))
        XCTAssertNotNil(item.data(forType: .rtfd))
        XCTAssertNotNil(item.string(forType: .html))
        XCTAssertNil(item.string(forType: .fileURL))
    }

    @MainActor
    func testOneImageAmongTextOnlyShotsOffersExactOriginalImageFallback() throws {
        var first = try makeCapture(name: "Text first")
        first.pngData = nil
        let second = try makeCapture(name: "Image second")
        let batch = CaptureBatch(captures: [first, second], contextStyle: .full)
        let item = CaptureClipboardService.makeItem(for: batch)
        XCTAssertEqual(item.data(forType: .png), second.pngData)
        XCTAssertEqual(attachments(in: try readDocument(item)).count, 1)
        XCTAssertEqual(item.string(forType: .string), batch.contextText)
        XCTAssertEqual(CaptureClipboardService.validImagePNGs(for: batch), [try XCTUnwrap(second.pngData)])
    }

    @MainActor
    func testLongUnicodeContextPastesExactlyIntoPlainTextReceiver() throws {
        var first = try makeCapture(name: "Long first")
        first.accessibilityText = String(repeating: "Long captured context — 你好 👨‍👩‍👧‍👦 📷\n", count: 4_000)
        let second = try makeCapture(name: "Last shot remains present")
        for style in [BatchContextStyle.compact, .full] {
            let batch = CaptureBatch(captures: [first, second], contextStyle: style)
            let clipboard = makeClipboard()
            XCTAssertTrue(clipboard.writeObjects([CaptureClipboardService.makeItem(for: batch)]))
            let receiver = NSTextView(frame: .zero)
            receiver.isRichText = false
            receiver.importsGraphics = false

            XCTAssertTrue(receiver.readSelection(from: clipboard))
            XCTAssertEqual(receiver.string, batch.contextText)
            XCTAssertTrue(receiver.string.contains(second.appName))
            XCTAssertFalse(receiver.string.contains("\u{FFFC}"))
        }
    }

    @MainActor
    func testHTMLContainsEveryOriginalImageInOrderAndEscapesCapturedMarkup() throws {
        let first = try makeCapture(name: "<script>First & \"one\"</script>", hue: 0.1)
        let second = try makeCapture(name: "Second", hue: 0.8)
        let batch = CaptureBatch(captures: [first, second], contextStyle: .full)
        let html = try XCTUnwrap(CaptureClipboardService.makeItem(for: batch).string(forType: .html))
        let expression = try NSRegularExpression(pattern: "data:image/png;base64,([A-Za-z0-9+/=]+)")
        let matches = expression.matches(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html))
        let images = try matches.map { match in
            let range = try XCTUnwrap(Range(match.range(at: 1), in: html))
            return try XCTUnwrap(Data(base64Encoded: String(html[range])))
        }
        XCTAssertEqual(images, batch.captures.compactMap(\.pngData))
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertTrue(html.contains("&lt;script&gt;First &amp; &quot;one&quot;&lt;/script&gt;"))
        XCTAssertTrue(html.contains("&#39;quoted&#39;"))
        let lastImage = try XCTUnwrap(html.range(of: "alt=\"NotchShot screenshot 2\""))
        let text = try XCTUnwrap(html.range(of: "<pre "))
        XCTAssertLessThan(lastImage.lowerBound, text.lowerBound)
    }

    @MainActor
    func testNoImagesOrCorruptPNGsKeepAllContextWithoutBrokenAttachments() throws {
        var missing = try makeCapture(name: "Missing")
        missing.pngData = nil
        var corrupt = try makeCapture(name: "Corrupt")
        corrupt.pngData = Data([137, 80, 78, 71, 13, 10, 26, 10] + Array("bad payload".utf8))
        var truncated = try makeCapture(name: "Truncated")
        truncated.pngData = truncated.pngData.map { Data($0.prefix(40)) }
        let batch = CaptureBatch(captures: [missing, corrupt, truncated], contextStyle: .full)
        let item = CaptureClipboardService.makeItem(for: batch)
        XCTAssertTrue(CaptureClipboardService.validImagePNGs(for: batch).isEmpty)
        XCTAssertNil(item.data(forType: .rtfd))
        XCTAssertNil(item.data(forType: .png))
        XCTAssertNil(item.data(forType: .tiff))
        XCTAssertFalse(try XCTUnwrap(item.string(forType: .html)).contains("data:image/"))
        XCTAssertEqual(item.string(forType: .string), batch.contextText)
    }

    @MainActor
    func testCorruptImageBetweenValidImagesDoesNotReorderOrLoseOthers() throws {
        let first = try makeCapture(name: "First", hue: 0.1)
        var corrupt = try makeCapture(name: "Corrupt")
        corrupt.pngData = Data("corrupt".utf8)
        let last = try makeCapture(name: "Last", hue: 0.9)
        let batch = CaptureBatch(captures: [first, corrupt, last], contextStyle: .full)
        let item = CaptureClipboardService.makeItem(for: batch)
        let expected = try [XCTUnwrap(first.pngData), XCTUnwrap(last.pngData)]
        XCTAssertEqual(CaptureClipboardService.validImagePNGs(for: batch), expected)
        XCTAssertEqual(attachments(in: try readDocument(item)).compactMap { $0.fileWrapper?.regularFileContents }, expected)
        XCTAssertNil(item.data(forType: .png))
        XCTAssertEqual(item.string(forType: .string), batch.contextText)
        XCTAssertTrue(try XCTUnwrap(item.string(forType: .html)).contains("screenshot 3"))
    }

    @MainActor
    func testDeclaredOversizedDimensionsAreRejectedBeforeDecoding() throws {
        var capture = try makeCapture(name: "Huge declaration")
        var png = try XCTUnwrap(capture.pngData)
        // Rewrite the PNG IHDR dimensions and CRC while retaining a tiny payload.
        // Metadata parsing succeeds, but the 400M-pixel declaration must fail the
        // pixel budget before the image decoder attempts to allocate its canvas.
        png.replaceSubrange(16..<24, with: [0, 0, 78, 32, 0, 0, 78, 32]) // 20,000 × 20,000
        let crc = crc32(Data(png[12..<29]))
        png.replaceSubrange(29..<33, with: [UInt8(crc >> 24), UInt8((crc >> 16) & 255),
                                         UInt8((crc >> 8) & 255), UInt8(crc & 255)])
        capture.pngData = png
        let batch = CaptureBatch(captures: [capture], contextStyle: .compact)
        XCTAssertTrue(CaptureClipboardService.validImagePNGs(for: batch).isEmpty)
        let item = CaptureClipboardService.makeItem(for: batch)
        XCTAssertNil(item.data(forType: .png))
        XCTAssertNil(item.data(forType: .rtfd))
        XCTAssertEqual(item.string(forType: .string), batch.contextText)
    }

    @MainActor
    func testLargeImageDisplayFitsPreviewButAttachmentRetainsOriginalPNG() throws {
        let capture = try makeCapture(name: "Large", width: 1_600, height: 1_200)
        let batch = CaptureBatch(captures: [capture], contextStyle: .compact)
        let item = CaptureClipboardService.makeItem(for: batch)
        let html = try XCTUnwrap(item.string(forType: .html))
        XCTAssertTrue(html.contains("width=\"640\" height=\"480\""))
        let attached = attachments(in: try readDocument(item))
        XCTAssertEqual(attached.first?.fileWrapper?.regularFileContents, capture.pngData)
        XCTAssertEqual(item.data(forType: .png), capture.pngData)
        XCTAssertNil(item.data(forType: .tiff), "Batch copy must not allocate an original-size TIFF just to offer a fallback.")
    }

    @MainActor
    func testBatchIdentityBindsOrderStyleExactTextAndImageBytes() throws {
        let first = try makeCapture(name: "First")
        var second = try makeCapture(name: "Second", hue: 0.8)
        let batch = CaptureBatch(captures: [first, second], contextStyle: .compact)
        let item = CaptureClipboardService.makeItem(for: batch)
        XCTAssertTrue(CaptureClipboardService.matchesBatchIdentity(item: item, batch: batch))
        XCTAssertEqual(item.string(forType: CaptureClipboardService.batchIdentifierType), batch.identity)
        XCTAssertFalse(CaptureClipboardService.matchesBatchIdentity(item: item, batch: CaptureBatch(captures: [second, first], contextStyle: .compact)))
        XCTAssertFalse(CaptureClipboardService.matchesBatchIdentity(item: item, batch: CaptureBatch(captures: [first, second], contextStyle: .full)))
        second.pngData = first.pngData
        XCTAssertFalse(CaptureClipboardService.matchesBatchIdentity(item: item, batch: CaptureBatch(captures: [first, second], contextStyle: .compact)))
        item.setString(batch.contextText + "changed", forType: .string)
        XCTAssertFalse(CaptureClipboardService.matchesBatchIdentity(item: item, batch: batch))
    }

    @MainActor
    func testPlainTextAndMissingIdentityCannotArmAsRichBatch() throws {
        let batch = CaptureBatch(captures: [try makeCapture(name: "First")], contextStyle: .compact)
        let item = NSPasteboardItem()
        item.setString(batch.contextText, forType: .string)
        XCTAssertFalse(CaptureClipboardService.matchesBatchIdentity(item: item, batch: batch))
    }

    @MainActor
    func testBackgroundValidationAndPreparedBatchPublishMatchingImageCounts() async throws {
        let first = try makeCapture(name: "First", hue: 0.1)
        var corrupt = try makeCapture(name: "Corrupt")
        corrupt.pngData = Data([137, 80, 78, 71, 13, 10, 26, 10] + Array("bad payload".utf8))
        var missing = try makeCapture(name: "Missing")
        missing.pngData = nil
        let last = try makeCapture(name: "Last", hue: 0.8)
        let captures = [first, corrupt, missing, last]
        let unavailable = await Task.detached {
            CaptureClipboardService.unavailableImageIDs(in: captures)
        }.value

        XCTAssertEqual(unavailable, [corrupt.id])
        let batch = CaptureBatch(captures: captures, contextStyle: .compact, unavailableImageIDs: unavailable)
        XCTAssertEqual(batch.omittedScreenshotNumbers, [2])
        XCTAssertEqual(batch.imagePNGs, [first, last].compactMap(\.pngData))
        XCTAssertEqual(CaptureClipboardService.validImagePNGs(for: batch), batch.imagePNGs)
        let item = CaptureClipboardService.makeItem(for: batch)
        XCTAssertEqual(attachments(in: try readDocument(item)).count, batch.imagePNGs.count)
        XCTAssertEqual(item.string(forType: .string), batch.contextText)
        XCTAssertTrue(CaptureClipboardService.matchesBatchIdentity(item: item, batch: batch))
    }

    @MainActor
    func testPreparedUnavailableIDsAreRespectedByEveryBatchImageRoute() throws {
        let first = try makeCapture(name: "First")
        let second = try makeCapture(name: "Second", hue: 0.8)
        // The immutable prepared batch is authoritative, even if its bytes could
        // now decode. Its UI, disclosure text, rich copy and staged paste must agree.
        let batch = CaptureBatch(captures: [first, second], contextStyle: .full, unavailableImageIDs: [second.id])
        let item = CaptureClipboardService.makeItem(for: batch)
        XCTAssertEqual(CaptureClipboardService.validImagePNGs(for: batch), batch.imagePNGs)
        XCTAssertEqual(item.data(forType: .png), first.pngData)
        XCTAssertEqual(attachments(in: try readDocument(item)).count, 1)
        XCTAssertEqual(item.string(forType: .string), batch.contextText)
        XCTAssertFalse(try XCTUnwrap(item.string(forType: .html)).contains("NotchShot screenshot 2"))
    }

    @MainActor
    private func readDocument(_ item: NSPasteboardItem) throws -> NSAttributedString {
        try NSAttributedString(data: XCTUnwrap(item.data(forType: .rtfd)),
                               options: [.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: nil)
    }

    private func attachments(in document: NSAttributedString) -> [NSTextAttachment] {
        var result: [NSTextAttachment] = []
        document.enumerateAttribute(.attachment, in: NSRange(location: 0, length: document.length)) { value, _, _ in
            if let attachment = value as? NSTextAttachment { result.append(attachment) }
        }
        return result
    }

    @MainActor
    private func makeClipboard() -> NSPasteboard {
        let clipboard = NSPasteboard(name: .init("NotchShotBatchClipboardTests-\(UUID())"))
        addTeardownBlock { clipboard.releaseGlobally() }
        return clipboard
    }

    @MainActor
    private func makeCapture(name: String, hue: CGFloat = 0.4, width: Int = 3, height: Int = 2) throws -> CaptureResult {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let graphics = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        NSColor(deviceHue: hue, saturation: 0.8, brightness: 0.9, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        return CaptureResult(date: Date(timeIntervalSince1970: 1_700_000_000), appName: name,
                             bundleIdentifier: "com.example.clipboard-batch", windowTitle: "Window \(name)",
                             pngData: try XCTUnwrap(bitmap.representation(using: .png, properties: [:])),
                             accessibilityText: "Text for \(name) with 'quoted' content & more — 你好 📷",
                             ocrText: "Separate OCR \(name)", warnings: ["Capture note \(name)"])
    }

    private func crc32(_ bytes: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xEDB8_8320 : 0) }
        }
        return crc ^ 0xFFFF_FFFF
    }
}
