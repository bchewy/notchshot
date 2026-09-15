// SPDX-License-Identifier: MIT
import CoreGraphics

/// Coordinate and placement calculations kept independent of NSScreen so
/// captures on offset displays can use the same animation as the main display.
enum CaptureCardGeometry {
    static func appKitFrame(fromCGFrame frame: CGRect, mainDisplayTop: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: mainDisplayTop - frame.maxY,
               width: frame.width, height: frame.height)
    }

    /// `screens` contains AppKit screen frames. Screen order determines ties;
    /// a missing or completely off-screen source uses the caller's fallback.
    static func screenIndex(forCGFrame source: CGRect?, screens: [CGRect],
                            mainDisplayTop: CGFloat, fallbackIndex: Int = 0) -> Int? {
        guard !screens.isEmpty else { return nil }
        let fallback = screens.indices.contains(fallbackIndex) ? fallbackIndex : 0
        guard let source, isUsable(source) else { return fallback }
        let frame = appKitFrame(fromCGFrame: source, mainDisplayTop: mainDisplayTop)
        var bestIndex = fallback
        var greatestArea: CGFloat = 0
        for (index, screen) in screens.enumerated() {
            let intersection = frame.intersection(screen)
            guard !intersection.isNull, !intersection.isEmpty else { continue }
            let area = intersection.width * intersection.height
            if area > greatestArea {
                greatestArea = area
                bestIndex = index
            }
        }
        return bestIndex
    }

    /// Centers the preview on the captured window, keeping it inside the
    /// visible screen. If the card is larger than that area, fit it uniformly.
    static func previewFrame(size: CGSize, sourceCGFrame source: CGRect?,
                             visibleFrame: CGRect, mainDisplayTop: CGFloat,
                             inset: CGFloat = 20) -> CGRect {
        let safeInset = max(0, min(inset, min(visibleFrame.width, visibleFrame.height) / 2))
        let available = visibleFrame.insetBy(dx: safeInset, dy: safeInset)
        let width = max(0, size.width)
        let height = max(0, size.height)
        let scale = min(1, width > 0 ? available.width / width : 1,
                        height > 0 ? available.height / height : 1)
        let fittedSize = CGSize(width: width * scale, height: height * scale)
        let center: CGPoint
        if let source, isUsable(source) {
            let frame = appKitFrame(fromCGFrame: source, mainDisplayTop: mainDisplayTop)
            center = CGPoint(x: frame.midX, y: frame.midY)
        } else {
            center = CGPoint(x: visibleFrame.midX, y: visibleFrame.midY)
        }
        return CGRect(
            x: min(max(center.x - fittedSize.width / 2, available.minX), available.maxX - fittedSize.width),
            y: min(max(center.y - fittedSize.height / 2, available.minY), available.maxY - fittedSize.height),
            width: fittedSize.width, height: fittedSize.height
        )
    }

    private static func isUsable(_ frame: CGRect) -> Bool {
        frame.origin.x.isFinite && frame.origin.y.isFinite &&
            frame.width.isFinite && frame.height.isFinite && frame.width > 0 && frame.height > 0
    }
}
