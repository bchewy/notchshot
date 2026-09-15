// SPDX-License-Identifier: MIT
import CoreGraphics
import XCTest
@testable import NotchShot

final class NotchSizeMotionTests: XCTestCase {
    private let collapsed = CGSize(width: 277, height: 32)
    private let shelf = CGSize(width: 440, height: 180)
    private let settings = CGSize(width: 440, height: 440)
    private let detail = CGSize(width: 440, height: 480)

    func testOpenPageResizeStartsAtCurrentSizeAndReachesExactTarget() {
        var motion = NotchSizeMotion(size: shelf, minimum: collapsed, maximum: detail, at: 0)
        let start = motion.retarget(to: settings, at: 0)
        // Converting the independent spring's normalized position back into
        // points can round by a few ulps; continuity is a geometric invariant.
        XCTAssertEqual(start.size.width, shelf.width, accuracy: 0.000_001)
        XCTAssertEqual(start.size.height, shelf.height, accuracy: 0.000_001)
        XCTAssertFalse(start.isSettled)
        let middle = motion.sample(at: 0.08)
        XCTAssertEqual(middle.size.width, shelf.width)
        XCTAssertGreaterThan(middle.size.height, shelf.height)
        XCTAssertLessThan(middle.size.height, settings.height)
        XCTAssertEqual(motion.sample(at: 0.25), .init(size: settings, velocity: .zero, isSettled: true))
    }

    func testSwitchingPagesAndThenCollapsingPreservesPositionAndVelocity() {
        var motion = NotchSizeMotion(size: collapsed, minimum: collapsed, maximum: detail, at: 0)
        motion.retarget(to: shelf, at: 0)
        let beforePageChange = motion.sample(at: 0.063)
        let afterPageChange = motion.retarget(to: detail, at: 0.063)
        assertContinuous(beforePageChange, afterPageChange)

        let beforeCollapse = motion.sample(at: 0.11)
        let afterCollapse = motion.retarget(to: collapsed, at: 0.11)
        assertContinuous(beforeCollapse, afterCollapse)
        XCTAssertEqual(motion.sample(at: 1), .init(size: collapsed, velocity: .zero, isSettled: true))
    }

    func testRapidPageChangesRemainBoundedAndAnchoredUntilLatestStateSettles() {
        let notch = CGRect(x: -851, y: 1350, width: 189, height: 32)
        var motion = NotchSizeMotion(size: collapsed, minimum: collapsed, maximum: detail, at: 0)
        let targets = [detail, shelf, settings, collapsed, detail, shelf]
        for (index, target) in targets.enumerated() {
            let time = Double(index) * 0.033
            assertContinuous(motion.sample(at: time), motion.retarget(to: target, at: time))
            for offset in [0.0, 0.01, 0.02, 0.03] {
                let size = motion.sample(at: time + offset).size
                XCTAssertTrue((collapsed.width...detail.width).contains(size.width))
                XCTAssertTrue((collapsed.height...detail.height).contains(size.height))
                let frame = NotchGeometry.frame(anchoredTo: notch, size: size)
                XCTAssertEqual(frame.midX, notch.midX, accuracy: 0.000_001)
                XCTAssertEqual(frame.maxY, notch.maxY, accuracy: 0.000_001)
            }
        }
        XCTAssertEqual(motion.sample(at: 1), .init(size: shelf, velocity: .zero, isSettled: true))
    }

    func testReducedMotionDropsPriorSizeVelocityAndSnapsToPage() {
        var motion = NotchSizeMotion(size: collapsed, minimum: collapsed, maximum: detail, at: 0)
        motion.retarget(to: detail, at: 0)
        XCTAssertGreaterThan(motion.sample(at: 0.06).velocity.dy, 0)
        let reduced = motion.retarget(to: shelf, at: 0.06, reduceMotion: true)
        XCTAssertEqual(reduced, .init(size: shelf, velocity: .zero, isSettled: true))
        XCTAssertEqual(motion.sample(at: 1), reduced)
    }

    private func assertContinuous(_ before: NotchSizeMotion.Sample, _ after: NotchSizeMotion.Sample,
                                  file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(before.size.width, after.size.width, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(before.size.height, after.size.height, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(before.velocity.dx, after.velocity.dx, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(before.velocity.dy, after.velocity.dy, accuracy: 0.000_001, file: file, line: line)
    }
}
