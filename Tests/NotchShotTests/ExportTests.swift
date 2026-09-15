// SPDX-License-Identifier: MIT
import XCTest
@testable import NotchShot

final class ExportTests: XCTestCase {
    func testRepeatedExportPreservesEarlierFilesAndStructuredHierarchy() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let child = AXNode(id: 1, role: "AXTextField", roleDescription: "text field", value: "https://example.com", placeholder: "Search", isSettable: true)
        let root = AXNode(id: 0, role: "AXWindow", roleDescription: "standard window", title: "Example", children: [child])
        let capture = CaptureResult(appName: "Browser", bundleIdentifier: "com.example.browser", windowTitle: "Example", axTree: [root], accessibilityText: "Example page", ocrText: "Recognized pixels")
        let first = try ExportService.export(capture, to: parent)
        let marker = first.appendingPathComponent("context.md")
        try "Keep this earlier export".write(to: marker, atomically: true, encoding: .utf8)
        let second = try ExportService.export(capture, to: parent)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), "Keep this earlier export")
        let decoded = try JSONDecoder().decode([AXNode].self, from: Data(contentsOf: second.appendingPathComponent("accessibility-tree.json")))
        XCTAssertEqual(decoded.first?.children.first?.value, "https://example.com")
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.appendingPathComponent("screenshot.png").path))
        let context = try String(contentsOf: second.appendingPathComponent("context.md"), encoding: .utf8)
        XCTAssertTrue(context.contains("## Accessibility text"))
        XCTAssertTrue(context.contains("(OCR)"))
    }

    func testTreePreservesIndentationAndEditableMetadata() {
        let node = AXNode(id: 0, role: "AXWindow", roleDescription: "standard window", title: "Page", children: [AXNode(id: 1, role: "AXTextField", roleDescription: "text field", title: "Address", value: "https://example.com", isSettable: true)])
        XCTAssertEqual(node.formatted(), "standard window Page\n\ttext field (settable) Address, Value: https://example.com")
        XCTAssertEqual(node.descendantCount, 2)
    }

    func testProtectedFieldsNeverAppearInFormattedTree() {
        let node = AXNode(id: 0, role: "AXTextField", roleDescription: "secure text field", title: "hidden label", value: "do-not-emit", isProtected: true)
        XCTAssertEqual(node.formatted(), "secure text field [protected]")
    }
}
