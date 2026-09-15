// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI
import XCTest
@testable import NotchShot

final class CaptureTreeViewportTests: XCTestCase {
    @MainActor
    func testLargeTreeKeepsCompleteScrollableContentInsideBoundedHost() throws {
        _ = NSApplication.shared
        // The compact notch leaves roughly 110 points for the tree below search.
        let viewport = NSSize(width: 412, height: 110)
        let dataURL = "data:image/png;base64," + String(repeating: "A0B1C2D3", count: 16_384)
        let elements = (0..<750).map { "  button Item \($0), Value: Full accessibility content for element \($0)" }
        let tree = (["Window: \"Large tree regression\", App: Test.", "  image, URL: \(dataURL)"] + elements + ["AX_TREE_END"]).joined(separator: "\n")

        // Attach the real representable to a hidden native window so SwiftUI
        // creates and lays out its AppKit viewport without touching the live app.
        let host = NSHostingView(rootView: ReadOnlyCaptureTextView(text: tree).frame(width: viewport.width, height: viewport.height))
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: viewport), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: viewport)
        host.layoutSubtreeIfNeeded()

        let scrollView = try XCTUnwrap(firstDescendant(of: NSScrollView.self, in: host))
        scrollView.layoutSubtreeIfNeeded()
        let textView = try XCTUnwrap(scrollView.documentView as? NSTextView)
        let manager = try XCTUnwrap(textView.layoutManager)
        let container = try XCTUnwrap(textView.textContainer)
        manager.ensureLayout(for: container)

        XCTAssertEqual(textView.string, tree, "Long data URLs and the final AX elements must remain intact.")
        XCTAssertFalse(textView.isEditable)
        XCTAssertTrue(textView.isSelectable)
        XCTAssertTrue(scrollView.hasHorizontalScroller)
        XCTAssertTrue(scrollView.hasVerticalScroller)
        XCTAssertGreaterThan(textView.frame.width, viewport.width * 100)
        XCTAssertGreaterThan(textView.frame.height, viewport.height * 10)
        XCTAssertEqual(host.frame.width, viewport.width, accuracy: 0.5)
        XCTAssertEqual(host.frame.height, viewport.height, accuracy: 0.5)
        XCTAssertEqual(scrollView.frame.width, viewport.width, accuracy: 0.5)
        XCTAssertEqual(scrollView.frame.height, viewport.height, accuracy: 0.5)
        XCTAssertEqual(scrollView.contentView.bounds.origin.x, 0, accuracy: 0.5)
        XCTAssertEqual(scrollView.contentView.bounds.origin.y, 0, accuracy: 0.5)

        let firstGlyph = manager.glyphRange(forCharacterRange: NSRange(location: 0, length: 1), actualCharacterRange: nil)
        let firstGlyphRect = manager.boundingRect(forGlyphRange: firstGlyph, in: container)
            .offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
        XCTAssertFalse(firstGlyphRect.isEmpty)
        XCTAssertTrue(textView.visibleRect.intersects(firstGlyphRect), "The beginning of the tree must be visible instead of a blank or horizontally offset viewport.")
    }

    @MainActor
    private func firstDescendant<T: NSView>(of type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for child in view.subviews {
            if let match = firstDescendant(of: type, in: child) { return match }
        }
        return nil
    }
}
