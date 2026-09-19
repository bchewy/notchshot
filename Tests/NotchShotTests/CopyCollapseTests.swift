// SPDX-License-Identifier: MIT
import AppKit
import XCTest
@testable import NotchShot

final class CopyCollapseTests: XCTestCase {
    @MainActor
    func testEveryManualCopyWritesItsContentBeforeDelayedCollapse() async throws {
        let fixture = makeFixture()
        let store = fixture.store
        defer { store.stop() }
        let capture = try makeImageCapture("Manual copy")
        store.captures = [capture]
        store.selectedID = capture.id
        let routes: [(String, () -> Void)] = [
            ("shot", { XCTAssertTrue(store.copyCapture(capture.id)) }),
            ("all", { store.copyContext() }),
            ("image", { store.copyImage() }),
            ("text", { store.copyText() }),
            ("tree", { store.copyTree() })
        ]

        for (name, copy) in routes {
            store.page = .detail
            store.isExpanded = true
            copy()
            XCTAssertTrue(store.isExpanded, "\(name) needs time for its copied feedback before closing.")
            switch name {
            case "image": XCTAssertEqual(fixture.clipboard.data(forType: .png), capture.pngData)
            case "text": XCTAssertEqual(fixture.clipboard.string(forType: .string), "Accessibility text\n\(capture.accessibilityText)")
            case "tree": XCTAssertEqual(fixture.clipboard.string(forType: .string), capture.treeText)
            default:
                XCTAssertEqual(fixture.clipboard.string(forType: .string), capture.clipboardText)
                XCTAssertEqual(fixture.clipboard.data(forType: .png), capture.pngData)
            }
            try await settle(untilCollapsed: store)
            XCTAssertFalse(store.isExpanded, "Successful \(name) copy should close the notch.")
            XCTAssertEqual(store.captures.map(\.id), [capture.id], "Collapsing must retain the saved shot.")
        }
        XCTAssertEqual(fixture.sound.playCount, routes.count)
    }

    @MainActor
    func testHoveredCopyUsesExactShotWithoutChangingSelectionBeforeClosing() async throws {
        let fixture = makeFixture()
        let store = fixture.store
        defer { store.stop() }
        let selected = makeCapture("Selected")
        let hovered = try makeImageCapture("Hovered")
        store.captures = [selected, hovered]
        store.selectedID = selected.id
        store.page = .shelf
        store.isExpanded = true

        XCTAssertTrue(store.copyCapture(hovered.id))
        XCTAssertEqual(fixture.clipboard.string(forType: .string), hovered.clipboardText)
        XCTAssertEqual(fixture.clipboard.data(forType: .png), hovered.pngData)
        XCTAssertNotNil(fixture.clipboard.data(forType: .tiff))
        XCTAssertEqual(store.selectedID, selected.id)
        XCTAssertEqual(store.page, .shelf)
        XCTAssertTrue(store.isExpanded)
        try await settle(untilCollapsed: store)
        XCTAssertFalse(store.isExpanded)
        XCTAssertEqual(store.selectedID, selected.id)
    }

    @MainActor
    func testOptOutPersistsAndCopyMuteDoesNotDisableCollapse() async throws {
        let fixture = makeFixture()
        let store = fixture.store
        defer { store.stop() }
        let capture = makeCapture("Preferences")
        store.captures = [capture]
        store.isExpanded = true
        XCTAssertTrue(store.collapseAfterCopy)
        store.collapseAfterCopy = false
        XCTAssertTrue(store.copyCapture(capture.id))
        try await settle()
        XCTAssertTrue(store.isExpanded)
        XCTAssertEqual(fixture.clipboard.string(forType: .string), capture.clipboardText)

        let restored = CaptureStore(preferences: fixture.preferences,
                                    captureSound: SilentCollapseCaptureSound(),
                                    clipboard: fixture.clipboard,
                                    copySound: CollapseCopySoundSpy(),
                                    copyCollapseDelay: .milliseconds(20))
        defer { restored.stop() }
        XCTAssertFalse(restored.collapseAfterCopy)
        store.collapseAfterCopy = true
        store.copySoundEnabled = false
        let previousPlays = fixture.sound.playCount
        XCTAssertTrue(store.copyCapture(capture.id))
        try await settle(untilCollapsed: store)
        XCTAssertFalse(store.isExpanded)
        XCTAssertEqual(fixture.sound.playCount, previousPlays)
        XCTAssertTrue(fixture.preferences.bool(forKey: "collapseAfterCopy"))
    }

    @MainActor
    func testMissingContentAndStaleHoverLeaveClipboardAndShelfAlone() async throws {
        let fixture = makeFixture()
        let store = fixture.store
        defer { store.stop() }
        store.isExpanded = true
        fixture.clipboard.setString("Keep this", forType: .string)
        let changeCount = fixture.clipboard.changeCount
        XCTAssertFalse(store.copyCapture(UUID()))
        store.copyContext()
        store.copyImage()
        store.copyText()
        store.copyTree()
        let empty = CaptureResult(appName: "Empty", bundleIdentifier: "com.example.copy-collapse", windowTitle: "Empty")
        store.captures = [empty]
        store.selectedID = empty.id
        store.copyImage()
        store.copyText()
        store.copyTree()
        try await settle()
        XCTAssertTrue(store.isExpanded)
        XCTAssertEqual(fixture.clipboard.changeCount, changeCount)
        XCTAssertEqual(fixture.clipboard.string(forType: .string), "Keep this")
        XCTAssertEqual(fixture.sound.playCount, 0)
    }

    @MainActor
    func testAutomaticCopyKeepsShelfOpenAfterCollection() async throws {
        let fixture = makeFixture()
        let store = fixture.store
        defer { store.stop() }
        let capture = makeCapture("Automatic arrival")
        store.autoCopyCapture = true
        store.openShelfAfterCapture = true
        store.pendingCapture = capture
        store.acceptPendingCapture()
        XCTAssertEqual(fixture.clipboard.string(forType: .string), capture.clipboardText)
        XCTAssertEqual(store.captures.map(\.id), [capture.id])
        XCTAssertTrue(store.isExpanded)
        try await settle()
        XCTAssertTrue(store.isExpanded, "Automatic clipboard copying must respect the user's open-on-arrival choice.")
        XCTAssertEqual(store.page, .shelf)
    }

    @MainActor
    func testNavigationAndHistoryEditsCancelAnEarlierCopyClose() async throws {
        let changes: [(String, (CaptureStore, CaptureResult) -> Void)] = [
            ("settings", { store, _ in store.showCaptureSettings() }),
            ("detail", { store, shot in store.showCaptureDetail(shot.id) }),
            ("explicit shelf", { store, _ in store.showShelf() }),
            ("selection", { store, shot in store.selectedID = shot.id }),
            ("new shot", { store, _ in store.captures.insert(self.makeCapture("Incoming"), at: 0) }),
            ("removed shot", { store, shot in store.removeCapture(shot.id) }),
            ("edited shot", { store, _ in store.captures[0].accessibilityText = "New content" }),
            ("clear history", { store, _ in store.clearHistory() })
        ]
        for (name, change) in changes {
            let fixture = makeFixture()
            let store = fixture.store
            let copied = makeCapture("Copied")
            let other = makeCapture("Other")
            store.captures = [copied, other]
            store.selectedID = copied.id
            store.isExpanded = true
            XCTAssertTrue(store.copyCapture(copied.id))
            change(store, other)
            try await settle()
            XCTAssertTrue(store.isExpanded, "\(name) must take priority over an earlier copy.")
            store.stop()
        }
    }

    @MainActor
    func testCloseThenReopenCancelsStaleCopyDeadline() {
        let clock = VirtualCopyCollapseClock()
        let fixture = makeFixture(schedule: clock.schedule)
        let store = fixture.store
        defer { store.stop() }
        let capture = makeCapture("Reopened")
        store.captures = [capture]
        store.isExpanded = true
        XCTAssertTrue(store.copyCapture(capture.id))
        let oldDeadline = clock.latestID
        store.collapse()
        store.showShelf()
        XCTAssertEqual(clock.activeCount, 0)
        clock.invokeEvenIfCancelled(oldDeadline)
        clock.advance(by: .seconds(1))
        XCTAssertTrue(store.isExpanded, "An old copy must not close a shelf the user deliberately reopened.")
    }

    @MainActor
    func testNewActivityCancelsCopyCloseAndBusyCopiesDoNotScheduleOne() async throws {
        let activities: [(String, (CaptureStore) -> Void, (CaptureStore) -> Void)] = [
            ("capture", { $0.isCapturing = true }, { $0.isCapturing = false }),
            ("import", { $0.isImporting = true }, { $0.isImporting = false }),
            ("drop", { $0.isDropTargeted = true }, { $0.isDropTargeted = false }),
            ("shortcut recording", { $0.isRecordingShortcut = true }, { $0.isRecordingShortcut = false }),
            ("landing", { $0.isLandingCapture = true }, { $0.isLandingCapture = false }),
            ("pending capture", { $0.pendingCapture = self.makeCapture("Pending") }, { $0.pendingCapture = nil }),
            ("card drag", { $0.beginCardDrag() }, { $0.endCardDrag(accepted: false) })
        ]
        for (name, begin, end) in activities {
            for busyBeforeCopy in [false, true] {
                let fixture = makeFixture()
                let store = fixture.store
                let capture = makeCapture("Activity")
                store.captures = [capture]
                store.isExpanded = true
                if busyBeforeCopy { begin(store) }
                XCTAssertTrue(store.copyCapture(capture.id))
                if !busyBeforeCopy { begin(store) }
                end(store)
                try await settle()
                XCTAssertTrue(store.isExpanded, "\(name), active before copy: \(busyBeforeCopy), must prevent a stale close.")
                XCTAssertEqual(fixture.clipboard.string(forType: .string), capture.clipboardText)
                store.stop()
            }
        }
    }

    @MainActor
    func testSettingsAndCollapsedCopiesDoNotLeaveAClosingDeadline() async throws {
        for page in [NotchPage.shelf, .settings] {
            let fixture = makeFixture()
            let store = fixture.store
            let capture = makeCapture("Hidden or settings")
            store.captures = [capture]
            store.page = page
            store.isExpanded = page == .settings
            XCTAssertTrue(store.copyCapture(capture.id))
            try await settle()
            XCTAssertEqual(store.isExpanded, page == .settings)
            store.showShelf()
            try await settle()
            XCTAssertTrue(store.isExpanded)
            store.stop()
        }
    }

    @MainActor
    func testTurningSettingOffOrStoppingCancelsPendingClose() {
        for stop in [false, true] {
            let clock = VirtualCopyCollapseClock()
            let fixture = makeFixture(schedule: clock.schedule)
            let store = fixture.store
            let capture = makeCapture("Cancelled")
            store.captures = [capture]
            store.isExpanded = true
            XCTAssertTrue(store.copyCapture(capture.id))
            let oldDeadline = clock.latestID
            if stop { store.stop() } else { store.collapseAfterCopy = false }
            XCTAssertEqual(clock.activeCount, 0)
            clock.invokeEvenIfCancelled(oldDeadline)
            clock.advance(by: .seconds(1))
            XCTAssertTrue(store.isExpanded)
            store.stop()
        }
    }

    @MainActor
    func testRapidSuccessfulCopiesRestartTheFeedbackDelay() {
        let clock = VirtualCopyCollapseClock()
        let fixture = makeFixture(delay: .milliseconds(160), schedule: clock.schedule)
        let store = fixture.store
        defer { store.stop() }
        let first = makeCapture("First")
        let second = makeCapture("Second")
        store.captures = [first, second]
        store.isExpanded = true
        XCTAssertTrue(store.copyCapture(first.id))
        let firstDeadline = clock.latestID
        clock.advance(by: .milliseconds(90))
        XCTAssertTrue(store.isExpanded)
        XCTAssertTrue(store.copyCapture(second.id))
        XCTAssertEqual(clock.activeCount, 1)
        clock.advance(by: .milliseconds(70))
        clock.invokeEvenIfCancelled(firstDeadline)
        XCTAssertTrue(store.isExpanded, "The first deadline must not cut off feedback for the second copy.")
        XCTAssertEqual(fixture.clipboard.string(forType: .string), second.clipboardText)
        clock.advance(by: .milliseconds(89))
        XCTAssertTrue(store.isExpanded, "The second copy gets its entire feedback delay.")
        clock.advance(by: .milliseconds(1))
        XCTAssertFalse(store.isExpanded)
        XCTAssertEqual(clock.activeCount, 0)
        XCTAssertEqual(fixture.sound.playCount, 2)
    }

    @MainActor
    func testSuccessfulCopyAnimatesHiddenNativePanelBackToCompactBounds() async throws {
        _ = NSApplication.shared
        guard NotchGeometry.preferredScreen != nil else {
            throw XCTSkip("This native integration test requires WindowServer display access.")
        }
        let previousWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
        let fixture = makeFixture()
        let store = fixture.store
        let capture = makeCapture("Native motion")
        store.captures = [capture]
        store.isExpanded = true
        let controller = NotchPanelController(store: store)
        defer { store.stop() }
        let window = try XCTUnwrap(NSApp.windows.first {
            !previousWindows.contains(ObjectIdentifier($0)) && $0.title == "NotchShot"
        })
        defer { window.close() }
        let expandedFrame = window.frame
        XCTAssertEqual(controller.presentation.progress, 1)
        XCTAssertFalse(window.isVisible, "The test must never show a window.")

        XCTAssertTrue(store.copyCapture(capture.id))
        XCTAssertTrue(store.isExpanded)
        XCTAssertEqual(fixture.clipboard.string(forType: .string), capture.clipboardText)
        try await waitForMotion {
            controller.presentation.progress < 1 && window.frame.height < expandedFrame.height
        }
        XCTAssertEqual(window.frame.size, controller.presentation.size)
        XCTAssertEqual(window.frame.midX, expandedFrame.midX, accuracy: 0.5)
        XCTAssertEqual(window.frame.maxY, expandedFrame.maxY, accuracy: 0.5)
        try await waitForMotion { !controller.isAnimating && controller.presentation.progress == 0 }
        XCTAssertFalse(store.isExpanded)
        XCTAssertEqual(window.frame.height, max(store.notchHeight, 32), accuracy: 0.5)
        XCTAssertEqual(window.frame.width, store.notchWidth + 36, accuracy: 0.5)
        XCTAssertFalse(window.isVisible)
    }

    @MainActor
    private func waitForMotion(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw NSError(domain: "CopyCollapseTests", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Copy did not drive native panel motion within one second."])
    }

    @MainActor
    private func makeFixture(delay: Duration = .milliseconds(20),
                             schedule: @escaping NotchIdleTimer.Schedule = NotchIdleTimer.scheduleTask)
        -> (store: CaptureStore, preferences: UserDefaults, clipboard: NSPasteboard, sound: CollapseCopySoundSpy) {
        let suite = "NotchShotCopyCollapseTests-\(UUID())"
        let preferences = UserDefaults(suiteName: suite)!
        let clipboard = NSPasteboard(name: .init(suite))
        let sound = CollapseCopySoundSpy()
        addTeardownBlock {
            preferences.removePersistentDomain(forName: suite)
            clipboard.releaseGlobally()
        }
        let store = CaptureStore(preferences: preferences,
                                 landingPreviewDelay: .milliseconds(1),
                                 shelfPreparationDelay: .milliseconds(1),
                                 captureSound: SilentCollapseCaptureSound(),
                                 clipboard: clipboard,
                                 copySound: sound,
                                 copyCollapseDelay: delay,
                                 copyCollapseSchedule: schedule)
        return (store, preferences, clipboard, sound)
    }

    private func makeCapture(_ name: String) -> CaptureResult {
        CaptureResult(appName: name, bundleIdentifier: "com.example.copy-collapse", windowTitle: name,
                      axTree: [AXNode(id: 1, role: "AXButton", roleDescription: "button", title: "Submit")],
                      accessibilityText: "Accessible content for \(name)")
    }

    @MainActor
    private func makeImageCapture(_ name: String) throws -> CaptureResult {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for x in 0..<2 {
            for y in 0..<2 { bitmap.setColor(.systemMint, atX: x, y: y) }
        }
        var capture = makeCapture(name)
        capture.pngData = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        return capture
    }

    /// Long enough for a 20 ms collapse to have fired when one is expected not to.
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(70))
    }

    /// A collapse that is expected to happen is awaited, not assumed to land
    /// inside a fixed sleep; the assertion that follows still fails on timeout.
    @MainActor
    private func settle(untilCollapsed store: CaptureStore) async throws {
        for _ in 0..<200 {
            if !store.isExpanded { return }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

/// Keep cancelled callbacks so a test can also model a deadline already queued
/// on the main actor when a second copy or a user interaction cancels it.
@MainActor
private final class VirtualCopyCollapseClock {
    private struct Job {
        let due: Duration
        let action: @MainActor () -> Void
        var cancelled = false
        var delivered = false
    }
    private var now = Duration.zero
    private var jobs: [Int: Job] = [:]
    private(set) var latestID = 0
    var activeCount: Int { jobs.values.filter { !$0.cancelled && !$0.delivered }.count }

    func schedule(_ delay: Duration, action: @escaping @MainActor () -> Void) -> (() -> Void) {
        latestID += 1
        let id = latestID
        jobs[id] = Job(due: now + delay, action: action)
        return { [weak self] in self?.jobs[id]?.cancelled = true }
    }

    func advance(by interval: Duration) {
        let target = now + interval
        while let next = jobs.filter({ !$0.value.cancelled && !$0.value.delivered && $0.value.due <= target })
            .min(by: { $0.value.due == $1.value.due ? $0.key < $1.key : $0.value.due < $1.value.due }) {
            now = next.value.due
            jobs[next.key]?.delivered = true
            next.value.action()
        }
        now = target
    }

    func invokeEvenIfCancelled(_ id: Int) { jobs[id]?.action() }
}

@MainActor
private final class SilentCollapseCaptureSound: CaptureSoundPlaying {
    func play() {}
}

@MainActor
private final class CollapseCopySoundSpy: CopySoundPlaying {
    var playCount = 0
    func play() { playCount += 1 }
}
