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
}
