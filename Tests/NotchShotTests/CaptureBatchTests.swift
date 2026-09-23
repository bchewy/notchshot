// SPDX-License-Identifier: MIT
import XCTest
@testable import NotchShot

final class CaptureBatchTests: XCTestCase {
    func testCaptureTimeIncompleteNoticeSurvivesFullAndCompactCopyAndCounting() {
        var capture = fixture("Partial app", text: String(repeating: "retained tree ", count: 2_000))
        capture.accessibilityTreeIncomplete = true
        let full = CaptureBatch(captures: [capture], contextStyle: .full)
        let compact = CaptureBatch(captures: [capture], contextStyle: .compact)
        for batch in [full, compact] {
            XCTAssertTrue(batch.contextText.contains("[Accessibility tree is incomplete:"))
            XCTAssertTrue(batch.contextText.contains("retained tree"))
        }
        XCTAssertEqual(compact.originalCharacterCount, full.characterCount)
        XCTAssertLessThanOrEqual(shotSections(compact)[0].count, CaptureBatch.maximumCompactCharactersPerShot)
        XCTAssertTrue(compact.isShortened)
        XCTAssertTrue(compact.contextText.hasSuffix(treeTruncation + "\n\n" + CapturedContext.closing))
    }

    private let treeTruncation = "\n[Accessibility tree shortened to fit compact context; full tree retained in NotchShot.]"

    func testFullPreservesExactTreesAndStableShotBoundariesWithoutOtherSources() {
        var first = fixture("Editor", text: "  Exact first line\n\nSecond\tline  ")
        first.accessibilityText = "FLAT TEXT MUST NOT BE COPIED"
        first.ocrText = "OCR MUST NOT BE COPIED"
        first.importedText = "IMPORTED TEXT MUST NOT BE COPIED"
        first.warnings = ["CAPTURE NOTES MUST NOT BE COPIED"]
        let second = fixture("Browser", text: "Another tree")
        let batch = CaptureBatch(captures: [first, second], contextStyle: .full)

        XCTAssertEqual(batch.contextText,
                       "# NotchShot — 2 shots · Full context\n" + CapturedContext.opening + "\n\n"
                       + "--- Shot 1 of 2 ---\nScreenshot: none captured.\n\n" + first.clipboardBody
                       + "\n\n--- Shot 2 of 2 ---\nScreenshot: none captured.\n\n" + second.clipboardBody
                       + "\n\n" + CapturedContext.closing)
        for excluded in [first.accessibilityText, first.ocrText, first.importedText, first.warnings[0]] {
            XCTAssertFalse(batch.contextText.contains(excluded))
        }
        XCTAssertFalse(batch.isShortened)
        XCTAssertEqual(batch.removedDuplicateLines, 0)
        XCTAssertEqual(batch.characterCount, batch.originalCharacterCount)
        XCTAssertEqual(batch.contextText.count, batch.characterCount)
        XCTAssertTrue(first.contextText.contains(first.ocrText), "Detailed exports remain intact.")
    }

    func testCaptureIdentityDeduplicationPreservesFirstInstanceAndSuppliedOrder() {
        let first = fixture("First", text: "First original")
        let second = fixture("Second", text: "Second original")
        var duplicate = first
        duplicate.axTree[0].value = "A replacement must not displace the first instance."
        let batch = CaptureBatch(captures: [second, first, duplicate, second], contextStyle: .full)

        XCTAssertEqual(batch.captures.map(\.id), [second.id, first.id])
        XCTAssertTrue(batch.contextText.contains("First original"))
        XCTAssertFalse(batch.contextText.contains(duplicate.axTree[0].value))
    }

    func testEightLongShotsShareBudgetAndEachRetainsAnIdentifiableTreePrefix() {
        let captures = (1...8).map { fixture("App \($0)", text: "Unique beginning for shot \($0): " + String(repeating: "abcdefghij", count: 2_000)) }
        let batch = CaptureBatch(captures: captures, contextStyle: .compact)

        XCTAssertLessThanOrEqual(batch.characterCount, CaptureBatch.maximumCompactCharacters)
        XCTAssertTrue(batch.isShortened)
        for index in 1...8 {
            XCTAssertTrue(batch.contextText.contains("--- Shot \(index) of 8 ---"))
            XCTAssertTrue(batch.contextText.contains("Unique beginning for shot \(index):"))
        }
        let sections = shotSections(batch)
        XCTAssertEqual(sections.count, 8)
        for section in sections {
            XCTAssertGreaterThan(section.count, 3_000, "An early shot must not consume later shots’ allowance.")
            XCTAssertLessThanOrEqual(section.count, CaptureBatch.maximumCompactCharactersPerShot)
            XCTAssertTrue(section.hasSuffix(treeTruncation))
        }
        XCTAssertEqual(batch.characterCount, batch.contextText.count)
    }

    func testSingleLongAXValueIsBoundedAndDisclosedWithoutMutatingOriginal() {
        let capture = fixture("Editor", text: String(repeating: "x", count: 100_000))
        let batch = CaptureBatch(captures: [capture], contextStyle: .compact)
        let section = shotSections(batch)[0]

        XCTAssertLessThanOrEqual(section.count, CaptureBatch.maximumCompactCharactersPerShot)
        XCTAssertTrue(section.hasSuffix(treeTruncation))
        XCTAssertEqual(batch.captures[0].axTree[0].value, capture.axTree[0].value)
        XCTAssertGreaterThan(batch.originalCharacterCount, batch.characterCount)
        let clipboardPrefix = String(section.components(separatedBy: "\n\n")[1].dropLast(treeTruncation.count))
        XCTAssertTrue(capture.clipboardBody.hasPrefix(clipboardPrefix))
    }

    func testCompactPreservesRepeatedLinesAndNodesWithinAndAcrossShots() {
        let line = "  A meaningful repeated line about the same captured document.  "
        var first = fixture("First", text: line + "\n" + line + "\nSave\nSave\n123\n123")
        first.axTree += [AXNode(id: 2, role: "AXButton", roleDescription: "button", title: "Save"),
                         AXNode(id: 3, role: "AXButton", roleDescription: "button", title: "Save")]
        let second = fixture("Second", text: line)
        let batch = CaptureBatch(captures: [first, second], contextStyle: .compact)

        XCTAssertEqual(batch.removedDuplicateLines, 0)
        XCTAssertEqual(batch.contextText.components(separatedBy: line).count - 1, 3)
        XCTAssertTrue(batch.contextText.contains("button Save\nbutton Save"))
        XCTAssertTrue(batch.contextText.contains(first.clipboardBody))
        XCTAssertTrue(batch.contextText.contains(second.clipboardBody))
        XCTAssertFalse(batch.isShortened)
    }

    func testCompactUsesOnlyTreeEvenWhenOtherSourcesAndWarningsArePresent() {
        var capture = fixture("Browser", text: "TREE SOURCE")
        capture.accessibilityText = "FLAT SOURCE"
        capture.ocrText = "OCR SOURCE"
        capture.importedText = "IMPORTED SOURCE"
        capture.warnings = ["CAPTURE WARNING"]
        let batch = CaptureBatch(captures: [capture], contextStyle: .compact)

        XCTAssertTrue(batch.contextText.contains(capture.clipboardBody))
        for excluded in [capture.accessibilityText, capture.ocrText, capture.importedText, capture.warnings[0]] {
            XCTAssertFalse(batch.contextText.contains(excluded))
        }
        XCTAssertEqual(batch.removedDuplicateLines, 0)
        XCTAssertFalse(batch.isShortened, "Excluded non-tree sources are not part of the clipboard contract.")
        XCTAssertEqual(batch.captures[0].importedText, capture.importedText)
    }

    func testMissingTreeIsExplicitWithoutImportedOrOCRSubstitution() {
        var imported = fixture("Import", text: "")
        imported.importedText = "Imported text only"
        imported.ocrText = "Secondary OCR"
        var ocr = fixture("Image", text: "")
        ocr.ocrText = "OCR only"
        ocr.accessibilityText = "Flat source without a tree"
        for style in BatchContextStyle.allCases {
            let batch = CaptureBatch(captures: [imported, ocr], contextStyle: style)
            XCTAssertTrue(batch.contextText.contains(imported.clipboardBody))
            XCTAssertTrue(batch.contextText.contains(ocr.clipboardBody))
            XCTAssertEqual(batch.contextText.components(separatedBy: "No accessibility tree was available for this shot.").count - 1, 2)
            for excluded in [imported.importedText, imported.ocrText, ocr.ocrText, ocr.accessibilityText] {
                XCTAssertFalse(batch.contextText.contains(excluded))
            }
            XCTAssertFalse(batch.isShortened)
        }
    }

    func testUnicodeClippingRetainsCompleteGraphemeClusters() {
        let cluster = "👩🏽‍💻"
        let capture = fixture("日本語 📷", text: String(repeating: "写真" + cluster + "e\u{301}", count: 5_000))
        let batch = CaptureBatch(captures: [capture], contextStyle: .compact)
        let body = batch.contextText.components(separatedBy: "text area, Value: ")[1]
            .components(separatedBy: treeTruncation)[0]

        XCTAssertLessThanOrEqual(batch.characterCount, CaptureBatch.maximumCompactCharacters)
        XCTAssertTrue(batch.isShortened)
        XCTAssertTrue(body.contains(cluster))
        XCTAssertTrue(body.allSatisfy { Set("写真" + cluster + "e\u{301}").contains($0) })
        XCTAssertTrue(capture.axTree[0].value.hasPrefix(body))
        XCTAssertFalse(body.contains("�"))
    }

    func testPathologicalMetadataAndTreeStayBoundedWhileLaterShotNamesSurvive() {
        var capture = fixture(String(repeating: "Camera", count: 3_000), text: "")
        capture.windowTitle = String(repeating: "Very long window ", count: 3_000)
        capture.warnings = [String(repeating: "Warnings are excluded. ", count: 10_000)]
        capture.axTree = (1...200).map { AXNode(id: $0, role: "AXLink", roleDescription: "link", title: "Useful link \($0)", url: "https://example.invalid/" + String(repeating: "path", count: 200)) }
        let captures = (1...8).map { index in
            var copy = capture
            copy.id = UUID()
            copy.appName = "Unique shot \(index) " + copy.appName
            return copy
        }
        let batch = CaptureBatch(captures: captures, contextStyle: .compact)

        XCTAssertEqual(batch.captures.count, 8)
        XCTAssertLessThanOrEqual(batch.characterCount, CaptureBatch.maximumCompactCharacters)
        XCTAssertTrue(batch.contextText.contains("[App or window name shortened; full names retained in NotchShot.]"))
        XCTAssertTrue(batch.contextText.contains("Useful link 1"))
        XCTAssertTrue(batch.contextText.contains("Unique shot 8"))
        XCTAssertFalse(batch.contextText.contains("Warnings are excluded."))
        XCTAssertTrue(batch.isShortened)
        for section in shotSections(batch) {
            XCTAssertLessThanOrEqual(section.count, CaptureBatch.maximumCompactCharactersPerShot)
            XCTAssertTrue(section.hasSuffix(treeTruncation))
        }
    }

    func testShortCompactTreePreservesHierarchyAndProtectedFields() {
        var capture = fixture("Form", text: "Form content")
        capture.axTree = [AXNode(id: 1, role: "AXGroup", roleDescription: "group", title: "Account", children: [
            AXNode(id: 2, role: "AXButton", roleDescription: "button", title: "Save changes"),
            AXNode(id: 3, role: "AXGroup", roleDescription: "group", title: "Links", children: [
                AXNode(id: 4, role: "AXLink", roleDescription: "link", title: "Documentation", url: "https://example.invalid/docs"),
                AXNode(id: 5, role: "AXTextField", roleDescription: "text field", title: "secret title", value: "secret value", help: "secret help", url: "secret URL", placeholder: "secret placeholder", isSettable: true, isProtected: true)
            ]),
            AXNode(id: 6, role: "AXTextField", roleDescription: "text field", title: "Search", value: "Camera", isSettable: true)
        ])]
        for style in BatchContextStyle.allCases {
            let batch = CaptureBatch(captures: [capture], contextStyle: style)
            XCTAssertTrue(batch.contextText.contains(capture.clipboardBody))
            XCTAssertTrue(batch.contextText.contains("group Account\n\tbutton Save changes\n\tgroup Links\n\t\tlink Documentation"))
            XCTAssertTrue(batch.contextText.contains("\t\ttext field (settable) [protected]"))
            XCTAssertTrue(batch.contextText.contains("\n\ttext field (settable) Search, Value: Camera"))
            XCTAssertFalse(batch.contextText.contains("secret"))
            XCTAssertFalse(batch.isShortened)
        }
    }

    func testEmptyAndTreelessBatchesDoNotInventImagesOrTreeContent() {
        for style in BatchContextStyle.allCases {
            let empty = CaptureBatch(captures: [], contextStyle: style)
            XCTAssertTrue(empty.contextText.isEmpty)
            XCTAssertTrue(empty.imagePNGs.isEmpty)
            XCTAssertEqual(empty.characterCount, 0)
            XCTAssertEqual(empty.originalCharacterCount, 0)
            XCTAssertFalse(empty.isShortened)
            let capture = fixture("Empty window", text: "")
            let batch = CaptureBatch(captures: [capture], contextStyle: style)
            XCTAssertTrue(batch.imagePNGs.isEmpty)
            XCTAssertTrue(batch.contextText.contains(capture.clipboardBody))
            XCTAssertFalse(batch.isShortened)
        }
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
        var first = fixture("Invalid image", text: "Its tree must remain available")
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
            XCTAssertTrue(batch.contextText.contains(first.clipboardBody))
        }
    }

    func testStreamedFullCountAndUnshortenedPrefixMatchExactMultilineUnicodeTrees() {
        var capture = fixture("\u{301}Camera 📷", text: "Ignored flat text")
        capture.windowTitle = "\u{301}Window\r\nTitle"
        capture.importedText = "Imported e\u{301} and 👩🏽‍💻 text\r"
        capture.ocrText = "OCR source"
        capture.warnings = ["A warning\r", "\u{301}A second warning"]
        capture.axTree = [AXNode(id: 1, role: "AXGroup", roleDescription: "\u{301}group\nnext line", title: "Form", children: [
            AXNode(id: 2, role: "AXTextField", roleDescription: "field", title: "\u{301}Name\r\nsecond line", value: "value\nnext value", help: "Multiline\nhelp", url: "https://example.invalid", placeholder: "\u{301}placeholder", isSettable: true),
            AXNode(id: 3, role: "AXTextField", roleDescription: "protected field", title: "private", value: "private", isSettable: true, isProtected: true)
        ]), AXNode(id: 5, role: "AXGroup", roleDescription: "group", children: [
            AXNode(id: 4, role: "AXLink", roleDescription: "link", title: "Name", value: "https://example.invalid", help: "Name", url: "https://example.invalid")
        ])]
        var noTree = fixture("\u{301}Empty", text: "")
        noTree.windowTitle = "Empty\r\nwindow"
        let full = CaptureBatch(captures: [capture, noTree], contextStyle: .full)
        let compact = CaptureBatch(captures: [capture, noTree], contextStyle: .compact)
        XCTAssertEqual(compact.originalCharacterCount, full.contextText.count)
        XCTAssertTrue(compact.contextText.contains(capture.clipboardBody))
        XCTAssertTrue(compact.contextText.contains(noTree.clipboardBody))
        XCTAssertFalse(compact.isShortened)
    }

    func testCompactRetainsHierarchyPrefixAndMarksUnexaminedLaterNodes() {
        var capture = fixture("Hierarchy", text: "")
        capture.axTree = [AXNode(id: 1, role: "AXGroup", roleDescription: "group", title: "Toolbar", children: (1...2_000).map {
            AXNode(id: $0 + 1, role: "AXButton", roleDescription: "button", title: "Repeated useful label")
        })]
        capture.axTree.append(AXNode(id: 3_000, role: "AXButton", roleDescription: "button", title: "Unique final node"))
        let batch = CaptureBatch(captures: [capture], contextStyle: .compact)
        let section = shotSections(batch)[0]
        let content = section.components(separatedBy: "\n\n")[1]
        let prefix = String(content.dropLast(treeTruncation.count))

        XCTAssertTrue(capture.clipboardBody.hasPrefix(prefix))
        XCTAssertTrue(prefix.contains("group Toolbar\n\tbutton Repeated useful label\n\tbutton Repeated useful label"))
        XCTAssertTrue(section.hasSuffix(treeTruncation))
        XCTAssertFalse(section.contains("Unique final node"))
        XCTAssertEqual(batch.removedDuplicateLines, 0)
        XCTAssertTrue(batch.isShortened)
        XCTAssertEqual(batch.captures[0].elementCount, capture.elementCount)
    }

    func testExactlyFilledShotHasNoTruncationUntilAnotherNodeExists() {
        var capture = fixture("Boundary", text: "x")
        let first = CaptureBatch(captures: [capture], contextStyle: .compact)
        let additionalCharacters = CaptureBatch.maximumCompactCharactersPerShot - shotSections(first)[0].count
        capture.axTree[0].value += String(repeating: "x", count: additionalCharacters)
        let exact = CaptureBatch(captures: [capture], contextStyle: .compact)
        XCTAssertEqual(shotSections(exact)[0].count, CaptureBatch.maximumCompactCharactersPerShot)
        XCTAssertTrue(exact.contextText.contains(capture.clipboardBody))
        XCTAssertFalse(exact.isShortened)

        capture.axTree.append(AXNode(id: 2, role: "AXButton", roleDescription: "button", title: "One more node"))
        let overflow = CaptureBatch(captures: [capture], contextStyle: .compact)
        XCTAssertEqual(shotSections(overflow)[0].count, CaptureBatch.maximumCompactCharactersPerShot)
        XCTAssertTrue(shotSections(overflow)[0].hasSuffix(treeTruncation))
        XCTAssertTrue(overflow.isShortened)
        XCTAssertFalse(overflow.contextText.contains("One more node"))
    }

    func testLargeAXValuesKeepBoundedPreviewAndExactOriginalCount() {
        let largeText = String(repeating: "A long accessibility value. ", count: 346_000)
        var first = fixture("Large first tree", text: "x")
        var second = fixture("Large second tree", text: "x")
        let baseline = CaptureBatch(captures: [first, second], contextStyle: .full).characterCount
        first.axTree[0].value = largeText
        second.axTree[0].value = largeText
        let start = ContinuousClock.now
        let batch = CaptureBatch(captures: [first, second], contextStyle: .compact)
        let elapsed = ContinuousClock.now - start
        print("CaptureBatch Compact benchmark: 2 × \(largeText.utf8.count) bytes in \(elapsed)")

        XCTAssertEqual(batch.originalCharacterCount, baseline + 2 * (largeText.count - 1))
        XCTAssertLessThanOrEqual(batch.characterCount, CaptureBatch.maximumCompactCharacters)
        XCTAssertTrue(batch.contextText.contains("--- Shot 2 of 2 ---"))
        XCTAssertEqual(batch.contextText.components(separatedBy: treeTruncation).count - 1, 2)
        XCTAssertTrue(batch.isShortened)
    }

    func testLargeExcludedSourcesDoNotChangeClipboardPayloadOrIdentity() {
        var capture = fixture("Tree source", text: "Only this tree is copied")
        let baseline = CaptureBatch(captures: [capture], contextStyle: .compact)
        capture.accessibilityText = String(repeating: "Flat text ", count: 100_000)
        capture.importedText = String(repeating: "Imported text ", count: 100_000)
        capture.ocrText = String(repeating: "OCR text ", count: 100_000)
        capture.warnings = [String(repeating: "Warning ", count: 100_000)]
        let batch = CaptureBatch(captures: [capture], contextStyle: .compact)
        XCTAssertEqual(batch.contextText, baseline.contextText)
        XCTAssertEqual(batch.originalCharacterCount, baseline.originalCharacterCount)
        XCTAssertEqual(batch.identity, baseline.identity)
        XCTAssertFalse(batch.isShortened)
    }

    func testIdentityStillDependsOnStyleShotOrderAndImageBytes() {
        var first = fixture("First", text: "First tree")
        first.pngData = Data([1, 2, 3])
        let second = fixture("Second", text: "Second tree")
        let original = CaptureBatch(captures: [first, second], contextStyle: .compact)
        XCTAssertEqual(original.identity, CaptureBatch(captures: [first, second], contextStyle: .compact).identity)
        XCTAssertNotEqual(original.identity, CaptureBatch(captures: [second, first], contextStyle: .compact).identity)
        XCTAssertNotEqual(original.identity, CaptureBatch(captures: [first, second], contextStyle: .full).identity)
        first.pngData = Data([4, 5, 6])
        XCTAssertNotEqual(original.identity, CaptureBatch(captures: [first, second], contextStyle: .compact).identity)
    }

    private func shotSections(_ batch: CaptureBatch) -> [String] {
        let closing = "\n\n" + CapturedContext.closing
        let body = batch.contextText.hasSuffix(closing) ? String(batch.contextText.dropLast(closing.count)) : batch.contextText
        let sections = body.components(separatedBy: "--- Shot ").dropFirst()
        return sections.enumerated().map { index, value in
            "--- Shot " + (index == sections.count - 1 ? value : String(value.dropLast(2)))
        }
    }

    private func fixture(_ app: String, text: String) -> CaptureResult {
        CaptureResult(date: Date(timeIntervalSince1970: 1_800_000_000), appName: app,
                      bundleIdentifier: "test.capture-batch", windowTitle: "Window for " + app,
                      windowID: nil,
                      axTree: text.isEmpty ? [] : [AXNode(id: 1, role: "AXTextArea", roleDescription: "text area", value: text)],
                      accessibilityText: text)
    }
}
