// SPDX-License-Identifier: MIT
import CoreGraphics
import XCTest
@testable import NotchShot

final class CaptureCardGeometryTests: XCTestCase {
    func testTopOriginConversionPreservesWindowOnDisplayAboveMainScreen() {
        let frame = CaptureCardGeometry.appKitFrame(
            fromCGFrame: CGRect(x: -900, y: -700, width: 800, height: 600), mainDisplayTop: 1000
        )
        XCTAssertEqual(frame, CGRect(x: -900, y: 1100, width: 800, height: 600))
    }

    func testTopOriginConversionPreservesWindowOnDisplayBelowMainScreen() {
        let frame = CaptureCardGeometry.appKitFrame(
            fromCGFrame: CGRect(x: 1500, y: 1200, width: 600, height: 400), mainDisplayTop: 1000
        )
        XCTAssertEqual(frame, CGRect(x: 1500, y: -600, width: 600, height: 400))
    }

    func testScreenChoiceUsesLargestIntersectionAcrossNegativeDisplayOrigins() {
        let screens = [CGRect(x: 0, y: 0, width: 1500, height: 1000),
                       CGRect(x: -1200, y: 300, width: 1200, height: 900)]
        let source = CGRect(x: -600, y: 200, width: 800, height: 500)
        XCTAssertEqual(CaptureCardGeometry.screenIndex(forCGFrame: source, screens: screens,
                                                       mainDisplayTop: 1000), 1)
    }

    func testScreenChoiceFallsBackForMissingOffscreenAndInvalidSources() {
        let screens = [CGRect(x: 0, y: 0, width: 900, height: 700),
                       CGRect(x: 900, y: -200, width: 1200, height: 800)]
        for source in [nil, CGRect(x: 3000, y: 0, width: 200, height: 200),
                       CGRect(x: CGFloat.infinity, y: 0, width: 100, height: 100)] {
            XCTAssertEqual(CaptureCardGeometry.screenIndex(forCGFrame: source, screens: screens,
                                                           mainDisplayTop: 700, fallbackIndex: 1), 1)
        }
        XCTAssertEqual(CaptureCardGeometry.screenIndex(forCGFrame: nil, screens: screens,
                                                       mainDisplayTop: 700, fallbackIndex: 99), 0)
        XCTAssertNil(CaptureCardGeometry.screenIndex(forCGFrame: nil, screens: [], mainDisplayTop: 700))
    }

    func testPreviewCentersOnSourceWindowInsteadOfDisplayOrNotch() {
        let source = CGRect(x: 300, y: 200, width: 600, height: 400)
        let frame = CaptureCardGeometry.previewFrame(
            size: CGSize(width: 240, height: 180), sourceCGFrame: source,
            visibleFrame: CGRect(x: 0, y: 60, width: 1500, height: 900), mainDisplayTop: 1000
        )
        XCTAssertEqual(frame.midX, 600)
        XCTAssertEqual(frame.midY, 600)
        XCTAssertEqual(frame.size, CGSize(width: 240, height: 180))
    }

    func testPreviewClampsToVisibleEdgesOnOffsetDisplay() {
        let visible = CGRect(x: -1200, y: 340, width: 1200, height: 820)
        let frame = CaptureCardGeometry.previewFrame(
            size: CGSize(width: 240, height: 180),
            sourceCGFrame: CGRect(x: -1300, y: -300, width: 240, height: 200),
            visibleFrame: visible, mainDisplayTop: 1000, inset: 16
        )
        XCTAssertEqual(frame.minX, visible.minX + 16)
        XCTAssertEqual(frame.maxY, visible.maxY - 16)
        XCTAssertTrue(visible.contains(frame))
    }

    func testOversizedCardFitsInsideVisibleAreaWithAspectRatioPreserved() {
        let visible = CGRect(x: 500, y: -700, width: 180, height: 100)
        let frame = CaptureCardGeometry.previewFrame(
            size: CGSize(width: 400, height: 200), sourceCGFrame: nil,
            visibleFrame: visible, mainDisplayTop: 1000, inset: 10
        )
        XCTAssertTrue(visible.insetBy(dx: 10, dy: 10).contains(frame))
        XCTAssertEqual(frame.width / frame.height, 2, accuracy: 0.0001)
        XCTAssertEqual(frame.midX, visible.midX)
        XCTAssertEqual(frame.midY, visible.midY)
    }

    func testMissingSourceFallsBackToVisibleScreenCenter() {
        let visible = CGRect(x: 1800, y: -500, width: 1200, height: 900)
        let frame = CaptureCardGeometry.previewFrame(
            size: CGSize(width: 250, height: 200), sourceCGFrame: nil,
            visibleFrame: visible, mainDisplayTop: 1000
        )
        XCTAssertEqual(frame.midX, visible.midX)
        XCTAssertEqual(frame.midY, visible.midY)
    }
}
