// SPDX-License-Identifier: MIT
import CoreGraphics
import XCTest
@testable import NotchShot

final class CaptureEngineTests: XCTestCase {
    private let firstBounds = CGRect(x: 20, y: 40, width: 800, height: 600)
    private let secondBounds = CGRect(x: 200, y: 100, width: 900, height: 700)

    func testFocusedGeometryWinsOverShareableListOrderingAndDuplicateTitles() {
        let candidates = [
            CaptureWindowCandidate(id: 1, title: "Document", bounds: firstBounds, layer: 0),
            CaptureWindowCandidate(id: 2, title: "Document", bounds: secondBounds, layer: 0)
        ]
        XCTAssertEqual(CaptureService.selectWindow(candidates, focusedTitle: "Document", focusedBounds: secondBounds, hasFocusedWindow: true)?.id, 2)
    }

    func testUnknownFocusedWindowDoesNotCaptureAnUnrelatedWindow() {
        let candidate = CaptureWindowCandidate(id: 1, title: "Other document", bounds: firstBounds, layer: 0)
        XCTAssertNil(CaptureService.selectWindow([candidate], focusedTitle: "Private document", focusedBounds: secondBounds, hasFocusedWindow: true))
    }

    func testMissingAXUsesFrontmostStandardWindowRatherThanFloatingPanel() {
        let candidates = [
            CaptureWindowCandidate(id: 1, title: "Tools", bounds: firstBounds, layer: 3),
            CaptureWindowCandidate(id: 2, title: "Document", bounds: secondBounds, layer: 0)
        ]
        XCTAssertEqual(CaptureService.selectWindow(candidates, focusedTitle: nil, focusedBounds: nil, hasFocusedWindow: false)?.id, 2)
    }

    func testAXReadableTextExcludesProtectedSubtree() {
        let nodes = [AXNode(id: 1, role: "AXWindow", roleDescription: "window", title: "Example", children: [
            AXNode(id: 2, role: "AXTextField", roleDescription: "protected field", value: "never export", isProtected: true,
                   children: [AXNode(id: 3, role: "AXStaticText", roleDescription: "text", value: "also protected")]),
            AXNode(id: 4, role: "AXStaticText", roleDescription: "text", value: "Visible content")
        ])]
        XCTAssertEqual(AccessibilityReader.readableText(nodes), "Example\nVisible content")
    }

    func testReaderWarningsMarkCopiedTreeIncompleteWithoutSubstitutingOtherText() {
        let warning = "Some accessibility child lists could not be read; the tree is partial."
        let readerResult = AccessibilityReadResult(
            tree: [AXNode(id: 1, role: "AXWindow", roleDescription: "window", title: "Fixture", children: [
                AXNode(id: 2, role: "AXButton", roleDescription: "button", title: "Submit")
            ])],
            text: "Flat accessibility source",
            warnings: [warning]
        )
        var capture = CaptureResult(appName: "Fixture App", bundleIdentifier: "com.example.fixture",
                                    windowTitle: "Fixture", ocrText: "OCR fallback source")

        CaptureService.applyAccessibility(readerResult, to: &capture)

        XCTAssertTrue(capture.accessibilityTreeIncomplete)
        XCTAssertTrue(capture.warnings.contains(warning))
        XCTAssertTrue(capture.clipboardText.contains("[Accessibility tree is incomplete:"))
        XCTAssertTrue(capture.clipboardText.contains("window Fixture\n\tbutton Submit"))
        XCTAssertFalse(capture.clipboardText.contains("Flat accessibility source"))
        XCTAssertFalse(capture.clipboardText.contains("OCR fallback source"))
        XCTAssertEqual(capture.accessibilityText, "Flat accessibility source")
        XCTAssertEqual(capture.ocrText, "OCR fallback source")
    }

    func testUnrelatedCaptureNotesDoNotMarkReadableTreeIncomplete() {
        let readerResult = AccessibilityReadResult(tree: [
            AXNode(id: 1, role: "AXButton", roleDescription: "button", title: "Submit")
        ])
        var capture = CaptureResult(appName: "Fixture App", bundleIdentifier: "com.example.fixture",
                                    windowTitle: "Fixture", warnings: ["The screenshot could not be encoded as PNG."])

        CaptureService.applyAccessibility(readerResult, to: &capture)

        XCTAssertFalse(capture.accessibilityTreeIncomplete)
        XCTAssertEqual(capture.clipboardText, capture.treeText)
        XCTAssertEqual(capture.warnings.count, 2, "The informational AX visibility note is also not an incompleteness signal.")
    }

    func testBrowserControlsWithoutDocumentMarkCopiedTreeIncomplete() {
        let toolbar = AXNode(id: 1, role: "AXToolbar", roleDescription: "toolbar", children: [
            AXNode(id: 2, role: "AXButton", roleDescription: "button", title: "Back")
        ])
        var capture = CaptureResult(appName: "Brave Browser", bundleIdentifier: "com.brave.Browser",
                                    windowTitle: "Fixture page")

        let needsBrowserFallback = CaptureService.applyAccessibility(
            AccessibilityReadResult(tree: [toolbar]), to: &capture
        )

        XCTAssertTrue(needsBrowserFallback)
        XCTAssertTrue(capture.accessibilityTreeIncomplete)
        XCTAssertTrue(capture.clipboardText.contains("[Accessibility tree is incomplete:"))
        XCTAssertTrue(capture.warnings.contains { $0.contains("controls but no web document tree") })
    }

    func testBrowserDocumentDoesNotReceiveMissingDocumentWarning() {
        let window = AXNode(id: 1, role: "AXWindow", roleDescription: "window", children: [
            AXNode(id: 2, role: "AXWebArea", roleDescription: "web area", title: "Fixture page")
        ])
        var capture = CaptureResult(appName: "Brave Browser", bundleIdentifier: "com.brave.Browser",
                                    windowTitle: "Fixture page")

        let needsBrowserFallback = CaptureService.applyAccessibility(
            AccessibilityReadResult(tree: [window]), to: &capture
        )

        XCTAssertFalse(needsBrowserFallback)
        XCTAssertFalse(capture.accessibilityTreeIncomplete)
        XCTAssertEqual(capture.clipboardText, capture.treeText)
        XCTAssertFalse(capture.warnings.contains { $0.contains("controls but no web document tree") })
    }
}
