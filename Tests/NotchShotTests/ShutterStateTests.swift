// SPDX-License-Identifier: MIT
import XCTest
@testable import NotchShot

final class ShutterStateTests: XCTestCase {
    func testApertureFollowsCaptureProgress() {
        XCTAssertEqual(ShutterState.resolve(isCapturing: false, hasPendingShot: false, isLanding: false), .open)
        XCTAssertEqual(ShutterState.resolve(isCapturing: true, hasPendingShot: false, isLanding: false), .shut)
        XCTAssertEqual(ShutterState.resolve(isCapturing: true, hasPendingShot: true, isLanding: false), .half,
                       "The screenshot is ready while text and tree are still being read.")
        XCTAssertEqual(ShutterState.resolve(isCapturing: false, hasPendingShot: true, isLanding: true), .reopening)
        XCTAssertEqual(ShutterState.resolve(isCapturing: false, hasPendingShot: false, isLanding: true), .open,
                       "Landing without a shot has nothing to show.")
    }

    func testBladesCloseForTheShutterAndOpenPastRestOnLanding() {
        XCTAssertEqual(ShutterState.shut.opening, 0)
        XCTAssertLessThan(ShutterState.shut.opening, ShutterState.half.opening)
        XCTAssertLessThan(ShutterState.half.opening, ShutterState.open.opening)
        XCTAssertLessThan(ShutterState.open.opening, ShutterState.reopening.opening)
        for state in ShutterState.allCases {
            XCTAssertTrue((0...1).contains(state.opening), "\(state)")
        }
    }
}
