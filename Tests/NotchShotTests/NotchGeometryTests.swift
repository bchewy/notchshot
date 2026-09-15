// SPDX-License-Identifier: MIT
import AppKit
import XCTest
@testable import NotchShot

final class NotchGeometryTests: XCTestCase {
    @MainActor
    func testNativePanelReanchorsLateContentResizeAndFrameChanges() {
        _ = NSApplication.shared
        let notch = CGRect(x: 661, y: 950, width: 189, height: 32)
        let expanded = NotchGeometry.frame(anchoredTo: notch, size: CGSize(width: 560, height: 580))
        let panel = NotchPanel(frame: expanded)
        defer { panel.close() }
        panel.notchAnchor = notch

        // Reproduce the host's late resize, which otherwise preserves the old
        // expanded left edge even after the controller positioned the panel.
        panel.setContentSize(CGSize(width: 277, height: 32))
        XCTAssertEqual(panel.frame.midX, notch.midX, accuracy: 0.5)
        XCTAssertEqual(panel.frame.maxY, notch.maxY, accuracy: 0.5)

        panel.setFrame(CGRect(x: expanded.minX, y: 200, width: 277, height: 32), display: false)
        XCTAssertEqual(panel.frame.midX, notch.midX, accuracy: 0.5)
        XCTAssertEqual(panel.frame.maxY, notch.maxY, accuracy: 0.5)

        panel.setFrameOrigin(CGPoint(x: 100, y: 100))
        XCTAssertEqual(panel.frame.midX, notch.midX, accuracy: 0.5)
        XCTAssertEqual(panel.frame.maxY, notch.maxY, accuracy: 0.5)
    }

    func testAsymmetricSafeAreasAnchorToCutoutInsteadOfDisplayMidpoint() {
        let notch = NotchGeometry.notchRect(
            in: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeAreaTop: 32, leftAreaWidth: 663, rightAreaWidth: 664
        )
        XCTAssertEqual(notch.midX, 755.5)
        XCTAssertEqual(notch.size, CGSize(width: 189, height: 32))
    }

    func testSecondaryDisplayOriginIsIncludedInNotchAnchor() {
        let notch = NotchGeometry.notchRect(
            in: CGRect(x: -1512, y: 400, width: 1512, height: 982),
            safeAreaTop: 32, leftAreaWidth: 663, rightAreaWidth: 664
        )
        let frame = NotchGeometry.frame(anchoredTo: notch, size: CGSize(width: 277, height: 32))
        XCTAssertEqual(frame, CGRect(x: -895, y: 1350, width: 277, height: 32))
    }

    func testCollapsePreservesCutoutCenterAndTopEdge() {
        let notch = CGRect(x: 661, y: 950, width: 189, height: 32)
        let expanded = NotchGeometry.frame(anchoredTo: notch, size: CGSize(width: 560, height: 580))
        let collapsed = NotchGeometry.frame(anchoredTo: notch, size: CGSize(width: 277, height: 32))
        XCTAssertEqual(expanded.midX, collapsed.midX)
        XCTAssertEqual(expanded.maxY, collapsed.maxY)
        XCTAssertEqual(collapsed.minX, 617)
        XCTAssertNotEqual(expanded.minX, collapsed.minX)
    }

    func testDisplayWithoutCutoutAndIncompleteGeometryUseCenteredFallback() {
        let screen = CGRect(x: 1920, y: -200, width: 1440, height: 900)
        let external = NotchGeometry.notchRect(in: screen, safeAreaTop: 0, leftAreaWidth: nil, rightAreaWidth: nil)
        XCTAssertEqual(external, CGRect(x: 2545, y: 672, width: 190, height: 28))
        let incomplete = NotchGeometry.notchRect(in: screen, safeAreaTop: 32, leftAreaWidth: 663, rightAreaWidth: nil)
        XCTAssertEqual(incomplete.midX, screen.midX)
        XCTAssertEqual(incomplete.size, CGSize(width: 190, height: 32))
    }
}
