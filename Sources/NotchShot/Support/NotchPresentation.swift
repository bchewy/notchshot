// SPDX-License-Identifier: MIT
import CoreGraphics
import Observation

/// The rendered state of the notch, shared by the native panel and SwiftUI.
/// CaptureStore.isExpanded remains the requested state; this follows the motion.
@Observable @MainActor
final class NotchPresentation {
    private(set) var progress: CGFloat
    private(set) var size: CGSize

    init(progress: CGFloat, size: CGSize) {
        self.progress = progress
        self.size = size
    }

    func update(progress: CGFloat, size: CGSize) {
        self.progress = progress
        self.size = size
    }
}
