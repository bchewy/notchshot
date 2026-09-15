// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI

/// A native text viewport keeps very long AX values out of SwiftUI's size calculation.
/// SwiftUI owns the supplied content; AppKit owns only text selection and scrolling.
struct ReadOnlyCaptureTextView: NSViewRepresentable {
    let text: String
    var accessibilityLabel = "Accessibility tree"
    var wrapsLines = false

    func makeNSView(context: Context) -> NSScrollView {
        CaptureTextScrollView(frame: .zero)
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        (nsView as? CaptureTextScrollView)?.setContent(text, accessibilityLabel: accessibilityLabel, wrapsLines: wrapsLines)
    }
}

private final class CaptureTextScrollView: NSScrollView {
    private let captureTextView: NSTextView
    private var measuredDocumentSize: NSSize?
    private var shouldResetScroll = false
    private var wrapsLines = false

    override init(frame frameRect: NSRect) {
        // TextKit measures the document without affecting the SwiftUI host.
        // Trees retain unwrapped lines; prose can wrap within the viewport.
        // Neither mode shortens content, including URLs and data URLs.
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(containerSize: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        container.lineFragmentPadding = 0
        captureTextView = NSTextView(frame: NSRect(x: 0, y: 0, width: 1, height: 1), textContainer: container)

        super.init(frame: frameRect)

        drawsBackground = false
        borderType = .noBorder
        hasVerticalScroller = true
        hasHorizontalScroller = true
        autohidesScrollers = true
        scrollerStyle = .overlay
        contentView.drawsBackground = false
        appearance = NSAppearance(named: .darkAqua)

        captureTextView.isEditable = false
        captureTextView.isSelectable = true
        captureTextView.isRichText = false
        captureTextView.importsGraphics = false
        captureTextView.allowsUndo = false
        captureTextView.drawsBackground = false
        captureTextView.backgroundColor = .clear
        captureTextView.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        captureTextView.textColor = .white.withAlphaComponent(0.78)
        captureTextView.textContainerInset = NSSize(width: 12, height: 12)
        captureTextView.minSize = .zero
        captureTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        captureTextView.isHorizontallyResizable = false
        captureTextView.isVerticallyResizable = false
        captureTextView.autoresizingMask = []
        captureTextView.setAccessibilityLabel("Accessibility tree")
        captureTextView.selectedTextAttributes = [
            .backgroundColor: NSColor.systemTeal.withAlphaComponent(0.4),
            .foregroundColor: NSColor.white
        ]
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        captureTextView.defaultParagraphStyle = paragraph
        documentView = captureTextView
    }

    required init?(coder: NSCoder) {
        fatalError("CaptureTextScrollView is created programmatically")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    func setContent(_ text: String, accessibilityLabel: String, wrapsLines: Bool) {
        captureTextView.setAccessibilityLabel(accessibilityLabel)
        let changedText = captureTextView.string != text
        let changedWrapping = self.wrapsLines != wrapsLines
        guard changedText || changedWrapping else { return }
        self.wrapsLines = wrapsLines
        hasHorizontalScroller = !wrapsLines
        if changedText {
            captureTextView.string = text
            captureTextView.setSelectedRange(NSRange(location: 0, length: 0))
        }
        measuredDocumentSize = nil
        shouldResetScroll = true
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard contentSize.width > 0, contentSize.height > 0,
              let manager = captureTextView.layoutManager,
              let container = captureTextView.textContainer else { return }

        let inset = captureTextView.textContainerInset
        let containerWidth = wrapsLines
            ? max(1, contentSize.width - inset.width * 2)
            : CGFloat.greatestFiniteMagnitude
        if container.containerSize.width != containerWidth {
            container.containerSize = NSSize(width: containerWidth, height: CGFloat.greatestFiniteMagnitude)
            measuredDocumentSize = nil
        }
        if measuredDocumentSize == nil {
            manager.ensureLayout(for: container)
            let usedRect = manager.usedRect(for: container)
            measuredDocumentSize = NSSize(
                width: ceil(usedRect.maxX + inset.width * 2),
                height: ceil(usedRect.maxY + inset.height * 2)
            )
        }
        if let measuredDocumentSize {
            let documentSize = NSSize(
                width: wrapsLines ? contentSize.width : max(contentSize.width, measuredDocumentSize.width),
                height: max(contentSize.height, measuredDocumentSize.height)
            )
            if captureTextView.frame.size != documentSize {
                captureTextView.setFrameSize(documentSize)
            }
        }
        if shouldResetScroll {
            shouldResetScroll = false
            contentView.scroll(to: .zero)
            reflectScrolledClipView(contentView)
        }
    }
}
