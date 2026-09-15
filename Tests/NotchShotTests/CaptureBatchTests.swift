// SPDX-License-Identifier: MIT
import XCTest
@testable import NotchShot

final class CaptureBatchTests: XCTestCase {
    func testFullPreservesEveryOriginalSourceAndStableShotBoundaries() throws {
        var first = fixture("Editor", text: "  Exact first line\n\nSecond\tline  ")
        first.ocrText = "OCR and AX may overlap; this stays verbatim."
        first.importedText = "Imported <markup> & text\n"
        first.axTree = [AXNode(id: 1, role: "AXButton", roleDescription: "button", title: "Save")]
        first.warnings = ["A capture limitation.\nWith another line."]
        let second = fixture("Browser", text: "Another source")
        let batch = CaptureBatch(captures: [first, second], contextStyle: .full)

        XCTAssertTrue(batch.contextText.contains("--- Shot 1 of 2 ---\nScreenshot: none captured.\n\n" + first.contextText))
        XCTAssertTrue(batch.contextText.hasSuffix("--- Shot 2 of 2 ---\nScreenshot: none captured.\n\n" + second.contextText))
        XCTAssertFalse(batch.isShortened)
        XCTAssertEqual(batch.removedDuplicateLines, 0)
        XCTAssertEqual(batch.characterCount, batch.originalCharacterCount)
        XCTAssertEqual(batch.contextText.count, batch.characterCount)
    }

    func testCaptureIdentityDeduplicationPreservesFirstInstanceAndSuppliedOrder() {
        let first = fixture("First", text: "First original")
        let second = fixture("Second", text: "Second original")
        var duplicate = first
        duplicate.accessibilityText = "A replacement must not displace the first instance."
        let batch = CaptureBatch(captures: [second, first, duplicate, second], contextStyle: .full)

        XCTAssertEqual(batch.captures.map(\.id), [second.id, first.id])
        XCTAssertTrue(batch.contextText.contains("First original"))
        XCTAssertFalse(batch.contextText.contains(duplicate.accessibilityText))
    }

    func testEightLongShotsShareBudgetAndEachRetainsAnIdentifiableExcerpt() {
        let captures = (1...8).map { fixture("App \($0)", text: "Unique beginning for shot \($0): " + String(repeating: "abcdefghij", count: 2_000)) }
        let batch = CaptureBatch(captures: captures, contextStyle: .compact)

        XCTAssertLessThanOrEqual(batch.characterCount, 32_000)
        XCTAssertTrue(batch.isShortened)
        for index in 1...8 {
            XCTAssertTrue(batch.contextText.contains("--- Shot \(index) of 8 ---"))
            XCTAssertTrue(batch.contextText.contains("Unique beginning for shot \(index):"))
        }
        let sections = batch.contextText.components(separatedBy: "--- Shot ").dropFirst()
        XCTAssertEqual(sections.count, 8)
        for section in sections {
            XCTAssertGreaterThan(section.count, 3_000, "A long early shot must not consume later shots’ allowance.")
            XCTAssertLessThanOrEqual(section.count, 6_000)
            XCTAssertTrue(section.contains("Text shortened to fit compact context"))
        }
    }

    func testSingleLongLineIsBoundedAndDisclosedWithoutMutatingOriginal() {
        let capture = fixture("Editor", text: String(repeating: "x", count: 100_000))
        let batch = CaptureBatch(captures: [capture], contextStyle: .compact)

        let excerpt = batch.contextText.components(separatedBy: "--- Shot ").last ?? ""
        XCTAssertLessThanOrEqual(excerpt.count, 6_000)
        XCTAssertTrue(batch.contextText.contains("[Text shortened to fit compact context; full text retained in NotchShot.]"))
        XCTAssertEqual(batch.captures[0].accessibilityText, capture.accessibilityText)
        XCTAssertGreaterThan(batch.originalCharacterCount, batch.characterCount)
    }

    func testDuplicateLineRemovalStaysWithinShotAndKeepsFirstLineFormatting() {
        let line = "  A meaningful repeated line about the same captured document.  "
        let first = fixture("First", text: line + "\nA\tmeaningful repeated line about the same captured document.\nSave\nSave\n123\n123")
        let second = fixture("Second", text: line)
        let batch = CaptureBatch(captures: [first, second], contextStyle: .compact)

        XCTAssertEqual(batch.removedDuplicateLines, 1)
        XCTAssertEqual(batch.contextText.components(separatedBy: line).count - 1, 2,
                       "Shared text across shots must retain its separate provenance.")
        XCTAssertTrue(batch.contextText.contains("Save\nSave\n123\n123"))
        XCTAssertTrue(batch.contextText.contains("[Removed 1 repeated line within this source.]"))
        XCTAssertTrue(batch.isShortened)
    }

    func testSourcePriorityAndOtherSourceOmissionsAreExplicitNotCrossSourceDeduplicated() {
        var capture = fixture("Browser", text: "The accessibility source supplies the main readable context.")
        capture.ocrText = capture.accessibilityText
        capture.importedText = "An imported source must not silently blend into accessibility text."
        let batch = CaptureBatch(captures: [capture], contextStyle: .compact)

        XCTAssertTrue(batch.contextText.contains("Accessibility text:\n" + capture.accessibilityText))
        XCTAssertTrue(batch.contextText.contains("Additional sources omitted in compact context: Imported text, Text recognized from screenshot (OCR)"))
        XCTAssertEqual(batch.removedDuplicateLines, 0)
        XCTAssertFalse(batch.contextText.contains(capture.importedText))
        XCTAssertTrue(batch.isShortened)
        XCTAssertEqual(batch.captures[0].importedText, capture.importedText)
    }

    func testImportedAndOCRReadabilityFallbacksRetainSourceLabels() {
        var imported = fixture("Import", text: "")
        imported.importedText = "Imported text only"
        imported.ocrText = "Secondary OCR"
        var ocr = fixture("Image", text: "")
        ocr.ocrText = "OCR only"
        let batch = CaptureBatch(captures: [imported, ocr], contextStyle: .compact)

        XCTAssertTrue(batch.contextText.contains("Imported text:\nImported text only"))
        XCTAssertTrue(batch.contextText.contains("Text recognized from screenshot (OCR):\nOCR only"))
        XCTAssertTrue(batch.contextText.contains("Additional sources omitted in compact context: Text recognized from screenshot (OCR)"))
    }

    func testUnicodeClippingRetainsCompleteGraphemeClusters() {
        let cluster = "👩🏽‍💻"
        let capture = fixture("日本語 📷", text: String(repeating: "写真" + cluster + "e\u{301}", count: 5_000))
        let batch = CaptureBatch(captures: [capture], contextStyle: .compact)
        let body = batch.contextText.components(separatedBy: "Accessibility text:\n")[1]
            .components(separatedBy: "\n[Text shortened")[0]

        XCTAssertLessThanOrEqual(batch.characterCount, 32_000)
        XCTAssertTrue(batch.isShortened)
        XCTAssertTrue(body.contains(cluster))
        XCTAssertTrue(body.allSatisfy { Set("写真" + cluster + "e\u{301}").contains($0) })
        XCTAssertFalse(body.contains("�"))
    }

    func testPathologicalMetadataWarningsAndTreeRemainBoundedAndMarked() {
        var capture = fixture(String(repeating: "Camera", count: 3_000), text: String(repeating: "Document content ", count: 2_000))
        capture.windowTitle = String(repeating: "Very long window ", count: 3_000)
        capture.warnings = (1...50).map { "Capture note \($0): " + String(repeating: "detail ", count: 1_000) }
        capture.axTree = (1...200).map { AXNode(id: $0, role: "AXLink", roleDescription: "link", title: "Useful link \($0)", url: "https://example.invalid/" + String(repeating: "path", count: 200)) }
        let batch = CaptureBatch(captures: Array(repeating: capture, count: 8).enumerated().map { index, value in
            var copy = value
            copy.id = UUID()
            copy.accessibilityText = "Unique shot \(index) " + copy.accessibilityText
            return copy
        }, contextStyle: .compact)

        XCTAssertEqual(batch.captures.count, 8)
        XCTAssertLessThanOrEqual(batch.characterCount, 32_000)
        XCTAssertTrue(batch.contextText.contains("…"))
        XCTAssertTrue(batch.contextText.contains("Capture notes shortened"))
        XCTAssertTrue(batch.contextText.contains("Accessibility controls and links (partial; full tree retained)"))
        XCTAssertTrue(batch.contextText.contains("Useful link 1"))
        XCTAssertTrue(batch.contextText.contains("Unique shot 7"))
        XCTAssertTrue(batch.isShortened)
    }

    func testControlSummaryPreservesUsefulControlsAndDoesNotExposeProtectedFields() {
        var capture = fixture("Form", text: "Form content")
        capture.axTree = [AXNode(id: 1, role: "AXGroup", roleDescription: "group", children: [
            AXNode(id: 2, role: "AXButton", roleDescription: "button", title: "Save changes"),
            AXNode(id: 3, role: "AXLink", roleDescription: "link", title: "Documentation", url: "https://example.invalid/docs"),
            AXNode(id: 4, role: "AXTextField", roleDescription: "text field", title: "secret title", value: "secret value", isProtected: true),
            AXNode(id: 5, role: "AXTextField", roleDescription: "text field", title: "Search", value: "Camera", isSettable: true)
        ])]
        let batch = CaptureBatch(captures: [capture], contextStyle: .compact)

        XCTAssertTrue(batch.contextText.contains("button: Save changes"))
        XCTAssertTrue(batch.contextText.contains("Documentation — https://example.invalid/docs"))
        XCTAssertTrue(batch.contextText.contains("text field [protected]"))
        XCTAssertTrue(batch.contextText.contains("text field (settable): Search, Value: Camera"))
        XCTAssertFalse(batch.contextText.contains("secret"))
        XCTAssertTrue(batch.contextText.contains("partial; full tree retained"))
    }

    func testEmptyAndTextOnlyBatchesDoNotInventImagesOrContent() {
        for style in BatchContextStyle.allCases {
            let empty = CaptureBatch(captures: [], contextStyle: style)
            XCTAssertTrue(empty.contextText.isEmpty)
            XCTAssertTrue(empty.imagePNGs.isEmpty)
            XCTAssertEqual(empty.characterCount, 0)
            XCTAssertFalse(empty.isShortened)
        }
        let capture = fixture("Plain app", text: "A short complete readable excerpt.")
        let batch = CaptureBatch(captures: [capture], contextStyle: .compact)
        XCTAssertTrue(batch.imagePNGs.isEmpty)
        XCTAssertTrue(batch.contextText.contains(capture.accessibilityText))
        XCTAssertFalse(batch.isShortened)
        let metadataOnly = CaptureBatch(captures: [fixture("Empty window", text: "")], contextStyle: .compact)
        XCTAssertTrue(metadataOnly.contextText.contains("No readable text was captured."))
    }

    func testImageBytesAndOrderRemainUnmodifiedForClipboardValidation() {
        var first = fixture("First", text: "First source")
        first.pngData = Data([1, 2, 3])
        let noImage = fixture("No image", text: "Text only")
        var last = fixture("Last", text: "Last source")
        last.pngData = Data([4, 5, 6])
        let batch = CaptureBatch(captures: [last, noImage, first], contextStyle: .compact)

        XCTAssertEqual(batch.imagePNGs, [last.pngData!, first.pngData!])
        XCTAssertEqual(batch.captures.map(\.id), [last.id, noImage.id, first.id])
    }

    func testMixedImageAndTextOnlyShotsKeepImageAssociationWithOriginalShotNumber() {
        var first = fixture("First", text: "First context")
        first.pngData = Data([1, 2, 3])
        let textOnly = fixture("Text only", text: "No screenshot here")
        var third = fixture("Third", text: "Third context")
        third.pngData = Data([4, 5, 6])
        for style in BatchContextStyle.allCases {
            let batch = CaptureBatch(captures: [first, textOnly, third], contextStyle: style)
            XCTAssertTrue(batch.contextText.contains("--- Shot 1 of 3 ---\nScreenshot source: Shot 1."))
            XCTAssertTrue(batch.contextText.contains("--- Shot 2 of 3 ---\nScreenshot: none captured."))
            XCTAssertTrue(batch.contextText.contains("--- Shot 3 of 3 ---\nScreenshot source: Shot 3."))
            XCTAssertEqual(batch.imagePNGs, [first.pngData!, third.pngData!])
        }
    }

    func testUnavailableImagesAreDisclosedWithoutChangingOriginalCaptureOrRenumberingOthers() {
        var first = fixture("Invalid image", text: "Its text must remain available")
        first.pngData = Data([1, 2, 3])
        let textOnly = fixture("Text only", text: "No image was captured")
        var third = fixture("Valid image", text: "Third context")
        third.pngData = Data([4, 5, 6])
        for style in BatchContextStyle.allCases {
            let batch = CaptureBatch(captures: [first, textOnly, third], contextStyle: style,
                                     unavailableImageIDs: [first.id, textOnly.id, UUID()])
            XCTAssertEqual(batch.unavailableImageIDs, [first.id])
            XCTAssertEqual(batch.omittedScreenshotNumbers, [1])
            XCTAssertEqual(batch.imagePNGs, [third.pngData!])
            XCTAssertEqual(batch.captures[0].pngData, first.pngData)
            XCTAssertTrue(batch.contextText.contains("--- Shot 1 of 3 ---\nScreenshot: unavailable; text retained."))
            XCTAssertTrue(batch.contextText.contains("--- Shot 2 of 3 ---\nScreenshot: none captured."))
            XCTAssertTrue(batch.contextText.contains("--- Shot 3 of 3 ---\nScreenshot source: Shot 3."))
            XCTAssertTrue(batch.contextText.contains(first.accessibilityText))
            if style == .full { XCTAssertTrue(batch.contextText.contains(first.contextText)) }
        }
    }

    func testStreamedFullCountMatchesExactContextWithEverySourceAndMultilineTree() {
        var capture = fixture("\u{301}Camera 📷", text: "Source ends with a carriage return\r")
        capture.windowTitle = "\u{301}Window\r\nTitle"
        capture.importedText = "Imported e\u{301} and 👩🏽‍💻 text\r"
        capture.ocrText = "OCR source"
        capture.warnings = ["A warning\r", "\u{301}A second warning"]
        capture.axTree = [AXNode(id: 1, role: "AXGroup", roleDescription: "\u{301}group\nnext line", children: [
            AXNode(id: 2, role: "AXTextField", roleDescription: "field", title: "\u{301}Name\r\nsecond line", value: "value\nnext value", help: "Multiline\nhelp", url: "https://example.invalid", placeholder: "\u{301}placeholder", isSettable: true),
            AXNode(id: 3, role: "AXTextField", roleDescription: "protected field", title: "private", value: "private", isSettable: true, isProtected: true)
        ]), AXNode(id: 4, role: "AXLink", roleDescription: "link", title: "Name", value: "https://example.invalid", help: "Name", url: "https://example.invalid")]
        let full = CaptureBatch(captures: [capture], contextStyle: .full)
        let compact = CaptureBatch(captures: [capture], contextStyle: .compact)
        XCTAssertEqual(compact.originalCharacterCount, full.contextText.count)
    }

    func testCompactStopsExaminingRepeatedInputAndClearlyDisclosesUnexaminedRemainder() {
        let line = "This substantial line is deliberately repeated in a very long source.\n"
        var capture = fixture("Imported source", text: "")
        capture.importedText = String(repeating: line, count: 4_000) + "A final unique line beyond the examined prefix."
        let batch = CaptureBatch(captures: [capture], contextStyle: .compact)

        XCTAssertTrue(batch.contextText.contains("Remaining source not examined in compact context"))
        XCTAssertFalse(batch.contextText.contains("A final unique line"))
        XCTAssertLessThan(batch.removedDuplicateLines, 4_000,
                          "The duplicate count must describe examined lines, not imply the whole source was inspected.")
        XCTAssertGreaterThan(batch.removedDuplicateLines, 0)
        XCTAssertLessThanOrEqual(batch.characterCount, 32_000)
        XCTAssertEqual(batch.captures[0].importedText, capture.importedText)
        XCTAssertTrue(batch.isShortened)
    }

    func testLargeImportedSourcesKeepBoundedPreviewAndExactOriginalCount() {
        let largeText = String(repeating: "A long imported source line. ", count: 346_000)
        var first = fixture("Large first import", text: "")
        var second = fixture("Large second import", text: "")
        let baseline = CaptureBatch(captures: [first, second], contextStyle: .full).characterCount
        first.importedText = largeText
        second.importedText = largeText
        let start = ContinuousClock.now
        let batch = CaptureBatch(captures: [first, second], contextStyle: .compact)
        let elapsed = ContinuousClock.now - start
        print("CaptureBatch Compact benchmark: 2 × \(largeText.utf8.count) bytes in \(elapsed)")

        XCTAssertEqual(batch.originalCharacterCount,
                       baseline + 2 * ("\n\n## Imported text\n".count + largeText.count))
        XCTAssertLessThanOrEqual(batch.characterCount, 32_000)
        XCTAssertTrue(batch.contextText.contains("--- Shot 2 of 2 ---"))
        XCTAssertTrue(batch.contextText.contains("Remaining source not examined in compact context"))
    }

    private func fixture(_ app: String, text: String) -> CaptureResult {
        CaptureResult(date: Date(timeIntervalSince1970: 1_800_000_000), appName: app,
                      bundleIdentifier: "test.capture-batch", windowTitle: "Window for " + app,
                      windowID: nil, accessibilityText: text)
    }
}
