// SPDX-License-Identifier: MIT
import AppKit
import XCTest
@testable import NotchShot

final class NotchAttentionTests: XCTestCase {
    @MainActor
    func testStaleKeyWindowDoesNotPretendToOwnKeyboardAttention() {
        XCTAssertFalse(NotchAttentionMonitor.hasMeaningfulKeyboardFocus(
            windowIsKey: true, responder: .none, keyboardInteractionOwned: false))
        XCTAssertFalse(NotchAttentionMonitor.hasMeaningfulKeyboardFocus(
            windowIsKey: true, responder: .none, keyboardInteractionOwned: true))
        XCTAssertFalse(NotchAttentionMonitor.hasMeaningfulKeyboardFocus(
            windowIsKey: true, responder: .control, keyboardInteractionOwned: false))
    }

    @MainActor
    func testEditingSelectionAndKeyboardNavigationKeepTheKeyWindowEngaged() {
        for responder in [NotchAttentionMonitor.ResponderKind.editableText, .selectedText] {
            for keyboardOwned in [false, true] {
                XCTAssertTrue(NotchAttentionMonitor.hasMeaningfulKeyboardFocus(
                    windowIsKey: true, responder: responder, keyboardInteractionOwned: keyboardOwned))
            }
        }
        XCTAssertTrue(NotchAttentionMonitor.hasMeaningfulKeyboardFocus(
            windowIsKey: true, responder: .control, keyboardInteractionOwned: true))
    }

    @MainActor
    func testFocusLossReleasesEditingSelectionAndNavigation() {
        for responder in [NotchAttentionMonitor.ResponderKind.none, .control, .editableText, .selectedText] {
            XCTAssertFalse(NotchAttentionMonitor.hasMeaningfulKeyboardFocus(
                windowIsKey: false, responder: responder, keyboardInteractionOwned: true))
        }
    }

    @MainActor
    func testNativeSnapshotTracksStationaryPointerThroughGeometryChanges() {
        _ = NSApplication.shared
        let panel = makePanel()
        defer { panel.close() }
        var pointer = NSPoint(x: 200, y: 150)
        var snapshots: [NotchAttentionMonitor.Snapshot] = []
        var activityCount = 0
        let monitor = NotchAttentionMonitor(panel: panel, mouseLocation: { pointer },
                                            pressedMouseButtons: { 0 },
                                            onSnapshot: { snapshots.append($0) },
                                            onActivity: { activityCount += 1 })
        defer { monitor.setWatching(false) }
        monitor.setWatching(true)
        XCTAssertTrue(monitor.lastSnapshot.surfaceVisible)
        XCTAssertTrue(monitor.lastSnapshot.pointerInside)
        XCTAssertEqual(activityCount, 0)

        panel.setFrame(NSRect(x: 600, y: 100, width: 300, height: 200), display: false)
        monitor.refresh()
        XCTAssertFalse(monitor.lastSnapshot.pointerInside, "Window movement must update presence even without mouse movement.")
        pointer = NSPoint(x: 598, y: 150)
        monitor.refresh()
        XCTAssertTrue(monitor.lastSnapshot.pointerInside, "A small border allowance avoids pointer-edge flicker.")
        pointer = NSPoint(x: 594, y: 150)
        monitor.refresh()
        XCTAssertFalse(monitor.lastSnapshot.pointerInside)
        XCTAssertEqual(activityCount, 0, "Geometry and sampling alone must not extend the idle countdown.")
        let count = snapshots.count
        monitor.refresh()
        monitor.refresh()
        XCTAssertEqual(snapshots.count, count, "Identical samples must not produce repeated state updates.")
    }

    @MainActor
    func testMouseButtonReleaseChangesSnapshotAndStopClearsPresence() {
        _ = NSApplication.shared
        let panel = makePanel()
        defer { panel.close() }
        var buttons = 1
        let monitor = NotchAttentionMonitor(panel: panel, mouseLocation: { NSPoint(x: 0, y: 0) },
                                            pressedMouseButtons: { buttons }, onSnapshot: { _ in },
                                            onActivity: {})
        monitor.setWatching(true)
        XCTAssertTrue(monitor.lastSnapshot.mouseButtonDown)
        XCTAssertFalse(monitor.lastSnapshot.pointerInside)
        buttons = 0
        monitor.refresh()
        XCTAssertFalse(monitor.lastSnapshot.mouseButtonDown)
        monitor.setWatching(false)
        XCTAssertFalse(monitor.isWatching)
        XCTAssertEqual(monitor.lastSnapshot, NotchAttentionMonitor.Snapshot())
        buttons = 1
        monitor.refresh()
        XCTAssertEqual(monitor.lastSnapshot, NotchAttentionMonitor.Snapshot())
    }

    @MainActor
    func testHidingSurfaceStopsMonitoringAndCanRestartCleanly() {
        _ = NSApplication.shared
        let panel = makePanel()
        defer { panel.close() }
        let monitor = NotchAttentionMonitor(panel: panel, mouseLocation: { NSPoint(x: 200, y: 150) },
                                            pressedMouseButtons: { 0 }, onSnapshot: { _ in }, onActivity: {})
        defer { monitor.setWatching(false) }
        monitor.setWatching(true)
        XCTAssertTrue(monitor.isWatching)
        panel.simulatesVisibility = false
        monitor.refresh()
        XCTAssertFalse(monitor.isWatching)
        XCTAssertEqual(monitor.lastSnapshot, NotchAttentionMonitor.Snapshot())
        panel.simulatesVisibility = true
        monitor.setWatching(true)
        XCTAssertTrue(monitor.isWatching)
        XCTAssertTrue(monitor.lastSnapshot.pointerInside)
        panel.alphaValue = 0
        monitor.refresh()
        XCTAssertFalse(monitor.isWatching)
        XCTAssertFalse(monitor.lastSnapshot.surfaceVisible)
    }

    @MainActor
    func testNativeMenuTrackingKeepsNestedMenusProtectedUntilAllEnd() {
        _ = NSApplication.shared
        let panel = makePanel()
        defer { panel.close() }
        var activityCount = 0
        let monitor = NotchAttentionMonitor(panel: panel, mouseLocation: { .zero },
                                            pressedMouseButtons: { 0 }, onSnapshot: { _ in },
                                            onActivity: { activityCount += 1 })
        defer { monitor.setWatching(false) }
        monitor.setWatching(true)
        let parent = NSMenu(title: "Test parent"), child = NSMenu(title: "Test child")
        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: parent)
        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: child)
        XCTAssertTrue(monitor.lastSnapshot.menuTracking)
        XCTAssertEqual(activityCount, 2)
        NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: child)
        XCTAssertTrue(monitor.lastSnapshot.menuTracking)
        NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: parent)
        XCTAssertFalse(monitor.lastSnapshot.menuTracking)
        monitor.setWatching(false)
        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: parent)
        XCTAssertFalse(monitor.lastSnapshot.menuTracking)
        XCTAssertEqual(activityCount, 2, "Stopped monitors must remove their notification observers.")
    }

    @MainActor
    private func makePanel() -> SimulatedVisiblePanel {
        let panel = SimulatedVisiblePanel(contentRect: NSRect(x: 100, y: 100, width: 300, height: 200),
                                          styleMask: [.borderless, .nonactivatingPanel],
                                          backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = false
        // The NSWindow remains unordered: only its visibility query is simulated.
        // Tests must never draw over the user's applications or move their pointer.
        return panel
    }
}

@MainActor
private final class SimulatedVisiblePanel: NSPanel {
    var simulatesVisibility = true
    override var isVisible: Bool { simulatesVisibility }
}
