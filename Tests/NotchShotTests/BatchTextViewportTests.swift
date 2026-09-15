// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI
import XCTest
@testable import NotchShot

final class BatchTextViewportTests: XCTestCase {
    @MainActor
    func testLongUnicodeContextWrapsWithinViewportAndCopiesEveryCharacter() throws {
        _ = NSApplication.shared
        let paragraph = "Long readable context with 中文内容 and 👩🏽‍💻 remains complete when wrapping. "
        let text = String(repeating: paragraph, count: 300) + "END_OF_SELECTED_CONTEXT"
        let viewport = NSSize(width: 362, height: 220)
        let host = NSHostingView(rootView: ReadOnlyCaptureTextView(
            text: text, accessibilityLabel: "Selected shot context", wrapsLines: true
        ).frame(width: viewport.width, height: viewport.height))
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: viewport),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: viewport)
        host.layoutSubtreeIfNeeded()

        let scroll = try XCTUnwrap(firstDescendant(of: NSScrollView.self, in: host))
        scroll.layoutSubtreeIfNeeded()
        let textView = try XCTUnwrap(scroll.documentView as? NSTextView)
        let manager = try XCTUnwrap(textView.layoutManager)
        let container = try XCTUnwrap(textView.textContainer)
        manager.ensureLayout(for: container)

        XCTAssertFalse(window.isVisible, "Viewport QA must not disturb the live app.")
        XCTAssertEqual(textView.string, text)
        XCTAssertFalse(textView.isEditable)
        XCTAssertTrue(textView.isSelectable)
        XCTAssertFalse(scroll.hasHorizontalScroller)
        XCTAssertTrue(scroll.hasVerticalScroller)
        XCTAssertEqual(textView.frame.width, scroll.contentSize.width, accuracy: 0.5)
        XCTAssertGreaterThan(textView.frame.height, viewport.height * 10)
        XCTAssertLessThanOrEqual(manager.usedRect(for: container).maxX,
                                 scroll.contentSize.width - textView.textContainerInset.width * 2 + 0.5)
        XCTAssertEqual(textView.accessibilityLabel(), "Selected shot context")

        let firstGlyph = manager.glyphRange(forCharacterRange: NSRange(location: 0, length: 1),
                                           actualCharacterRange: nil)
        let firstRect = manager.boundingRect(forGlyphRange: firstGlyph, in: container)
            .offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
        XCTAssertTrue(textView.visibleRect.intersects(firstRect), "Review starts with readable text in view.")

        let board = NSPasteboard(name: NSPasteboard.Name("NotchShot.BatchTextViewport.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        textView.setSelectedRange(NSRange(location: 0, length: (text as NSString).length))
        XCTAssertEqual(textView.selectedRange().length, (text as NSString).length)
        XCTAssertTrue(textView.writeSelection(to: board, types: textView.writablePasteboardTypes))
        XCTAssertTrue(board.string(forType: .string) == text, "Visual wrapping must never insert or drop copied characters.")
    }

    @MainActor
    func testWrappedContextReflowsWhenReviewWidthChanges() throws {
        _ = NSApplication.shared
        let text = String(repeating: "Readable context 中文 with a long sequence of words. ", count: 100)
        let host = NSHostingView(rootView: ReadOnlyCaptureTextView(text: text, wrapsLines: true))
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 390, height: 220),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let scroll = try XCTUnwrap(firstDescendant(of: NSScrollView.self, in: host))
        scroll.layoutSubtreeIfNeeded()
        let textView = try XCTUnwrap(scroll.documentView as? NSTextView)
        let widerHeight = textView.frame.height

        window.setContentSize(NSSize(width: 240, height: 220))
        host.layoutSubtreeIfNeeded()
        scroll.layoutSubtreeIfNeeded()

        XCTAssertEqual(textView.string, text)
        XCTAssertEqual(textView.frame.width, scroll.contentSize.width, accuracy: 0.5)
        XCTAssertGreaterThan(textView.frame.height, widerHeight,
                             "A narrower review must remeasure paragraphs instead of clipping their right side.")
        XCTAssertFalse(scroll.hasHorizontalScroller)
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
