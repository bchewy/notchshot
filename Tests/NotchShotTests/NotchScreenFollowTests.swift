// SPDX-License-Identifier: MIT
import CoreGraphics
import XCTest
@testable import NotchShot

final class NotchScreenFollowTests: XCTestCase {
    private let primary = NotchScreenFollowTests.display(1, x: 0, y: 0)
    private let left = NotchScreenFollowTests.display(2, x: -100, y: 0)
    private let above = NotchScreenFollowTests.display(3, x: 0, y: 100)

    func testInitialSelectionAndDisconnectedRecoveryAreImmediateEvenWhileBlocked() {
        var policy = NotchScreenFollowPolicy()
        let displays = [primary, left, above]
        XCTAssertEqual(policy.destination(displays: displays, preferredID: 1, currentID: nil,
                                          pointer: CGPoint(x: -50, y: 50), enabled: true,
                                          blocked: true, now: 0), 2)
        XCTAssertEqual(policy.destination(displays: displays, preferredID: 1, currentID: 99,
                                          pointer: CGPoint(x: 50, y: 150), enabled: true,
                                          blocked: true, now: 0), 3)
        XCTAssertEqual(policy.destination(displays: displays, preferredID: 1, currentID: nil,
                                          pointer: CGPoint(x: -50, y: 50), enabled: false,
                                          blocked: true, now: 0), 1)
    }

    func testNegativeOriginsAndDisplaysAboveRequireTheSettleDelay() {
        var policy = NotchScreenFollowPolicy(settleDelay: 0.5)
        let displays = [primary, left, above]
        XCTAssertEqual(destination(&policy, displays, current: 1, point: CGPoint(x: -50, y: 50), at: 0), 1)
        XCTAssertEqual(destination(&policy, displays, current: 1, point: CGPoint(x: -50, y: 50), at: 0.49), 1)
        XCTAssertEqual(destination(&policy, displays, current: 1, point: CGPoint(x: -50, y: 50), at: 0.5), 2)
        XCTAssertEqual(destination(&policy, displays, current: 2, point: CGPoint(x: 50, y: 150), at: 1), 2)
        XCTAssertEqual(destination(&policy, displays, current: 2, point: CGPoint(x: 50, y: 150), at: 1.5), 3)
    }

    func testSharedBoundariesHaveDeterministicHalfOpenOwnership() {
        var policy = NotchScreenFollowPolicy()
        for displays in [[primary, left, above], [above, left, primary]] {
            XCTAssertEqual(destination(&policy, displays, current: nil, point: CGPoint(x: 0, y: 50), at: 0), 1)
            XCTAssertEqual(destination(&policy, displays, current: nil, point: CGPoint(x: 50, y: 100), at: 0), 3)
            XCTAssertEqual(destination(&policy, displays, current: nil, point: CGPoint(x: -100, y: 0), at: 0), 2)
            XCTAssertEqual(destination(&policy, displays, current: 2, point: CGPoint(x: 100, y: 50), at: 5), 2)
        }
    }

    func testGapAndOutsidePointerRetainCurrentAndCancelPendingMove() {
        var policy = NotchScreenFollowPolicy(settleDelay: 0.5)
        let distant = Self.display(4, x: 200, y: 0)
        let displays = [primary, distant]
        XCTAssertEqual(destination(&policy, displays, current: 1, point: CGPoint(x: 250, y: 50), at: 0), 1)
        XCTAssertEqual(destination(&policy, displays, current: 1, point: CGPoint(x: 150, y: 50), at: 0.4), 1)
        XCTAssertEqual(destination(&policy, displays, current: 1, point: CGPoint(x: 250, y: 50), at: 0.6), 1)
        XCTAssertEqual(destination(&policy, displays, current: 1, point: CGPoint(x: 250, y: 50), at: 1), 1)
        XCTAssertEqual(destination(&policy, displays, current: 1, point: CGPoint(x: 500, y: -500), at: 5), 1)
    }

    func testQuickVisitsAndReturningToCurrentRestartTheCountdown() {
        var policy = NotchScreenFollowPolicy(settleDelay: 0.5)
        let displays = [primary, left, above]
        XCTAssertEqual(destination(&policy, displays, current: 1, point: CGPoint(x: -50, y: 50), at: 0), 1)
        XCTAssertEqual(destination(&policy, displays, current: 1, point: CGPoint(x: 50, y: 150), at: 0.4), 1)
        XCTAssertEqual(destination(&policy, displays, current: 1, point: CGPoint(x: -50, y: 50), at: 0.6), 1)
        XCTAssertEqual(destination(&policy, displays, current: 1, point: CGPoint(x: 50, y: 50), at: 1), 1)
        XCTAssertEqual(destination(&policy, displays, current: 1, point: CGPoint(x: -50, y: 50), at: 1.1), 1)
        XCTAssertEqual(destination(&policy, displays, current: 1, point: CGPoint(x: -50, y: 50), at: 1.7), 2)
    }

    func testBlockedInteractionCancelsCandidateAndRequiresFreshDwellAfterRelease() {
        var policy = NotchScreenFollowPolicy(settleDelay: 0.5)
        let displays = [primary, left]
        let pointer = CGPoint(x: -50, y: 50)
        XCTAssertEqual(destination(&policy, displays, current: 1, point: pointer, at: 0), 1)
        XCTAssertEqual(destination(&policy, displays, current: 1, point: pointer, blocked: true, at: 1), 1)
        XCTAssertEqual(destination(&policy, displays, current: 1, point: pointer, at: 2), 1)
        XCTAssertEqual(destination(&policy, displays, current: 1, point: pointer, at: 2.49), 1)
        XCTAssertEqual(destination(&policy, displays, current: 1, point: pointer, at: 2.5), 2)
    }

    func testDisablingCancelsCandidateAndDefersPreferredReturnWhileBlocked() {
        var policy = NotchScreenFollowPolicy(settleDelay: 0.5)
        let displays = [primary, left]
        let pointer = CGPoint(x: -50, y: 50)
        XCTAssertEqual(destination(&policy, displays, current: 1, point: pointer, at: 0), 1)
        XCTAssertEqual(destination(&policy, displays, current: 1, point: pointer, enabled: false, at: 1), 1)
        XCTAssertEqual(destination(&policy, displays, current: 1, point: pointer, at: 2), 1)
        XCTAssertEqual(destination(&policy, displays, current: 1, point: pointer, at: 2.5), 2)
        XCTAssertEqual(destination(&policy, displays, current: 2, point: pointer,
                                   enabled: false, blocked: true, at: 3), 2)
        XCTAssertEqual(destination(&policy, displays, current: 2, point: pointer, enabled: false, at: 4), 1)
    }

    func testDisconnectRecoversToPointerOrPreferredAndDropsOldCandidate() {
        var policy = NotchScreenFollowPolicy(settleDelay: 0.5)
        XCTAssertEqual(destination(&policy, [primary, left, above], current: 1,
                                   point: CGPoint(x: -50, y: 50), at: 0), 1)
        XCTAssertEqual(destination(&policy, [left, above], current: 1,
                                   point: CGPoint(x: 50, y: 150), blocked: true, at: 0.1), 3)
        XCTAssertEqual(destination(&policy, [primary, left, above], current: 3,
                                   point: CGPoint(x: -50, y: 50), at: 1), 3)
        XCTAssertEqual(destination(&policy, [primary, left, above], current: 3,
                                   point: CGPoint(x: -50, y: 50), at: 1.5), 2)
        XCTAssertEqual(destination(&policy, [primary, above], current: 2,
                                   point: CGPoint(x: -50, y: 50), blocked: true, at: 2), 1)
    }

    func testScreenReorderingPreservesCandidateByDisplayID() {
        var policy = NotchScreenFollowPolicy(settleDelay: 0.5)
        let pointer = CGPoint(x: -50, y: 50)
        XCTAssertEqual(destination(&policy, [primary, left], current: 1, point: pointer, at: 0), 1)
        XCTAssertEqual(destination(&policy, [left, primary], current: 1, point: pointer, at: 0.5), 2)
    }

    func testNoDisplaysClearsCandidateAndReappearanceRecovers() {
        var policy = NotchScreenFollowPolicy(settleDelay: 0.5)
        let pointer = CGPoint(x: -50, y: 50)
        XCTAssertEqual(destination(&policy, [primary, left], current: 1, point: pointer, at: 0), 1)
        XCTAssertNil(destination(&policy, [], current: 1, point: pointer, at: 1))
        XCTAssertEqual(destination(&policy, [primary, left], current: 1, point: pointer, at: 2), 1)
        XCTAssertEqual(destination(&policy, [left], current: nil, point: pointer, blocked: true, at: 3), 2)
    }

    func testMissingPreferredUsesFirstAvailableDisplay() {
        var policy = NotchScreenFollowPolicy()
        XCTAssertEqual(destination(&policy, [left, above], current: nil, point: CGPoint(x: 500, y: 500), at: 0), 2)
        XCTAssertEqual(destination(&policy, [left, above], current: 3, point: CGPoint(x: 50, y: 150),
                                   enabled: false, at: 1), 2)
    }

    func testExplicitResetAndClockReversalRequireFreshDwell() {
        var policy = NotchScreenFollowPolicy(settleDelay: 0.5)
        let displays = [primary, left]
        let pointer = CGPoint(x: -50, y: 50)
        XCTAssertEqual(destination(&policy, displays, current: 1, point: pointer, at: 10), 1)
        policy.reset()
        XCTAssertEqual(destination(&policy, displays, current: 1, point: pointer, at: 11), 1)
        XCTAssertEqual(destination(&policy, displays, current: 1, point: pointer, at: 1), 1)
        XCTAssertEqual(destination(&policy, displays, current: 1, point: pointer, at: 1.5), 2)
    }

    private func destination(_ policy: inout NotchScreenFollowPolicy, _ displays: [NotchDisplay],
                             current: CGDirectDisplayID?, point: CGPoint, enabled: Bool = true,
                             blocked: Bool = false, at now: TimeInterval) -> CGDirectDisplayID? {
        policy.destination(displays: displays, preferredID: 1, currentID: current,
                           pointer: point, enabled: enabled, blocked: blocked, now: now)
    }

    private static func display(_ id: CGDirectDisplayID, x: CGFloat, y: CGFloat) -> NotchDisplay {
        let frame = CGRect(x: x, y: y, width: 100, height: 100)
        return NotchDisplay(id: id, frame: frame,
                            notchRect: CGRect(x: frame.midX - 10, y: frame.maxY - 5, width: 20, height: 5))
    }
}
