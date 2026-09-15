// SPDX-License-Identifier: MIT
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import NotchShot

final class CaptureImportTests: XCTestCase {
    @MainActor
    func testDropSnapshotSurvivesPasteboardChangesAndPreservesTextProvenance() async throws {
        let pasteboard = NSPasteboard(name: .init("NotchShot.ImportTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.declareTypes([.png, .string], owner: nil)
        pasteboard.setData(try makePNG(), forType: .png)
        pasteboard.setString("Window: Example\n\tbutton Capture", forType: .string)
        let payload = try CaptureImportService.snapshot(from: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("unrelated later clipboard content", forType: .string)

        let result = try await CaptureImportService.importCapture(payload: payload)

        XCTAssertNotNil(result.pngData)
        XCTAssertEqual(result.importedText, "Window: Example\n\tbutton Capture")
        XCTAssertTrue(result.accessibilityText.isEmpty)
        XCTAssertTrue(result.axTree.isEmpty)
        XCTAssertTrue(result.ocrText.isEmpty, "Supplied context should not trigger OCR.")
        XCTAssertTrue(result.bundleIdentifier.isEmpty)
        XCTAssertTrue(result.warnings.contains(where: { $0.contains("no accessibility tree") }))
    }

    @MainActor
    func testPlainTextDoesNotInventScreenshotOrAccessibilityTree() async throws {
        let payload = CaptureImportPayload(imageData: nil,
                                           text: "An appshot's copied tree is supplied text.", name: "Imported Appshot")
        let result = try await CaptureImportService.importCapture(payload: payload)
        XCTAssertEqual(result.importedText, payload.text)
        XCTAssertNil(result.pngData)
        XCTAssertNil(result.windowID)
        XCTAssertTrue(result.axTree.isEmpty)
        XCTAssertTrue(result.accessibilityText.isEmpty)
        XCTAssertTrue(result.ocrText.isEmpty)
    }

    @MainActor
    func testCorruptImageReturnsActionableFailure() async {
        let payload = CaptureImportPayload(imageData: Data("not an image".utf8),
                                           text: "context", name: "Broken image")
        do {
            _ = try await CaptureImportService.importCapture(payload: payload)
            XCTFail("Corrupt bytes must not be accepted as a screenshot.")
        } catch CaptureImportError.invalidImage {
            // Expected: no empty or fabricated screenshot is returned.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    func testCombinedImageAndContextSizeIsBoundedBeforeDecode() async {
        let payload = CaptureImportPayload(imageData: Data(repeating: 0, count: CaptureImportService.maximumInputBytes),
                                           text: "one extra byte", name: "Large image")
        do {
            _ = try await CaptureImportService.importCapture(payload: payload)
            XCTFail("The combined image and text input must fit the size limit.")
        } catch CaptureImportError.inputTooLarge {
            // Expected before image parsing.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPixelLimitRejectsOverflowSizedHeaders() throws {
        XCTAssertNoThrow(try CaptureImportService.validatePixelDimensions(width: 8_000, height: 5_000))
        XCTAssertThrowsError(try CaptureImportService.validatePixelDimensions(width: 8_001, height: 5_000)) {
            guard case CaptureImportError.imageTooLarge = $0 else { return XCTFail("Unexpected error: \($0)") }
        }
        XCTAssertThrowsError(try CaptureImportService.validatePixelDimensions(width: Int.max, height: Int.max)) {
            guard case CaptureImportError.imageTooLarge = $0 else { return XCTFail("Unexpected error: \($0)") }
        }
    }

    @MainActor
    func testRemoteImageURLIsNeverFetched() {
        let pasteboard = NSPasteboard(name: .init("NotchShot.ImportRemoteTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.declareTypes([.fileURL], owner: nil)
        pasteboard.setString("https://example.invalid/image.png", forType: .fileURL)
        XCTAssertFalse(CaptureImportService.canImport(pasteboard))
        XCTAssertThrowsError(try CaptureImportService.snapshot(from: pasteboard)) {
            guard case CaptureImportError.unsupportedDrop = $0 else { return XCTFail("Unexpected error: \($0)") }
        }
    }

    @MainActor
    func testMultiplePNGAndTIFFItemsKeepImageTextAndFilenameTogether() async throws {
        let pasteboard = NSPasteboard(name: .init("NotchShot.ImportPairingTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let first = NSPasteboardItem()
        first.setData(try makeImageData(type: .tiff, width: 4, height: 3), forType: .tiff)
        first.setString("Context from first TIFF card", forType: .string)
        first.setString("file:///tmp/first-card.tiff", forType: .fileURL)
        let second = NSPasteboardItem()
        second.setData(try makeImageData(type: .png, width: 7, height: 2), forType: .png)
        second.setString("Context from second PNG card", forType: .string)
        second.setString("file:///tmp/second-card.png", forType: .fileURL)
        XCTAssertTrue(pasteboard.writeObjects([first, second]))

        let payload = try CaptureImportService.snapshot(from: pasteboard)
        let result = try await CaptureImportService.importCapture(payload: payload)

        XCTAssertEqual(result.importedText, "Context from first TIFF card")
        XCTAssertEqual(result.windowTitle, "first-card.tiff")
        let dimensions = try imageDimensions(XCTUnwrap(result.pngData))
        XCTAssertEqual(dimensions.width, 4)
        XCTAssertEqual(dimensions.height, 3)
        XCTAssertTrue(result.warnings.contains(where: { $0.contains("only the first supported image") }))
    }

    @MainActor
    func testLocalFileBytesSurviveReplacementAndRemovalAfterDropSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("original-appshot.png")
        let original = try makePNG()
        try original.write(to: fileURL)
        let pasteboard = NSPasteboard(name: .init("NotchShot.ImportFileTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let item = NSPasteboardItem()
        item.setString(fileURL.absoluteString, forType: .fileURL)
        item.setString("Original image context", forType: .string)
        XCTAssertTrue(pasteboard.writeObjects([item]))
        let beforeReplacement = try CaptureImportService.snapshot(from: pasteboard)
        let beforeRemoval = try CaptureImportService.snapshot(from: pasteboard)
        XCTAssertEqual(beforeReplacement.imageData, original)
        XCTAssertEqual(beforeRemoval.imageData, original)

        try makeImageData(type: .png, width: 11, height: 13).write(to: fileURL, options: .atomic)
        let replacedResult = try await CaptureImportService.importCapture(payload: beforeReplacement)
        try FileManager.default.removeItem(at: fileURL)
        let removedResult = try await CaptureImportService.importCapture(payload: beforeRemoval)

        for result in [replacedResult, removedResult] {
            XCTAssertEqual(result.windowTitle, "original-appshot.png")
            XCTAssertEqual(result.importedText, "Original image context")
            let dimensions = try imageDimensions(XCTUnwrap(result.pngData))
            XCTAssertEqual(dimensions.width, 4)
            XCTAssertEqual(dimensions.height, 3)
        }
    }

    @MainActor
    func testHoverRejectsUnsupportedFileAndAcceptsRasterTypeWithoutImageData() {
        let pasteboard = NSPasteboard(name: .init("NotchShot.ImportHoverTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.declareTypes([.fileURL, .string], owner: nil)
        pasteboard.setString("file:///tmp/document.pdf", forType: .fileURL)
        pasteboard.setString("/tmp/document.pdf", forType: .string)
        XCTAssertFalse(CaptureImportService.canImport(pasteboard))
        pasteboard.declareTypes([.png], owner: nil)
        XCTAssertTrue(CaptureImportService.canImport(pasteboard), "Hover should inspect types without requesting or decoding image bytes.")
    }

    private func makePNG() throws -> Data {
        try makeImageData(type: .png, width: 4, height: 3)
    }

    private func makeImageData(type: UTType, width: Int, height: Int) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                            bytesPerRow: 0, space: colorSpace,
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.7, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func imageDimensions(_ data: Data) throws -> (width: Int, height: Int) {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return (image.width, image.height)
    }
}
