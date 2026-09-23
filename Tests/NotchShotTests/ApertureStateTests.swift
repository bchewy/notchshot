// SPDX-License-Identifier: MIT
import XCTest
@testable import NotchShot

final class ApertureStateTests: XCTestCase {
    func testApertureFollowsCaptureProgress() {
        XCTAssertEqual(ApertureState.resolve(isCapturing: false, hasPendingShot: false, isLanding: false), .open)
        XCTAssertEqual(ApertureState.resolve(isCapturing: true, hasPendingShot: false, isLanding: false), .shut)
        XCTAssertEqual(ApertureState.resolve(isCapturing: true, hasPendingShot: true, isLanding: false), .half,
                       "The screenshot is ready while text and tree are still being read.")
        XCTAssertEqual(ApertureState.resolve(isCapturing: false, hasPendingShot: true, isLanding: true), .reopening)
        XCTAssertEqual(ApertureState.resolve(isCapturing: false, hasPendingShot: false, isLanding: true), .open,
                       "Landing without a shot has nothing to show.")
    }

    func testBladesCloseForTheShutterAndOpenPastRestOnLanding() {
        XCTAssertEqual(ApertureState.shut.opening, 0)
        XCTAssertLessThan(ApertureState.shut.opening, ApertureState.half.opening)
        XCTAssertLessThan(ApertureState.half.opening, ApertureState.open.opening)
        XCTAssertLessThan(ApertureState.open.opening, ApertureState.reopening.opening)
        for state in ApertureState.allCases {
            XCTAssertTrue((0...1).contains(state.opening), "\(state)")
        }
    }
}
