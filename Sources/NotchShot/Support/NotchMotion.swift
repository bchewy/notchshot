// SPDX-License-Identifier: MIT
import CoreGraphics
import Foundation

/// An analytic critically damped spring. Sampling depends on elapsed time, not
/// frame count, and retargeting retains both position and velocity.
struct NotchMotion {
    struct Sample: Equatable {
        let progress: CGFloat
        let velocity: CGFloat
        let isSettled: Bool
    }

    private(set) var target: CGFloat
    private var initialProgress: CGFloat
    private var initialVelocity: CGFloat = 0
    private var startTime: TimeInterval
    // A no-bounce dropdown should settle within the 250 ms motion budget.
    // At ten time constants a critical spring has only 0.05% travel left.
    // See docs/MOTION.md for the native adaptation of Emil Kowalski's guidance.
    private let frequency: CGFloat = 10 / 0.25

    init(progress: CGFloat, at timestamp: TimeInterval) {
        let bounded = Self.bounded(progress)
        target = bounded
        initialProgress = bounded
        startTime = timestamp
    }

    @discardableResult
    mutating func retarget(to progress: CGFloat, at timestamp: TimeInterval, reduceMotion: Bool = false) -> Sample {
        let nextTarget = Self.bounded(progress)
        if reduceMotion {
            reset(to: nextTarget, at: timestamp)
            return sample(at: timestamp)
        }

        let current = sample(at: timestamp)
        target = nextTarget
        initialProgress = current.progress
        initialVelocity = current.velocity
        startTime = timestamp
        return sample(at: timestamp)
    }

    mutating func reset(to progress: CGFloat, at timestamp: TimeInterval) {
        target = Self.bounded(progress)
        initialProgress = target
        initialVelocity = 0
        startTime = timestamp
    }

    func sample(at timestamp: TimeInterval) -> Sample {
        let elapsed = CGFloat(max(0, timestamp - startTime))
        let displacement = initialProgress - target
        let coefficient = initialVelocity + frequency * displacement
        let decay = CGFloat(exp(-Double(frequency * elapsed)))
        let position = target + (displacement + coefficient * elapsed) * decay
        var velocity = (initialVelocity - frequency * coefficient * elapsed) * decay
        let progress = Self.bounded(position)
        if (position < 0 && velocity < 0) || (position > 1 && velocity > 0) { velocity = 0 }

        // Finish exactly, avoiding a permanent subpixel gap or a live display
        // link after the motion has become imperceptible (within 0.25 s at rest).
        if abs(progress - target) < 0.001, abs(velocity) < 0.02 {
            return Sample(progress: target, velocity: 0, isSettled: true)
        }
        return Sample(progress: progress, velocity: velocity, isSettled: false)
    }

    static func size(at progress: CGFloat, collapsed: CGSize, expanded: CGSize) -> CGSize {
        let fraction = bounded(progress)
        return CGSize(width: collapsed.width + (expanded.width - collapsed.width) * fraction,
                      height: collapsed.height + (expanded.height - collapsed.height) * fraction)
    }

    private static func bounded(_ progress: CGFloat) -> CGFloat {
        progress.isFinite ? min(1, max(0, progress)) : 0
    }
}
