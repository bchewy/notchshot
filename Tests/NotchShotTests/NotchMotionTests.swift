// SPDX-License-Identifier: MIT
import AppKit
import XCTest
@testable import NotchShot

final class NotchMotionTests: XCTestCase {
    @MainActor
    func testStartsCollapsedAndOpenPagesResizeTheHiddenNativePanel() async throws {
        _ = NSApplication.shared
        guard NotchGeometry.preferredScreen != nil else {
            throw XCTSkip("This native integration test requires WindowServer display access; the test process is headless or sandboxed.")
        }
        let previousWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
        let (preferences, clipboard) = isolatedStoreDependencies()
        let store = CaptureStore(preferences: preferences, clipboard: clipboard)
        // Keep animation time independent of expensive native view mounting.
        // Observation, the real display link, and the real hosting view still
        // deliver every frame; only the time sampled by that link is controlled.
        // Exercise animation even when the host enables Reduce Motion; the
        // separate reduced-motion test covers snapping without changing macOS.
        var motionTime: TimeInterval = 0
        let controller = NotchPanelController(store: store, motionClock: { motionTime },
                                              shouldReduceMotion: { false })
        defer { store.stop() }
        let window = try XCTUnwrap(NSApp.windows.first { !previousWindows.contains(ObjectIdentifier($0)) && $0.title == "NotchShot" })
        defer { window.close() }
        XCTAssertFalse(store.isExpanded)
        XCTAssertEqual(controller.presentation.progress, 0)
        XCTAssertEqual(window.frame.height, max(store.notchHeight, 32), accuracy: 0.5)
        XCTAssertEqual(window.frame.width, store.notchWidth + 36, accuracy: 0.5,
                       "The native window must release the old side padding, not only draw smaller indicators.")
        let anchor = window.frame

        store.isExpanded = true
        try await waitForMotion("opening starts a display link") { controller.isAnimating }
        motionTime += 1
        try await waitForMotion("opening settles") { !controller.isAnimating && controller.presentation.progress == 1 }
        XCTAssertEqual(window.frame.height, 180, accuracy: 0.5)

        // Page changes must animate independently when reveal progress is
        // already one; changing the interpolation endpoint would jump here.
        store.page = .settings
        try await waitForMotion("settings starts a display link") { controller.isAnimating }
        motionTime += 0.08
        try await waitForMotion("settings receives an intermediate native frame") {
            controller.isAnimating && window.frame.height > 180
        }
        XCTAssertLessThan(window.frame.height, 440)
        XCTAssertEqual(controller.presentation.progress, 1)
        XCTAssertEqual(window.frame.size, controller.presentation.size)
        XCTAssertEqual(window.frame.midX, anchor.midX, accuracy: 0.5)
        XCTAssertEqual(window.frame.maxY, anchor.maxY, accuracy: 0.5)
        XCTAssertFalse(window.isVisible)
        motionTime += 1
        try await waitForMotion("settings settles at 440 points") { !controller.isAnimating && abs(window.frame.height - 440) < 0.5 }

        store.page = .detail
        try await waitForMotion("detail starts a display link") { controller.isAnimating }
        motionTime += 1
        try await waitForMotion("detail settles at 480 points") { !controller.isAnimating && abs(window.frame.height - 480) < 0.5 }
        store.page = .shelf
        try await waitForMotion("shelf starts a display link") { controller.isAnimating }
        motionTime += 1
        try await waitForMotion("shelf settles at 180 points") { !controller.isAnimating && abs(window.frame.height - 180) < 0.5 }
        XCTAssertEqual(window.frame.midX, anchor.midX, accuracy: 0.5)
        XCTAssertEqual(window.frame.maxY, anchor.maxY, accuracy: 0.5)
        XCTAssertFalse(window.isVisible, "The regression test must not present UI.")
    }

    @MainActor
    func testReducedMotionSnapsHiddenNativePanelAcrossOpenPagesAndCollapse() async throws {
        _ = NSApplication.shared
        guard NotchGeometry.preferredScreen != nil else {
            throw XCTSkip("This native integration test requires WindowServer display access; the test process is headless or sandboxed.")
        }
        let previousWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
        let (preferences, clipboard) = isolatedStoreDependencies()
        let store = CaptureStore(preferences: preferences, clipboard: clipboard)
        // Frozen time proves each change snaps; an ordinary animation cannot
        // run to its endpoint and accidentally satisfy the reduced-motion test.
        let controller = NotchPanelController(store: store, motionClock: { 0 },
                                              shouldReduceMotion: { true })
        defer { store.stop() }
        let window = try XCTUnwrap(NSApp.windows.first {
            !previousWindows.contains(ObjectIdentifier($0)) && $0.title == "NotchShot"
        })
        defer { window.close() }
        let collapsedFrame = window.frame

        store.isExpanded = true
        try await waitForMotion("reduced-motion opening snaps to the shelf") {
            controller.presentation.progress == 1 && abs(window.frame.height - 180) < 0.5
        }
        assertReducedMotionFrame(window, controller: controller, height: 180, anchor: collapsedFrame)

        store.page = .settings
        try await waitForMotion("reduced-motion settings snaps to 440 points") { abs(window.frame.height - 440) < 0.5 }
        assertReducedMotionFrame(window, controller: controller, height: 440, anchor: collapsedFrame)

        store.page = .detail
        try await waitForMotion("reduced-motion detail snaps to 480 points") { abs(window.frame.height - 480) < 0.5 }
        assertReducedMotionFrame(window, controller: controller, height: 480, anchor: collapsedFrame)

        store.page = .shelf
        try await waitForMotion("reduced-motion shelf snaps to 180 points") { abs(window.frame.height - 180) < 0.5 }
        assertReducedMotionFrame(window, controller: controller, height: 180, anchor: collapsedFrame)

        store.isExpanded = false
        try await waitForMotion("reduced-motion collapse snaps to compact bounds") { controller.presentation.progress == 0 }
        assertReducedMotionFrame(window, controller: controller, height: collapsedFrame.height, anchor: collapsedFrame)
        XCTAssertEqual(window.frame.size, collapsedFrame.size)
    }

    @MainActor
    private func assertReducedMotionFrame(_ window: NSWindow, controller: NotchPanelController,
                                          height: CGFloat, anchor: CGRect,
                                          file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(controller.isAnimating, "Reduce Motion must not start a display link.", file: file, line: line)
        XCTAssertEqual(window.frame.height, height, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(window.frame.size, controller.presentation.size, file: file, line: line)
        XCTAssertEqual(window.frame.midX, anchor.midX, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(window.frame.maxY, anchor.maxY, accuracy: 0.5, file: file, line: line)
        XCTAssertFalse(window.isVisible, "The regression test must not present UI.", file: file, line: line)
    }

    @MainActor
    func testStoreToggleDrivesHiddenNativePanelAndPresentationThroughObservation() async throws {
        _ = NSApplication.shared
        guard NotchGeometry.preferredScreen != nil else {
            throw XCTSkip("This native integration test requires WindowServer display access; the test process is headless or sandboxed.")
        }
        let previousWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
        let (preferences, clipboard) = isolatedStoreDependencies()
        let store = CaptureStore(preferences: preferences, clipboard: clipboard)
        store.isExpanded = true
        let controller = NotchPanelController(store: store)
        defer { store.stop() }
        let window = try XCTUnwrap(NSApp.windows.first { !previousWindows.contains(ObjectIdentifier($0)) && $0.title == "NotchShot" })
        defer { window.close() }
        XCTAssertFalse(window.isVisible, "The regression test must not present UI.")
        let expandedFrame = window.frame
        XCTAssertEqual(controller.presentation.progress, 1)

        store.isExpanded = false
        // A first display tick can move by less than AppKit's pixel rounding.
        // Wait for visible native motion before asserting the smaller frame.
        try await waitForMotion("collapse receives a smaller native frame") { controller.presentation.progress < 1 && window.frame.height < expandedFrame.height }
        XCTAssertLessThan(window.frame.height, expandedFrame.height)
        XCTAssertEqual(window.frame.size, controller.presentation.size)
        XCTAssertEqual(window.frame.midX, expandedFrame.midX, accuracy: 0.5)
        XCTAssertEqual(window.frame.maxY, expandedFrame.maxY, accuracy: 0.5)

        try await waitForMotion("collapse settles") { !controller.isAnimating && controller.presentation.progress == 0 }
        XCTAssertEqual(window.frame.height, max(store.notchHeight, 32), accuracy: 0.5)
        XCTAssertEqual(window.frame.width, store.notchWidth + 36, accuracy: 0.5,
                       "A settled close must not retain an invisible expanded hit area.")
        XCTAssertFalse(window.isVisible)

        // A second change verifies the one-shot observation was re-armed.
        store.isExpanded = true
        try await waitForMotion("reopening receives a native frame") { controller.presentation.progress > 0 }
        try await waitForMotion("reopening settles") { !controller.isAnimating && controller.presentation.progress == 1 }
        XCTAssertEqual(window.frame.size, expandedFrame.size)
        XCTAssertFalse(window.isVisible)
    }

    @MainActor
    private func waitForMotion(_ description: String, _ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        let message = "Timed out waiting for \(description). System Reduce Motion: \(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)."
        FileHandle.standardError.write(Data("[NativeMotion] \(message)\n".utf8))
        throw NSError(domain: "NotchMotionTests", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: message])
    }

    func testOpeningAndClosingHaveBoundedIntermediateFramesAndExactEndpoints() {
        var opening = NotchMotion(progress: 0, at: 0)
        var closing = NotchMotion(progress: 1, at: 0)
        opening.retarget(to: 1, at: 0)
        closing.retarget(to: 0, at: 0)
        var previous: CGFloat = 0
        for time in [0.0, 0.03, 0.08, 0.15, 0.23, 0.3, 0.5] {
            let opened = opening.sample(at: time)
            let closed = closing.sample(at: time)
            XCTAssertGreaterThanOrEqual(opened.progress, previous)
            XCTAssertTrue((0...1).contains(opened.progress))
            XCTAssertEqual(closed.progress, 1 - opened.progress, accuracy: 0.000_001)
            previous = opened.progress
        }
        let middle = opening.sample(at: 0.08)
        XCTAssertGreaterThan(middle.progress, 0)
        XCTAssertLessThan(middle.progress, 1)
        XCTAssertFalse(middle.isSettled)
        XCTAssertEqual(opening.sample(at: 0.25), .init(progress: 1, velocity: 0, isSettled: true), "An uninterrupted dropdown must settle within its 250 ms budget.")
        XCTAssertEqual(closing.sample(at: 0.25), .init(progress: 0, velocity: 0, isSettled: true))
    }

    func testReversalBetweenFramesPreservesPositionAndVelocity() {
        var motion = NotchMotion(progress: 0, at: 0)
        motion.retarget(to: 1, at: 0)
        let before = motion.sample(at: 0.083)
        let after = motion.retarget(to: 0, at: 0.083)
        XCTAssertEqual(after.progress, before.progress, accuracy: 0.000_001)
        XCTAssertEqual(after.velocity, before.velocity, accuracy: 0.000_001)
        // Preserved momentum briefly continues opening before reversing.
        XCTAssertGreaterThan(motion.sample(at: 0.084).progress, after.progress)
        XCTAssertEqual(motion.sample(at: 1), .init(progress: 0, velocity: 0, isSettled: true))
    }

    func testRapidReversalsStayBoundedAndFinishAtLatestRequestedState() {
        var motion = NotchMotion(progress: 0, at: 0)
        motion.retarget(to: 1, at: 0)
        for (index, time) in [0.04, 0.072, 0.09, 0.13, 0.16, 0.19].enumerated() {
            let before = motion.sample(at: time)
            let next: CGFloat = index.isMultiple(of: 2) ? 0 : 1
            let after = motion.retarget(to: next, at: time)
            XCTAssertEqual(after.progress, before.progress, accuracy: 0.000_001)
            XCTAssertEqual(after.velocity, before.velocity, accuracy: 0.000_001)
            XCTAssertTrue((0...1).contains(after.progress))
            XCTAssertTrue((0...1).contains(motion.sample(at: time + 0.005).progress))
        }
        XCTAssertEqual(motion.sample(at: 1), .init(progress: 1, velocity: 0, isSettled: true))
    }

    func testMotionIsIndependentOfDisplayRefreshCadence() {
        var atSixtyHertz = NotchMotion(progress: 0, at: 0)
        var atOneTwentyHertz = NotchMotion(progress: 0, at: 0)
        atSixtyHertz.retarget(to: 1, at: 0)
        atOneTwentyHertz.retarget(to: 1, at: 0)
        for tick in 0...12 { _ = atSixtyHertz.sample(at: Double(tick) / 60) }
        for tick in 0...24 { _ = atOneTwentyHertz.sample(at: Double(tick) / 120) }
        XCTAssertEqual(atSixtyHertz.sample(at: 0.205), atOneTwentyHertz.sample(at: 0.205))
        atSixtyHertz.retarget(to: 0, at: 0.205)
        atOneTwentyHertz.retarget(to: 0, at: 0.205)
        XCTAssertEqual(atSixtyHertz.sample(at: 0.3), atOneTwentyHertz.sample(at: 0.3))
    }

    func testDelayedFrameSettlesImmediatelyAndCanStartAFreshTransition() {
        var motion = NotchMotion(progress: 0, at: 0)
        motion.retarget(to: 1, at: 0)
        XCTAssertEqual(motion.sample(at: 30), .init(progress: 1, velocity: 0, isSettled: true))
        let reversed = motion.retarget(to: 0, at: 30)
        XCTAssertEqual(reversed.progress, 1)
        XCTAssertEqual(reversed.velocity, 0)
        XCTAssertFalse(reversed.isSettled)
        XCTAssertEqual(motion.sample(at: 31), .init(progress: 0, velocity: 0, isSettled: true))
    }

    func testReduceMotionSnapsLatestTargetAndDiscardsOldVelocity() {
        var motion = NotchMotion(progress: 0, at: 0)
        motion.retarget(to: 1, at: 0)
        XCTAssertGreaterThan(motion.sample(at: 0.08).velocity, 0)
        let reduced = motion.retarget(to: 0, at: 0.08, reduceMotion: true)
        XCTAssertEqual(reduced, .init(progress: 0, velocity: 0, isSettled: true))
        XCTAssertEqual(motion.sample(at: 0.5), reduced)
        let resumed = motion.retarget(to: 1, at: 0.6)
        XCTAssertEqual(resumed.progress, 0)
        XCTAssertEqual(resumed.velocity, 0)
        XCTAssertFalse(resumed.isSettled)
    }

    func testEveryIntermediateFrameKeepsNotchCenterAndScreenTopOnOffsetDisplay() {
        let notch = CGRect(x: -851, y: 1350, width: 189, height: 32)
        let collapsed = CGSize(width: 277, height: 32)
        let expanded = CGSize(width: 440, height: 480)
        var motion = NotchMotion(progress: 0, at: 0)
        motion.retarget(to: 1, at: 0)
        for time in [0.0, 0.04, 0.08, 0.16, 0.24, 0.5] {
            let size = NotchMotion.size(at: motion.sample(at: time).progress, collapsed: collapsed, expanded: expanded)
            let frame = NotchGeometry.frame(anchoredTo: notch, size: size)
            XCTAssertEqual(frame.midX, notch.midX, accuracy: 0.000_001)
            XCTAssertEqual(frame.maxY, notch.maxY, accuracy: 0.000_001)
            XCTAssertGreaterThanOrEqual(frame.width, collapsed.width)
            XCTAssertLessThanOrEqual(frame.width, expanded.width)
            XCTAssertGreaterThanOrEqual(frame.height, collapsed.height)
            XCTAssertLessThanOrEqual(frame.height, expanded.height)
        }
    }
}
