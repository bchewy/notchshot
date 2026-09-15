// SPDX-License-Identifier: MIT
import AppKit
import XCTest
@testable import NotchShot

final class ShotHoverTrackingTests: XCTestCase {
    @MainActor
    func testEveryThumbnailEdgeAndCornerCanEnterWithoutReachingItsCenter() throws {
        let fixture = HoverTrackingFixture()
        defer { fixture.close() }
        let points = [
            NSPoint(x: 0.5, y: 0.5), NSPoint(x: 71.5, y: 0.5),
            NSPoint(x: 0.5, y: 37.5), NSPoint(x: 71.5, y: 37.5),
            NSPoint(x: 0.5, y: 19), NSPoint(x: 71.5, y: 19),
            NSPoint(x: 36, y: 0.5), NSPoint(x: 36, y: 37.5)
        ]
        for point in points {
            fixture.point(at: NSPoint(x: -10, y: -10))
            fixture.anchor.reconcileHover()
            fixture.point(at: point)
            fixture.anchor.mouseEntered(with: try fixture.event(.mouseEntered))
            XCTAssertTrue(fixture.shortcut.isRegistered, "The full tile must respond at \(point).")
            XCTAssertEqual(fixture.shortcut.captureID, fixture.capture.id)
            fixture.binding.onCapture?()
        }
        XCTAssertEqual(fixture.copies, points.count)
        XCTAssertEqual(fixture.binding.registrations, points.count)
    }

    @MainActor
    func testMouseMovementRecoversAMissedEntryWithoutCrossingAnotherBoundary() throws {
        let fixture = HoverTrackingFixture()
        defer { fixture.close() }
        fixture.point(at: NSPoint(x: -1, y: 19))
        fixture.anchor.mouseEntered(with: try fixture.event(.mouseEntered))
        XCTAssertFalse(fixture.shortcut.isRegistered,
                       "Outside pointer must miss bounds \(fixture.anchor.bounds), visibleRect \(fixture.anchor.visibleRect).")

        fixture.point(at: NSPoint(x: 0.5, y: 19))
        fixture.anchor.mouseMoved(with: try fixture.event(.mouseMoved))
        XCTAssertTrue(fixture.shortcut.isRegistered)
        XCTAssertEqual(fixture.binding.registrations, 1)
        fixture.binding.onCapture?()
        XCTAssertEqual(fixture.copies, 1)
    }

    @MainActor
    func testEnablingPreviewUnderAStationaryPointerStartsHover() async {
        let fixture = HoverTrackingFixture(enabled: false)
        defer { fixture.close() }
        fixture.point(at: NSPoint(x: 1, y: 1))
        await flushMainQueue()
        XCTAssertFalse(fixture.shortcut.isRegistered)

        fixture.configure(enabled: true)
        await flushMainQueue()
        XCTAssertTrue(fixture.shortcut.isRegistered)
        XCTAssertEqual(fixture.binding.registrations, 1)
        XCTAssertEqual(fixture.hoverStates.last, true)
    }

    @MainActor
    func testGeometryChangeRearmsHoverForTheStationaryPointer() async throws {
        let fixture = HoverTrackingFixture()
        defer { fixture.close() }
        fixture.point(at: NSPoint(x: 36, y: 19))
        fixture.anchor.mouseEntered(with: try fixture.event(.mouseEntered))
        let oldCopy = try XCTUnwrap(fixture.binding.onCapture)
        let registrations = fixture.binding.registrations

        fixture.anchor.setFrameOrigin(NSPoint(x: 41, y: 40))
        fixture.anchor.updateTrackingAreas()
        await flushMainQueue()
        XCTAssertTrue(fixture.shortcut.isRegistered)
        XCTAssertEqual(fixture.binding.registrations, registrations + 1,
                       "The changed anchor needs a fresh copy validity frame.")
        oldCopy()
        XCTAssertEqual(fixture.copies, 0, "A queued key from the old geometry must stay invalid.")
        fixture.binding.onCapture?()
        XCTAssertEqual(fixture.copies, 1)
        XCTAssertEqual(fixture.hoverStates.last, true)
    }

    @MainActor
    func testRepeatedMovesAndTrackingUpdatesDoNotRestartTheSameHover() async throws {
        let fixture = HoverTrackingFixture()
        defer { fixture.close() }
        fixture.point(at: NSPoint(x: 1, y: 19))
        fixture.anchor.mouseEntered(with: try fixture.event(.mouseEntered))
        for x: CGFloat in [2, 5, 10, 15, 20, 30, 50, 71] {
            fixture.point(at: NSPoint(x: x, y: 19))
            fixture.anchor.mouseMoved(with: try fixture.event(.mouseMoved))
            fixture.anchor.updateTrackingAreas()
        }
        await flushMainQueue()
        XCTAssertTrue(fixture.shortcut.isRegistered)
        XCTAssertEqual(fixture.binding.registrations, 1,
                       "Movement inside the same tile must not restart its preview delay or shortcut.")
        XCTAssertEqual(fixture.hoverStates.filter { $0 }.count, 1)
        XCTAssertEqual(fixture.hoverStates.last, true)
    }

    @MainActor
    func testClippedThumbnailOnlyTracksItsVisiblePart() throws {
        let fixture = HoverTrackingFixture(clipped: true)
        defer { fixture.close() }
        let visible = fixture.anchor.visibleRect
        XCTAssertFalse(visible.isEmpty)
        XCTAssertLessThan(visible.width, fixture.anchor.bounds.width)

        fixture.point(at: NSPoint(x: visible.maxX + 0.5, y: visible.midY))
        fixture.anchor.mouseMoved(with: try fixture.event(.mouseMoved))
        XCTAssertFalse(fixture.shortcut.isRegistered,
                       "A scrolled-out part of the document must never take Command-C.")

        fixture.point(at: NSPoint(x: visible.maxX - 0.5, y: visible.midY))
        fixture.anchor.mouseMoved(with: try fixture.event(.mouseMoved))
        XCTAssertTrue(fixture.shortcut.isRegistered, "The visible clipped edge should still respond.")

        fixture.point(at: NSPoint(x: visible.maxX + 0.5, y: visible.midY))
        fixture.anchor.mouseMoved(with: try fixture.event(.mouseMoved))
        XCTAssertFalse(fixture.shortcut.isRegistered)
    }

    @MainActor
    func testStopCancelsQueuedStationaryPointerRefresh() async {
        let fixture = HoverTrackingFixture(enabled: false)
        defer { fixture.close() }
        fixture.point(at: NSPoint(x: 36, y: 19))
        fixture.configure(enabled: true)
        fixture.anchor.updateTrackingAreas()
        fixture.anchor.stop()
        await flushMainQueue()
        XCTAssertFalse(fixture.anchor.isPreviewEnabled)
        XCTAssertFalse(fixture.shortcut.isRegistered)
        XCTAssertEqual(fixture.binding.registrations, 0)
    }

    @MainActor
    func testDetachingCancelsQueuedStationaryPointerRefresh() async {
        let fixture = HoverTrackingFixture(enabled: false)
        defer { fixture.close() }
        fixture.point(at: NSPoint(x: 36, y: 19))
        fixture.configure(enabled: true)
        fixture.anchor.updateTrackingAreas()
        fixture.anchor.removeFromSuperview()
        await flushMainQueue()
        XCTAssertNil(fixture.anchor.window)
        XCTAssertFalse(fixture.shortcut.isRegistered)
        XCTAssertEqual(fixture.binding.registrations, 0)
    }

    @MainActor
    func testCoveredTileCannotAcquireOrKeepTheCopyShortcut() async throws {
        let fixture = HoverTrackingFixture(enabled: false)
        defer { fixture.close() }
        fixture.point(at: NSPoint(x: 36, y: 19))
        fixture.window.isPointerTarget = false
        fixture.configure(enabled: true)
        await flushMainQueue()
        XCTAssertFalse(fixture.shortcut.isRegistered,
                       "Automatic resampling must not arm a tile underneath a popover or another app.")
        fixture.anchor.mouseMoved(with: try fixture.event(.mouseMoved))
        XCTAssertEqual(fixture.binding.registrations, 0)

        fixture.window.isPointerTarget = true
        fixture.anchor.mouseMoved(with: try fixture.event(.mouseMoved))
        XCTAssertTrue(fixture.shortcut.isRegistered)
        let queuedCopy = try XCTUnwrap(fixture.binding.onCapture)
        fixture.window.isPointerTarget = false
        queuedCopy()
        XCTAssertEqual(fixture.copies, 0)
        XCTAssertFalse(fixture.shortcut.isRegistered,
                       "Coverage must also invalidate a key delivered after the tile was hovered.")
    }

    @MainActor
    private func flushMainQueue() async {
        // Native representable updates intentionally reconcile on the next
        // main turn; drain a second turn for a dismissal's deferred callback.
        for _ in 0..<2 {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }
}

@MainActor
private final class HoverTrackingFixture {
    let window: HoverTrackingWindow
    let anchor = ShotHoverAnchorNSView(frame: NSRect(x: 40, y: 40, width: 72, height: 38),
                                      pointerTargetsWindow: { window, _ in
        (window as? HoverTrackingWindow)?.isPointerTarget == true
    })
    let binding = HoverTrackingBinding()
    let shortcut: HoverCopyShortcutService
    let controller: ShotHoverPreviewController
    let capture = CaptureResult(appName: "Hover fixture", bundleIdentifier: "test.notchshot.hover",
                                windowTitle: "Local tracking test", pngData: nil, importedText: "Fixture context")
    var copies = 0
    var hoverStates: [Bool] = []

    init(enabled: Bool = true, clipped: Bool = false) {
        _ = NSApplication.shared
        shortcut = HoverCopyShortcutService(binding: binding)
        // This test never orders a window or registers a real global shortcut.
        // The long delay prevents the controller presenting any preview UI.
        controller = ShotHoverPreviewController(hoverCopy: shortcut, previewDelay: .seconds(3_600))
        window = HoverTrackingWindow(contentRect: NSRect(x: 100, y: 100, width: 300, height: 200),
                                     styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        window.contentView = root
        if clipped {
            let clip = NSClipView(frame: NSRect(x: 40, y: 40, width: 36, height: 38))
            root.addSubview(clip)
            anchor.setFrameOrigin(.zero)
            clip.documentView = anchor
        } else {
            root.addSubview(anchor)
        }
        configure(enabled: enabled)
    }

    func configure(enabled: Bool) {
        anchor.configure(capture: capture, controller: controller, isEnabled: enabled,
                         copyShot: { [weak self] in
            self?.copies += 1
            return self != nil
        }, onHover: { [weak self] in self?.hoverStates.append($0) })
    }

    func point(at point: NSPoint) {
        window.simulatedPointer = anchor.convert(point, to: nil)
    }

    func event(_ type: NSEvent.EventType) throws -> NSEvent {
        let event: NSEvent?
        if type == .mouseEntered || type == .mouseExited {
            event = NSEvent.enterExitEvent(with: type, location: window.simulatedPointer,
                                           modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                           context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)
        } else {
            event = NSEvent.mouseEvent(with: type, location: window.simulatedPointer,
                                      modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                      context: nil, eventNumber: 0, clickCount: 0, pressure: 0)
        }
        return try XCTUnwrap(event)
    }

    func close() {
        anchor.stop()
        controller.dismiss()
        anchor.removeFromSuperview()
        window.close()
    }
}

@MainActor
private final class HoverTrackingWindow: NSWindow {
    var simulatedPointer = NSPoint(x: -100, y: -100)
    var isPointerTarget = true
    override var isVisible: Bool { true }
    override var occlusionState: NSWindow.OcclusionState { [.visible] }
    override var mouseLocationOutsideOfEventStream: NSPoint { simulatedPointer }
}

@MainActor
private final class HoverTrackingBinding: HoverCopyShortcutBinding {
    var onCapture: (() -> Void)?
    var registrations = 0
    var registeredShortcut: CaptureShortcut?

    func register(shortcut: CaptureShortcut) -> GlobalShortcutService.RegistrationResult {
        registrations += 1
        registeredShortcut = shortcut
        return .success
    }

    func unregister() { registeredShortcut = nil }
}
