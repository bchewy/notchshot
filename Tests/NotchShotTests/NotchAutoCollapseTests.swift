// SPDX-License-Identifier: MIT
import AppKit
import XCTest
@testable import NotchShot

final class NotchAutoCollapseTests: XCTestCase {
    @MainActor
    func testDefaultThreeSecondAbsenceClosesWithoutDiscardingShots() {
        let fixture = makeFixture()
        defer { fixture.store.stop() }
        let shot = makeCapture("Keep this shot")
        fixture.store.captures = [shot]
        fixture.store.selectedID = shot.id
        openAway(fixture.store)

        XCTAssertTrue(fixture.store.autoCollapseEnabled)
        XCTAssertEqual(fixture.store.autoCollapseDelay, 3)
        fixture.clock.advance(by: .milliseconds(2_999))
        XCTAssertTrue(fixture.store.isExpanded)
        fixture.clock.advance(by: .milliseconds(1))
        XCTAssertFalse(fixture.store.isExpanded)
        XCTAssertEqual(fixture.store.captures.map(\.id), [shot.id])
        XCTAssertEqual(fixture.store.selectedID, shot.id)
        XCTAssertEqual(fixture.clock.activeCount, 0)
    }

    @MainActor
    func testReturningCancelsCountdownAndLeavingGetsAFullFreshDelay() {
        let fixture = makeFixture()
        defer { fixture.store.stop() }
        openAway(fixture.store)
        fixture.clock.advance(by: .seconds(2))
        attention(fixture.store, pointerInside: true)
        fixture.clock.advance(by: .seconds(20))
        XCTAssertTrue(fixture.store.isExpanded)
        XCTAssertEqual(fixture.clock.activeCount, 0)

        attention(fixture.store)
        fixture.clock.advance(by: .milliseconds(2_999))
        XCTAssertTrue(fixture.store.isExpanded)
        fixture.clock.advance(by: .milliseconds(1))
        XCTAssertFalse(fixture.store.isExpanded)
    }

    @MainActor
    func testUnchangedAttentionSamplesDoNotKeepExtendingDeadline() {
        let fixture = makeFixture()
        defer { fixture.store.stop() }
        openAway(fixture.store)
        for _ in 0..<24 {
            fixture.clock.advance(by: .milliseconds(120))
            attention(fixture.store)
        }
        XCTAssertTrue(fixture.store.isExpanded)
        XCTAssertEqual(fixture.clock.activeCount, 1)
        fixture.clock.advance(by: .milliseconds(120))
        XCTAssertFalse(fixture.store.isExpanded)
    }

    @MainActor
    func testCancelledDeadlineCannotCloseAReopenedShelfEvenIfCallbackAlreadyQueued() {
        let fixture = makeFixture()
        defer { fixture.store.stop() }
        openAway(fixture.store)
        let oldDeadline = fixture.clock.latestID
        fixture.clock.advance(by: .seconds(2))
        fixture.store.collapse()
        fixture.store.showShelf()
        fixture.clock.invokeEvenIfCancelled(oldDeadline)
        XCTAssertTrue(fixture.store.isExpanded)
        fixture.clock.advance(by: .seconds(1))
        XCTAssertTrue(fixture.store.isExpanded, "The first opening's deadline has no authority over a reopened shelf.")
        fixture.clock.advance(by: .seconds(2))
        XCTAssertFalse(fixture.store.isExpanded)
    }

    @MainActor
    func testNativeAttentionBlockersPauseThenGrantFullDelay() {
        let blockers: [(String, (CaptureStore) -> Void)] = [
            ("pointer", { self.attention($0, pointerInside: true) }),
            ("keyboard editing or navigation", { self.attention($0, keyboardFocused: true) }),
            ("native menu", { self.attention($0, menuTracking: true) }),
            ("mouse button or external drag", { self.attention($0, mouseButtonDown: true) }),
            ("hidden export surface", { self.attention($0, surfaceVisible: false) })
        ]
        for (name, block) in blockers {
            let fixture = makeFixture()
            openAway(fixture.store)
            fixture.clock.advance(by: .seconds(2))
            block(fixture.store)
            fixture.clock.advance(by: .seconds(12))
            XCTAssertTrue(fixture.store.isExpanded, name)
            XCTAssertEqual(fixture.clock.activeCount, 0, name)
            attention(fixture.store)
            fixture.clock.advance(by: .seconds(2))
            XCTAssertTrue(fixture.store.isExpanded, name)
            fixture.clock.advance(by: .seconds(1))
            XCTAssertFalse(fixture.store.isExpanded, name)
            fixture.store.stop()
        }
    }

    @MainActor
    func testBusyOperationsAndArrivalPauseThenGrantFullDelay() {
        let operations: [(String, (CaptureStore) -> Void, (CaptureStore) -> Void)] = [
            ("capture processing", { $0.isCapturing = true }, { $0.isCapturing = false }),
            ("image import", { $0.isImporting = true }, { $0.isImporting = false }),
            ("drop target", { $0.isDropTargeted = true }, { $0.isDropTargeted = false }),
            ("shortcut recording", { $0.isRecordingShortcut = true }, { $0.isRecordingShortcut = false }),
            ("landing animation", { $0.isLandingCapture = true }, { $0.isLandingCapture = false }),
            ("capture preview", { $0.pendingCapture = self.makeCapture("Arriving") }, { $0.pendingCapture = nil }),
            ("outgoing card drag", { $0.beginCardDrag() }, { $0.endCardDrag(accepted: false) })
        ]
        for (name, begin, end) in operations {
            let fixture = makeFixture()
            openAway(fixture.store)
            fixture.clock.advance(by: .seconds(2))
            let oldDeadline = fixture.clock.latestID
            begin(fixture.store)
            fixture.clock.invokeEvenIfCancelled(oldDeadline)
            fixture.clock.advance(by: .seconds(12))
            XCTAssertTrue(fixture.store.isExpanded, name)
            XCTAssertEqual(fixture.clock.activeCount, 0, name)
            end(fixture.store)
            fixture.clock.advance(by: .milliseconds(2_999))
            XCTAssertTrue(fixture.store.isExpanded, name)
            fixture.clock.advance(by: .milliseconds(1))
            XCTAssertFalse(fixture.store.isExpanded, name)
            fixture.store.stop()
        }
    }

    @MainActor
    func testNavigationInteractionAndNewCaptureRestartCountdown() {
        let operations: [(String, (CaptureStore) -> Void)] = [
            ("settings", { $0.showCaptureSettings() }),
            ("explicit shelf reopen", { $0.showShelf() }),
            ("keyboard or pointer activity", { $0.noteNotchActivity() }),
            ("detail tab navigation", { $0.cancelCopyCollapse() }),
            ("new shot", { $0.captures.insert(self.makeCapture("New shot"), at: 0) }),
            ("selected shot", { $0.selectedID = UUID() })
        ]
        for (name, change) in operations {
            let fixture = makeFixture()
            openAway(fixture.store)
            fixture.clock.advance(by: .seconds(2))
            let oldDeadline = fixture.clock.latestID
            change(fixture.store)
            fixture.clock.invokeEvenIfCancelled(oldDeadline)
            fixture.clock.advance(by: .seconds(1))
            XCTAssertTrue(fixture.store.isExpanded, name)
            fixture.clock.advance(by: .seconds(2))
            XCTAssertFalse(fixture.store.isExpanded, name)
            fixture.store.stop()
        }
    }

    @MainActor
    func testNestedPopoverProtectionCannotBeReleasedByAnotherPopover() {
        let fixture = makeFixture()
        defer { fixture.store.stop() }
        let first = UUID(), second = UUID()
        openAway(fixture.store)
        fixture.clock.advance(by: .seconds(2))
        fixture.store.setAutoCollapseProtection(owner: first, active: true)
        fixture.store.setAutoCollapseProtection(owner: second, active: true)
        fixture.store.setAutoCollapseProtection(owner: first, active: false)
        fixture.clock.advance(by: .seconds(30))
        XCTAssertTrue(fixture.store.isExpanded)
        XCTAssertEqual(fixture.clock.activeCount, 0)
        fixture.store.setAutoCollapseProtection(owner: second, active: false)
        fixture.clock.advance(by: .milliseconds(2_999))
        XCTAssertTrue(fixture.store.isExpanded)
        fixture.clock.advance(by: .milliseconds(1))
        XCTAssertFalse(fixture.store.isExpanded)
    }

    @MainActor
    func testOptOutCancelsAnExistingDeadlineAndPersists() {
        let fixture = makeFixture()
        defer { fixture.store.stop() }
        openAway(fixture.store)
        let staleID = fixture.clock.latestID
        fixture.store.autoCollapseEnabled = false
        fixture.clock.invokeEvenIfCancelled(staleID)
        fixture.clock.advance(by: .seconds(60))
        XCTAssertTrue(fixture.store.isExpanded)
        XCTAssertEqual(fixture.clock.activeCount, 0)
        let restored = makeStore(preferences: fixture.preferences, clipboard: fixture.clipboard,
                                 clock: VirtualNotchClock())
        defer { restored.stop() }
        XCTAssertFalse(restored.autoCollapseEnabled)
        fixture.store.autoCollapseEnabled = true
        fixture.clock.advance(by: .seconds(3))
        XCTAssertFalse(fixture.store.isExpanded)
    }

    @MainActor
    func testDelayChangesPersistAndRestartInsteadOfReusingOldDeadline() {
        let fixture = makeFixture()
        defer { fixture.store.stop() }
        openAway(fixture.store)
        fixture.clock.advance(by: .seconds(2))
        let staleID = fixture.clock.latestID
        fixture.store.autoCollapseDelay = 5
        fixture.clock.invokeEvenIfCancelled(staleID)
        fixture.clock.advance(by: .seconds(4))
        XCTAssertTrue(fixture.store.isExpanded)
        let restored = makeStore(preferences: fixture.preferences, clipboard: fixture.clipboard,
                                 clock: VirtualNotchClock())
        defer { restored.stop() }
        XCTAssertEqual(restored.autoCollapseDelay, 5)
        fixture.clock.advance(by: .seconds(1))
        XCTAssertFalse(fixture.store.isExpanded)
    }

    @MainActor
    func testSupportedDelaysAndInvalidPreferenceRecovery() {
        let fixture = makeFixture()
        defer { fixture.store.stop() }
        for delay in [2.0, 3.0, 5.0, 10.0] {
            fixture.store.autoCollapseDelay = delay
            openAway(fixture.store)
            fixture.clock.advance(by: .seconds(delay) - .milliseconds(1))
            XCTAssertTrue(fixture.store.isExpanded)
            fixture.clock.advance(by: .milliseconds(1))
            XCTAssertFalse(fixture.store.isExpanded)
        }
        for invalid in [0.0, -1, 4, Double.infinity, Double.nan] {
            fixture.store.autoCollapseDelay = invalid
            XCTAssertEqual(fixture.store.autoCollapseDelay, 3)
            XCTAssertEqual(fixture.preferences.double(forKey: "autoCollapseDelay"), 3)
        }
        fixture.preferences.set(-100, forKey: "autoCollapseDelay")
        let restored = makeStore(preferences: fixture.preferences, clipboard: fixture.clipboard,
                                 clock: VirtualNotchClock())
        defer { restored.stop() }
        XCTAssertEqual(restored.autoCollapseDelay, 3)
    }

    @MainActor
    func testDeadlineResamplesAttentionBeforeClosing() {
        let fixture = makeFixture()
        defer { fixture.store.stop() }
        openAway(fixture.store)
        var resamples = 0
        fixture.store.onRefreshNotchAttention = { [weak store = fixture.store] in
            resamples += 1
            guard let store else { return }
            self.attention(store, pointerInside: true)
        }
        fixture.clock.advance(by: .seconds(3))
        XCTAssertEqual(resamples, 1)
        XCTAssertTrue(fixture.store.isExpanded, "A return between polling and the deadline must win.")
        XCTAssertEqual(fixture.clock.activeCount, 0)
        fixture.store.onRefreshNotchAttention = { resamples += 1 }
        attention(fixture.store)
        fixture.clock.advance(by: .seconds(3))
        XCTAssertEqual(resamples, 2)
        XCTAssertFalse(fixture.store.isExpanded)
    }

    @MainActor
    func testDeadlineResampleCanRestartTheTimerWithoutOldCallbackClosing() {
        let fixture = makeFixture()
        defer { fixture.store.stop() }
        openAway(fixture.store)
        fixture.store.onRefreshNotchAttention = { [weak store = fixture.store] in
            store?.onRefreshNotchAttention = nil
            store?.noteNotchActivity()
        }
        fixture.clock.advance(by: .seconds(3))
        XCTAssertTrue(fixture.store.isExpanded)
        fixture.clock.advance(by: .seconds(3))
        XCTAssertFalse(fixture.store.isExpanded)
    }

    @MainActor
    func testStopCancelsDeadlineAndLaterNativeSamplesCannotRearmIt() {
        let fixture = makeFixture()
        openAway(fixture.store)
        let staleID = fixture.clock.latestID
        fixture.store.stop()
        fixture.clock.invokeEvenIfCancelled(staleID)
        attention(fixture.store)
        fixture.store.noteNotchActivity()
        fixture.clock.advance(by: .seconds(30))
        XCTAssertTrue(fixture.store.isExpanded)
        XCTAssertEqual(fixture.clock.activeCount, 0)
    }

    @MainActor
    func testCollapsedOrNeverPresentedStoreDoesNotStartIdleWork() {
        let fixture = makeFixture()
        defer { fixture.store.stop() }
        fixture.store.isExpanded = true
        fixture.clock.advance(by: .seconds(30))
        XCTAssertTrue(fixture.store.isExpanded)
        XCTAssertEqual(fixture.clock.activeCount, 0)
        fixture.store.isExpanded = false
        attention(fixture.store)
        fixture.store.noteNotchActivity()
        fixture.clock.advance(by: .seconds(30))
        XCTAssertFalse(fixture.store.isExpanded)
        XCTAssertEqual(fixture.clock.activeCount, 0)
    }

    @MainActor
    func testPointerPresenceDoesNotCancelSuccessfulCopyCollapse() {
        let fixture = makeFixture()
        defer { fixture.store.stop() }
        let shot = makeCapture("Copied")
        fixture.store.captures = [shot]
        fixture.store.isExpanded = true
        attention(fixture.store, pointerInside: true)
        XCTAssertEqual(fixture.clock.activeCount, 0, "Pointer presence prevents an idle deadline.")
        XCTAssertTrue(fixture.store.copyCapture(shot.id))
        attention(fixture.store, pointerInside: true)
        fixture.store.noteNotchActivity() // Native mouseUp/keyUp from the same copy gesture.
        XCTAssertEqual(fixture.clock.activeCount, 1, "The independent copy deadline remains scheduled.")
        XCTAssertEqual(fixture.clipboard.string(forType: .string), shot.clipboardText)
        fixture.clock.advance(by: .milliseconds(19))
        XCTAssertTrue(fixture.store.isExpanded, "Copy feedback receives its full delay.")
        fixture.clock.advance(by: .milliseconds(1))
        XCTAssertFalse(fixture.store.isExpanded, "The manual copy feedback delay remains independent of idle attention.")
        XCTAssertEqual(fixture.clock.activeCount, 0)
        XCTAssertEqual(fixture.store.captures.map(\.id), [shot.id])
    }

    @MainActor
    private func attention(_ store: CaptureStore, pointerInside: Bool = false,
                           keyboardFocused: Bool = false, menuTracking: Bool = false,
                           mouseButtonDown: Bool = false, surfaceVisible: Bool = true) {
        store.updateNotchAttention(pointerInside: pointerInside, keyboardFocused: keyboardFocused,
                                   menuTracking: menuTracking, mouseButtonDown: mouseButtonDown,
                                   surfaceVisible: surfaceVisible)
    }

    @MainActor
    private func openAway(_ store: CaptureStore) {
        store.isExpanded = true
        attention(store)
    }

    @MainActor
    private func makeFixture() -> (store: CaptureStore, clock: VirtualNotchClock,
                                   preferences: UserDefaults, clipboard: NSPasteboard) {
        let suite = "NotchShotAutoCollapseTests-\(UUID())"
        let preferences = UserDefaults(suiteName: suite)!
        let clipboard = NSPasteboard(name: .init(suite))
        let clock = VirtualNotchClock()
        addTeardownBlock {
            preferences.removePersistentDomain(forName: suite)
            clipboard.releaseGlobally()
        }
        return (makeStore(preferences: preferences, clipboard: clipboard, clock: clock),
                clock, preferences, clipboard)
    }

    @MainActor
    private func makeStore(preferences: UserDefaults, clipboard: NSPasteboard,
                           clock: VirtualNotchClock) -> CaptureStore {
        CaptureStore(preferences: preferences, captureSound: SilentIdleCaptureSound(), clipboard: clipboard,
                     copySound: SilentIdleCopySound(), copyCollapseDelay: .milliseconds(20),
                     copyCollapseSchedule: clock.schedule,
                     idleSchedule: clock.schedule)
    }

    private func makeCapture(_ name: String) -> CaptureResult {
        CaptureResult(appName: name, bundleIdentifier: "com.example.notch-idle-tests", windowTitle: name,
                      accessibilityText: "Test context for \(name)")
    }
}

/// Advances logical time only. Retaining cancelled callbacks lets tests reproduce
/// the race where a deadline has already been queued when attention changes.
@MainActor
private final class VirtualNotchClock {
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
private final class SilentIdleCaptureSound: CaptureSoundPlaying { func play() {} }
@MainActor
private final class SilentIdleCopySound: CopySoundPlaying { func play() {} }
