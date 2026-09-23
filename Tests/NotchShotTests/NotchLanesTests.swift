// SPDX-License-Identifier: MIT
import XCTest
@testable import NotchShot

final class NotchLanesTests: XCTestCase {
    func testRightLaneFollowsTheChoiceWhenNothingMoreUrgentShows() {
        XCTAssertEqual(NotchIndicator.shotCount.content(isCapturing: false, shotCount: 3, permissionsReady: true), .count(3))
        XCTAssertEqual(NotchIndicator.shotCount.content(isCapturing: false, shotCount: 0, permissionsReady: true), .dot(ready: true),
                       "An empty shelf shows the ready dot instead of a zero.")
        XCTAssertEqual(NotchIndicator.statusDot.content(isCapturing: false, shotCount: 3, permissionsReady: true), .dot(ready: true))
        XCTAssertEqual(NotchIndicator.none.content(isCapturing: false, shotCount: 3, permissionsReady: true), .nothing)
    }

    func testCaptureProgressAndMissingPermissionsAlwaysShow() {
        for indicator in NotchIndicator.allCases {
            XCTAssertEqual(indicator.content(isCapturing: true, shotCount: 2, permissionsReady: true), .progress, "\(indicator)")
            XCTAssertEqual(indicator.content(isCapturing: true, shotCount: 2, permissionsReady: false), .progress, "\(indicator)")
            XCTAssertEqual(indicator.content(isCapturing: false, shotCount: 2, permissionsReady: false), .dot(ready: false),
                           "\(indicator): a capture would fail, so the warning shows.")
        }
    }

    @MainActor
    func testLaneChoicesDefaultPersistAndRejectUnknownValues() {
        let (preferences, clipboard) = isolatedStoreDependencies()
        let store = CaptureStore(preferences: preferences, clipboard: clipboard)
        XCTAssertEqual(store.notchMark, .aperture)
        XCTAssertEqual(store.notchIndicator, .shotCount)

        store.notchMark = .viewfinder
        store.notchIndicator = .none
        store.stop()
        let restored = CaptureStore(preferences: preferences, clipboard: clipboard)
        XCTAssertEqual(restored.notchMark, .viewfinder)
        XCTAssertEqual(restored.notchIndicator, .none)
        restored.stop()

        preferences.set("photographer", forKey: "notchMark")
        preferences.set(3, forKey: "notchIndicator")
        let malformed = CaptureStore(preferences: preferences, clipboard: clipboard)
        XCTAssertEqual(malformed.notchMark, .aperture)
        XCTAssertEqual(malformed.notchIndicator, .shotCount)
        malformed.stop()
    }
}
