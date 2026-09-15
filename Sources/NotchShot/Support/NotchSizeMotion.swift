// SPDX-License-Identifier: MIT
import CoreGraphics
import Foundation

/// Independent size springs let an already open notch change pages without
/// replacing its expanded endpoint underneath an expansion progress of one.
/// Both axes reuse the same timing and interruption behavior as the reveal.
struct NotchSizeMotion {
    struct Sample: Equatable {
        let size: CGSize
        let velocity: CGVector
        let isSettled: Bool
    }

    private let minimum: CGSize
    private let maximum: CGSize
    private var widthMotion: NotchMotion
    private var heightMotion: NotchMotion

    init(size: CGSize, minimum: CGSize, maximum: CGSize, at timestamp: TimeInterval) {
        self.minimum = minimum
        self.maximum = maximum
        widthMotion = NotchMotion(progress: Self.fraction(size.width, from: minimum.width, to: maximum.width), at: timestamp)
        heightMotion = NotchMotion(progress: Self.fraction(size.height, from: minimum.height, to: maximum.height), at: timestamp)
    }

    @discardableResult
    mutating func retarget(to size: CGSize, at timestamp: TimeInterval, reduceMotion: Bool = false) -> Sample {
        widthMotion.retarget(to: Self.fraction(size.width, from: minimum.width, to: maximum.width), at: timestamp,
                             reduceMotion: reduceMotion)
        heightMotion.retarget(to: Self.fraction(size.height, from: minimum.height, to: maximum.height), at: timestamp,
                              reduceMotion: reduceMotion)
        return sample(at: timestamp)
    }

    func sample(at timestamp: TimeInterval) -> Sample {
        let width = widthMotion.sample(at: timestamp)
        let height = heightMotion.sample(at: timestamp)
        let widthRange = maximum.width - minimum.width
        let heightRange = maximum.height - minimum.height
        return Sample(
            size: CGSize(width: minimum.width + widthRange * width.progress,
                         height: minimum.height + heightRange * height.progress),
            velocity: CGVector(dx: widthRange * width.velocity, dy: heightRange * height.velocity),
            isSettled: width.isSettled && height.isSettled
        )
    }

    private static func fraction(_ value: CGFloat, from minimum: CGFloat, to maximum: CGFloat) -> CGFloat {
        guard maximum > minimum else { return 0 }
        return (value - minimum) / (maximum - minimum)
    }
}
