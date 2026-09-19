// SPDX-License-Identifier: MIT
import CoreGraphics
import Foundation

/// Screen geometry copied from AppKit, allowing selection to be tested without
/// requiring a particular monitor arrangement or retaining an NSScreen.
struct NotchDisplay: Equatable {
    let id: CGDirectDisplayID
    let frame: CGRect
    let notchRect: CGRect
}

/// Chooses when the existing notch may move. Returning the current display means
/// stay put; recovering from a disconnected display bypasses interaction gates.
struct NotchScreenFollowPolicy {
    private let settleDelay: TimeInterval
    private var candidateID: CGDirectDisplayID?
    private var candidateSince: TimeInterval?

    init(settleDelay: TimeInterval = 0.35) {
        self.settleDelay = settleDelay.isFinite ? max(0, settleDelay) : 0.35
    }

    mutating func reset() {
        candidateID = nil
        candidateSince = nil
    }

    mutating func destination(displays: [NotchDisplay], preferredID: CGDirectDisplayID?,
                              currentID: CGDirectDisplayID?, pointer: CGPoint,
                              enabled: Bool, blocked: Bool, now: TimeInterval) -> CGDirectDisplayID? {
        guard let first = displays.first else {
            reset()
            return nil
        }
        let preferred = displays.first { $0.id == preferredID } ?? first
        let pointed = displays.first { Self.contains(pointer, in: $0.frame) }
        guard let current = displays.first(where: { $0.id == currentID }) else {
            reset()
            return enabled ? (pointed?.id ?? preferred.id) : preferred.id
        }

        guard enabled else {
            reset()
            return blocked ? current.id : preferred.id
        }
        guard !blocked, let pointed, pointed.id != current.id, now.isFinite else {
            reset()
            return current.id
        }
        let continuesCandidate = candidateID == pointed.id && candidateSince.map { now >= $0 } == true
        if !continuesCandidate {
            candidateID = pointed.id
            candidateSince = now
        }
        guard let candidateSince, now - candidateSince >= settleDelay else { return current.id }
        reset()
        return pointed.id
    }

    private static func contains(_ point: CGPoint, in frame: CGRect) -> Bool {
        // Half-open edges make a shared boundary belong to exactly one display,
        // independently of the ordering of NSScreen.screens.
        point.x >= frame.minX && point.x < frame.maxX
            && point.y >= frame.minY && point.y < frame.maxY
    }
}
