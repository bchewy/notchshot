// SPDX-License-Identifier: MIT
import Foundation

/// A read-only reflection of capture progress. Decoration never owns the
/// screenshot, its flight, or the shelf's open/close timing.
enum ApertureState: CaseIterable {
    /// Waiting to capture.
    case open
    /// Capturing: the blades close like a shutter.
    case shut
    /// The screenshot arrived; text and tree are still being read.
    case half
    /// The shot is landing on the shelf: the blades reopen past rest.
    case reopening

    static func resolve(isCapturing: Bool, hasPendingShot: Bool, isLanding: Bool) -> Self {
        if isLanding && hasPendingShot { return .reopening }
        // The screenshot arrives before accessibility extraction finishes.
        if hasPendingShot { return .half }
        return isCapturing ? .shut : .open
    }

    /// 0 is closed to a pinhole; 1 is wide open.
    var opening: CGFloat {
        switch self {
        case .open: 0.72
        case .shut: 0
        case .half: 0.34
        case .reopening: 0.9
        }
    }

    /// Blades turn as they close, like a lens ring.
    var turn: Double {
        switch self {
        case .open: 0
        case .shut: 55
        case .half: 28
        case .reopening: -12
        }
    }
}
