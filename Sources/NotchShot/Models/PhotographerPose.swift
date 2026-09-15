// SPDX-License-Identifier: MIT
import Foundation

/// A read-only reflection of capture progress. Decoration never owns the
/// screenshot, its flight, or the shelf's open/close timing.
enum PhotographerPose: CaseIterable {
    case idle, framing, holding, shelving

    static func resolve(isCapturing: Bool, hasPendingShot: Bool, isLanding: Bool) -> Self {
        if isLanding && hasPendingShot { return .shelving }
        // The screenshot arrives before accessibility extraction finishes.
        if hasPendingShot { return .holding }
        return isCapturing ? .framing : .idle
    }
}
