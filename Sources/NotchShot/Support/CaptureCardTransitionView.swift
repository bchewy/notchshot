// SPDX-License-Identifier: MIT
import AppKit

/// A raster canvas keeps the preview's labels and controls from relaying out
/// while its window changes size between the captured app, card, and shelf.
@MainActor
final class CaptureCardTransitionView: NSView {
    enum Style {
        case entrance
        case landing
    }

    var cardImage: NSImage? { didSet { needsDisplay = true } }
    var screenshot: NSImage? { didSet { needsDisplay = true } }
    var style: Style = .entrance { didSet { needsDisplay = true } }
    var progress: CGFloat = 0 { didSet { needsDisplay = true } }
    var flash: CGFloat = 0 { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let amount = Self.clamped(progress)
        let cardOpacity: CGFloat
        let cornerRadius: CGFloat
        switch style {
        case .entrance:
            cardOpacity = Self.smoothstep((amount - 0.62) / 0.38)
            cornerRadius = 12 + 4 * amount
        case .landing:
            cardOpacity = 1 - Self.smoothstep(amount / 0.65)
            cornerRadius = 16 - 10 * Self.smoothstep(amount)
        }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current?.imageInterpolation = .high
        let radius = min(cornerRadius, min(bounds.width, bounds.height) / 2)
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).addClip()
        NSColor(calibratedWhite: 0.055, alpha: 1).setFill()
        bounds.fill()

        // Keep the underlying surface opaque throughout the morph. The window
        // controller alone controls the final arrival fade, if one is needed.
        if let screenshot {
            draw(screenshot, in: Self.fittedRect(for: screenshot.size, within: bounds), opacity: 1)
        }
        if let cardImage {
            let opacity = screenshot == nil ? 1 : cardOpacity
            draw(cardImage, in: bounds, opacity: opacity)
        }
        let flashOpacity = Self.clamped(flash) * 0.22
        if flashOpacity > 0 {
            NSColor.white.withAlphaComponent(flashOpacity).setFill()
            bounds.fill()
        }
    }

    /// Call while the hosting view is mounted at the normal preview size.
    /// The bitmap retains the window's backing scale for crisp card labels.
    static func snapshot(of view: NSView, size: CGSize) -> NSImage? {
        guard size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { return nil }
        let originalSize = view.frame.size
        if originalSize != size { view.setFrameSize(size) }
        defer {
            if originalSize != size {
                view.setFrameSize(originalSize)
                view.layoutSubtreeIfNeeded()
            }
        }
        view.layoutSubtreeIfNeeded()
        let rect = CGRect(origin: view.bounds.origin, size: size)
        guard let representation = view.bitmapImageRepForCachingDisplay(in: rect) else { return nil }
        view.cacheDisplay(in: rect, to: representation)
        let image = NSImage(size: size)
        image.addRepresentation(representation)
        return image
    }

    private func draw(_ image: NSImage, in rect: CGRect, opacity: CGFloat) {
        guard opacity > 0, rect.width > 0, rect.height > 0 else { return }
        image.draw(in: rect, from: .zero, operation: .sourceOver,
                   fraction: opacity, respectFlipped: true, hints: nil)
    }

    private static func fittedRect(for size: CGSize, within bounds: CGRect) -> CGRect {
        guard size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { return .zero }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: bounds.midX - fitted.width / 2, y: bounds.midY - fitted.height / 2,
                      width: fitted.width, height: fitted.height)
    }

    private static func clamped(_ value: CGFloat) -> CGFloat {
        value.isFinite ? min(1, max(0, value)) : 0
    }

    private static func smoothstep(_ value: CGFloat) -> CGFloat {
        let value = clamped(value)
        return value * value * (3 - 2 * value)
    }
}
