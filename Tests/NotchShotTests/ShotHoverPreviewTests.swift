// SPDX-License-Identifier: MIT
import AppKit
import XCTest
@testable import NotchShot

final class ShotHoverPreviewTests: XCTestCase {
    @MainActor
    func testPreviewSitsBelowShelfWithoutCoveringThumbnail() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 950)
        let shelf = CGRect(x: 536, y: 802, width: 440, height: 180)
        let thumbnail = CGRect(x: 560, y: 850, width: 70, height: 36)
        let preview = ShotHoverPreviewController.previewFrame(thumbnail: thumbnail, shelf: shelf,
                                                               screen: screen, size: ShotHoverPreviewView.size)
        XCTAssertEqual(preview.maxY, shelf.minY - 8)
        XCTAssertEqual(preview.midX, thumbnail.midX)
        XCTAssertFalse(preview.intersects(shelf))
        XCTAssertTrue(screen.contains(preview))
    }

    @MainActor
    func testPreviewIsClampedOnOffsetDisplayAndAtBothEdges() {
        let screen = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        for x: CGFloat in [-1920, -70] {
            let thumbnail = CGRect(x: x, y: 100, width: 70, height: 36)
            let preview = ShotHoverPreviewController.previewFrame(thumbnail: thumbnail,
                                                                  shelf: CGRect(x: x, y: -150, width: 440, height: 180),
                                                                  screen: screen, size: ShotHoverPreviewView.size)
            XCTAssertTrue(screen.insetBy(dx: 8, dy: 8).contains(preview))
            XCTAssertEqual(preview.size, ShotHoverPreviewView.size)
        }
    }

    @MainActor
    func testPreviewWindowCannotTakeKeyboardFocusOrInterceptClicks() {
        _ = NSApplication.shared
        let panel = ShotHoverPreviewPanel(contentRect: CGRect(origin: .zero, size: ShotHoverPreviewView.size))
        defer { panel.close() }
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(panel.isVisible, "The test must not show UI.")
    }
}
