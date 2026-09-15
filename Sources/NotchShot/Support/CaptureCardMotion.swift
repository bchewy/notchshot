// SPDX-License-Identifier: MIT
import CoreGraphics

/// One presentation sample controls both native bounds and the image morph.
enum CaptureCardMotion {
    static let entranceDuration = 0.46
    static let flightDuration = 0.52

    struct Sample {
        var frame: CGRect
        var alpha: CGFloat = 1
        var visualProgress: CGFloat
        var flash: CGFloat = 0
    }

    static func entrance(from source: CGRect?, to preview: CGRect, progress: CGFloat) -> Sample {
        let p = clamped(progress)
        if let source {
            // A single window-scoped flash, followed by the screenshot peeling
            // into the floating card. The source app keeps keyboard focus.
            let flashFraction: CGFloat = 0.26
            let peel = clamped((p - flashFraction) / (1 - flashFraction))
            let eased = 1 - pow(1 - peel, 3)
            return Sample(frame: interpolated(source, preview, eased),
                          visualProgress: peel,
                          flash: p < flashFraction ? sin(.pi * p / flashFraction) : 0)
        }
        let initial = preview.insetBy(dx: preview.width * 0.055, dy: preview.height * 0.055)
            .offsetBy(dx: 0, dy: -10)
        let eased = 1 - pow(1 - p, 3)
        return Sample(frame: interpolated(initial, preview, eased), alpha: min(1, p * 4),
                      visualProgress: 1)
    }

    static func flight(from initial: CGRect, to destination: CGRect, progress: CGFloat) -> Sample {
        let p = clamped(progress)
        let eased = p * p * (3 - 2 * p)
        var frame = interpolated(initial, destination, eased)
        // Lift first, then steer into the slot; zero curvature at the endpoints.
        // The lift is bounded so a card already near the shelf cannot overshoot.
        let distance = hypot(destination.midX - initial.midX, destination.midY - initial.midY)
        let lift = min(55, distance * 0.12) * sin(.pi * eased)
        frame.origin.y += lift
        return Sample(frame: frame, visualProgress: p)
    }

    private static func clamped(_ value: CGFloat) -> CGFloat { max(0, min(1, value)) }

    private static func interpolated(_ first: CGRect, _ second: CGRect, _ p: CGFloat) -> CGRect {
        CGRect(x: first.minX + (second.minX - first.minX) * p,
               y: first.minY + (second.minY - first.minY) * p,
               width: first.width + (second.width - first.width) * p,
               height: first.height + (second.height - first.height) * p)
    }
}
