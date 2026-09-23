// SPDX-License-Identifier: MIT
import AppKit
import Foundation
import XCTest
@testable import NotchShot

@MainActor
final class UpdateControllerTests: XCTestCase {
    func testChannelDefaultsToTheBuildsOwnAndChoicesPersist() {
        let (preferences, _) = isolatedStoreDependencies()
        let nightly = makeController(preferences: preferences, buildChannel: .nightly).controller
        XCTAssertEqual(nightly.channel, .nightly)
        XCTAssertTrue(nightly.automaticUpdates)
        XCTAssertEqual(makeController(preferences: isolatedStoreDependencies("stable").preferences).controller.channel, .stable)

        nightly.channel = .stable
        nightly.automaticUpdates = false
        let restored = makeController(preferences: preferences, buildChannel: .nightly).controller
        XCTAssertEqual(restored.channel, .stable)
        XCTAssertFalse(restored.automaticUpdates)

        preferences.set("beta", forKey: "updateChannel")
        preferences.set("yes", forKey: "automaticUpdates")
        let malformed = makeController(preferences: preferences, buildChannel: .nightly).controller
        XCTAssertEqual(malformed.channel, .nightly)
        XCTAssertTrue(malformed.automaticUpdates)
    }

    func testUnavailableBuildNeverSchedulesOrChecks() {
        let (preferences, _) = isolatedStoreDependencies()
        let clock = VirtualUpdateClock()
        let controller = UpdateController(preferences: preferences, installation: nil, service: nil,
                                          unavailableReason: "Local builds don’t update themselves.", schedule: clock.schedule)
        controller.start()
        XCTAssertEqual(controller.phase, .unavailable("Local builds don’t update themselves."))
        XCTAssertFalse(controller.isAvailable)
        XCTAssertEqual(clock.activeCount, 0)
        XCTAssertNil(controller.checkNow())
        controller.channel = .nightly
        XCTAssertEqual(controller.phase, .unavailable("Local builds don’t update themselves."))
    }

    func testChecksShortlyAfterLaunchThenEverySixHours() async {
        let fixture = makeController()
        let (controller, service, clock) = (fixture.controller, fixture.service, fixture.clock)
        controller.start()
        clock.advance(by: .seconds(14))
        XCTAssertEqual(service.checkedChannels, [])
        clock.advance(by: .seconds(1))
        await controller.activeCheck?.value
        XCTAssertEqual(service.checkedChannels, [.stable])
        XCTAssertEqual(controller.phase, .upToDate)
        XCTAssertEqual(controller.lastChecked, fixture.now)
        XCTAssertEqual(fixture.preferences.object(forKey: "lastUpdateCheck") as? Date, fixture.now)

        clock.advance(by: .seconds(6 * 60 * 60 - 1))
        XCTAssertEqual(service.checkedChannels.count, 1)
        clock.advance(by: .seconds(1))
        await controller.activeCheck?.value
        XCTAssertEqual(service.checkedChannels.count, 2)
    }

    func testRelaunchesDoNotShortenTheCheckInterval() async {
        let (preferences, _) = isolatedStoreDependencies()
        let now = Date(timeIntervalSince1970: 1_000_000)
        preferences.set(now.addingTimeInterval(-5 * 60 * 60), forKey: "lastUpdateCheck")
        let fixture = makeController(preferences: preferences, now: now)
        fixture.controller.start()
        fixture.clock.advance(by: .seconds(60 * 60 - 1))
        XCTAssertEqual(fixture.service.checkedChannels, [])
        fixture.clock.advance(by: .seconds(1))
        await fixture.controller.activeCheck?.value
        XCTAssertEqual(fixture.service.checkedChannels, [.stable])
    }

    func testAutomaticUpdateInstallsAndRelaunchesOnlyOnceNothingWouldBeLost() async {
        let fixture = makeController()
        let (controller, service, clock) = (fixture.controller, fixture.service, fixture.clock)
        var idle = false
        var relaunches = 0
        controller.canInstallNow = { idle }
        controller.onRelaunch = { relaunches += 1 }
        service.latest = .success(offer(build: 41))
        controller.start()
        clock.advance(by: .seconds(15))
        await controller.activeCheck?.value

        XCTAssertEqual(controller.phase, .ready(offer(build: 41)))
        XCTAssertEqual(service.stagedOffers, [offer(build: 41)])
        XCTAssertEqual(service.installed, [])
        clock.advance(by: .seconds(2 * 60))
        XCTAssertEqual(service.installed, [], "Shots on the shelf keep the update waiting.")

        idle = true
        clock.advance(by: .seconds(2 * 60))
        XCTAssertEqual(service.installed.map(\.offer.build), [41])
        XCTAssertEqual(relaunches, 1)
        XCTAssertEqual(controller.phase, .installed(offer(build: 41)))
        XCTAssertNil(controller.checkNow(), "The installed bundle is already newer than this process.")
    }

    func testQuitInstallsAWaitingAutomaticUpdateWithoutRelaunching() async {
        let fixture = makeController()
        var relaunches = 0
        fixture.controller.onRelaunch = { relaunches += 1 }
        fixture.service.latest = .success(offer(build: 41))
        fixture.controller.start()
        await fixture.controller.checkNow()?.value
        XCTAssertEqual(fixture.controller.phase, .ready(offer(build: 41)))

        fixture.controller.installPendingUpdate()
        fixture.controller.installPendingUpdate()
        XCTAssertEqual(fixture.service.installed.map(\.offer.build), [41])
        XCTAssertEqual(relaunches, 0)
        XCTAssertEqual(fixture.controller.phase, .installed(offer(build: 41)))
    }

    func testManualModeChecksOnlyWhenAskedAndInstallsOnlyOnRestart() async {
        let fixture = makeController()
        let (controller, service, clock) = (fixture.controller, fixture.service, fixture.clock)
        controller.automaticUpdates = false
        controller.canInstallNow = { true }
        var relaunches = 0
        controller.onRelaunch = { relaunches += 1 }
        service.latest = .success(offer(build: 41))
        controller.start()
        clock.advance(by: .seconds(24 * 60 * 60))
        XCTAssertEqual(service.checkedChannels, [], "No background network when automatic updates are off.")

        await controller.checkNow()?.value
        XCTAssertEqual(controller.phase, .ready(offer(build: 41)))
        clock.advance(by: .seconds(60 * 60))
        controller.installPendingUpdate()
        XCTAssertEqual(service.installed, [], "Quitting does not install an update the user has not chosen.")
        XCTAssertEqual(clock.activeCount, 0)

        controller.installAndRelaunch()
        XCTAssertEqual(service.installed.map(\.offer.build), [41])
        XCTAssertEqual(relaunches, 1)
    }

    func testNewerReleaseReplacesAndWithdrawnReleaseDiscardsTheWaitingUpdate() async {
        let fixture = makeController()
        let (controller, service) = (fixture.controller, fixture.service)
        service.latest = .success(offer(build: 41))
        await controller.checkNow()?.value
        await controller.checkNow()?.value
        XCTAssertEqual(service.stagedOffers.map(\.build), [41], "An unchanged release is not downloaded again.")

        service.latest = .success(offer(build: 42))
        await controller.checkNow()?.value
        XCTAssertEqual(service.stagedOffers.map(\.build), [41, 42])
        XCTAssertEqual(service.discarded.map(\.offer.build), [41])
        XCTAssertEqual(controller.phase, .ready(offer(build: 42)))

        service.latest = .success(nil)
        await controller.checkNow()?.value
        XCTAssertEqual(service.discarded.map(\.offer.build), [41, 42])
        XCTAssertEqual(controller.phase, .upToDate)
        controller.installPendingUpdate()
        XCTAssertEqual(service.installed, [])
    }

    func testSwitchingToStableDropsAWaitingNightlyAndChecksAgain() async {
        let fixture = makeController(buildChannel: .nightly)
        let (controller, service) = (fixture.controller, fixture.service)
        controller.start()
        service.latest = .success(offer(build: 41, channel: .nightly))
        await controller.checkNow()?.value
        XCTAssertEqual(controller.phase, .ready(offer(build: 41, channel: .nightly)))

        service.latest = .success(nil)
        controller.channel = .stable
        XCTAssertEqual(service.discarded.map(\.offer.build), [41])
        await controller.activeCheck?.value
        XCTAssertEqual(service.checkedChannels, [.nightly, .stable])
        XCTAssertEqual(controller.phase, .upToDate)
    }

    func testChannelSwitchAbandonsACheckInFlight() async {
        let fixture = makeController(buildChannel: .nightly)
        let (controller, service) = (fixture.controller, fixture.service)
        controller.automaticUpdates = false
        service.holdChecks = true
        service.latest = .success(offer(build: 41, channel: .nightly))
        let abandoned = controller.checkNow()
        await service.waitForHeldCheck()

        controller.channel = .stable
        XCTAssertEqual(controller.phase, .idle)
        service.releaseHeldChecks()
        await abandoned?.value
        XCTAssertEqual(service.stagedOffers, [], "A nightly found before switching is never staged.")
        XCTAssertEqual(controller.phase, .idle)
    }

    func testFailuresRetrySoonerAndAreAnnouncedOnlyWhenRequested() async {
        let fixture = makeController()
        let (controller, service, clock) = (fixture.controller, fixture.service, fixture.clock)
        var notices: [String] = []
        controller.onNotice = { _, title, message in notices.append("\(title): \(message)") }
        service.latest = .failure(UpdateError.network("GitHub returned HTTP 502."))
        controller.start()
        clock.advance(by: .seconds(15))
        await controller.activeCheck?.value
        XCTAssertEqual(controller.phase, .failed("GitHub returned HTTP 502."))
        XCTAssertEqual(notices, [])

        clock.advance(by: .seconds(60 * 60))
        await controller.activeCheck?.value
        XCTAssertEqual(service.checkedChannels.count, 2, "A failed check retries after an hour.")

        await controller.checkNow()?.value
        XCTAssertEqual(notices, ["Update check failed: GitHub returned HTTP 502."])
    }

    func testFailedInstallIsReportedDiscardedAndDoesNotRelaunch() async {
        let fixture = makeController()
        var relaunches = 0
        var notices: [String] = []
        fixture.controller.onRelaunch = { relaunches += 1 }
        fixture.controller.onNotice = { _, title, _ in notices.append(title) }
        fixture.service.latest = .success(offer(build: 41))
        fixture.service.installError = UpdateError.installation("NotchShot couldn’t replace itself: Permission denied.")
        await fixture.controller.checkNow()?.value
        fixture.controller.installAndRelaunch()

        XCTAssertEqual(fixture.controller.phase, .failed("NotchShot couldn’t replace itself: Permission denied."))
        XCTAssertEqual(fixture.service.discarded.map(\.offer.build), [41])
        XCTAssertEqual(relaunches, 0)
        XCTAssertEqual(notices, ["Update ready", "Update not installed"])
    }

    func testFailedAutomaticInstallKeepsCheckingLater() async {
        let fixture = makeController()
        let (controller, service, clock) = (fixture.controller, fixture.service, fixture.clock)
        controller.canInstallNow = { true }
        service.latest = .success(offer(build: 41))
        service.installError = UpdateError.installation("NotchShot couldn’t replace itself: Resource busy.")
        controller.start()
        clock.advance(by: .seconds(15))
        await controller.activeCheck?.value
        XCTAssertEqual(controller.phase, .failed("NotchShot couldn’t replace itself: Resource busy."))

        service.installError = nil
        clock.advance(by: .seconds(60 * 60))
        await controller.activeCheck?.value
        XCTAssertEqual(service.checkedChannels.count, 2, "Automatic updates continue after a failed install.")
        XCTAssertEqual(service.installed.map(\.offer.build), [41])
    }

    func testFailedDownloadKeepsTheVerifiedUpdateWaiting() async {
        let fixture = makeController()
        let (controller, service) = (fixture.controller, fixture.service)
        var notices: [String] = []
        controller.onNotice = { _, title, _ in notices.append(title) }
        service.latest = .success(offer(build: 41))
        await controller.checkNow()?.value

        service.latest = .success(offer(build: 42))
        service.stageError = UpdateError.network("The update download was incomplete.")
        await controller.checkNow()?.value
        XCTAssertEqual(service.discarded, [], "Build 41 is kept until a replacement is verified.")
        XCTAssertEqual(controller.phase, .ready(offer(build: 41)))
        XCTAssertEqual(notices, ["Update ready", "Update check failed"])

        controller.installPendingUpdate()
        XCTAssertEqual(service.installed.map(\.offer.build), [41])
    }

    func testTurningAutomaticUpdatesOffStopsABackgroundCheckButNotARequestedOne() async {
        let fixture = makeController()
        let (controller, service, clock) = (fixture.controller, fixture.service, fixture.clock)
        service.holdChecks = true
        service.latest = .success(offer(build: 41))
        controller.start()
        clock.advance(by: .seconds(15))
        let background = controller.activeCheck
        await service.waitForHeldCheck()

        controller.automaticUpdates = false
        XCTAssertEqual(controller.phase, .idle)
        service.releaseHeldChecks()
        await background?.value
        XCTAssertEqual(service.stagedOffers, [], "Nothing downloads after automatic updates are turned off.")
        XCTAssertEqual(clock.activeCount, 0)

        service.holdChecks = true
        let requested = controller.checkNow()
        await service.waitForHeldCheck()
        controller.automaticUpdates = true
        controller.automaticUpdates = false
        service.releaseHeldChecks()
        await requested?.value
        XCTAssertEqual(controller.phase, .ready(offer(build: 41)), "A check the user asked for still finishes.")
    }

    func testStoreAllowsAnUnnoticedRelaunchOnlyWithAnEmptyClosedIdleShelf() {
        let (preferences, clipboard) = isolatedStoreDependencies()
        let paste = PendingPasteStub()
        let store = CaptureStore(preferences: preferences, clipboard: clipboard, assistedPaste: paste)
        defer { store.stop() }
        XCTAssertTrue(store.canRelaunchUnnoticed)

        store.captures = [CaptureResult(appName: "Notes", bundleIdentifier: "com.example.update-test", windowTitle: "Draft")]
        XCTAssertFalse(store.canRelaunchUnnoticed, "Shots in memory would be lost.")
        store.captures = []
        store.isExpanded = true
        XCTAssertFalse(store.canRelaunchUnnoticed, "The notch is in use.")
        store.isExpanded = false
        store.isCapturing = true
        XCTAssertFalse(store.canRelaunchUnnoticed, "A capture is in flight.")
        store.isCapturing = false
        paste.hasPendingPaste = true
        XCTAssertFalse(store.canRelaunchUnnoticed, "The next ⌘V is still assisted.")
        paste.hasPendingPaste = false
        XCTAssertTrue(store.canRelaunchUnnoticed)
    }

    // MARK: - Fixtures

    private struct Fixture {
        let controller: UpdateController
        let service: FakeUpdateService
        let clock: VirtualUpdateClock
        let preferences: UserDefaults
        let now: Date
    }

    private func makeController(preferences: UserDefaults? = nil, buildChannel: UpdateChannel = .stable,
                                now: Date = Date(timeIntervalSince1970: 1_000_000)) -> Fixture {
        let preferences = preferences ?? isolatedStoreDependencies().preferences
        let service = FakeUpdateService()
        let clock = VirtualUpdateClock()
        let installation = UpdateInstallation(bundleURL: URL(fileURLWithPath: "/Applications/NotchShot.app"),
                                              bundleIdentifier: "com.bchewy.NotchShot", version: "0.6.0", build: 40,
                                              channel: buildChannel)
        let controller = UpdateController(preferences: preferences, installation: installation, service: service,
                                          schedule: clock.schedule, now: { now })
        addTeardownBlock { @MainActor in controller.stop() }
        return Fixture(controller: controller, service: service, clock: clock, preferences: preferences, now: now)
    }

    private func offer(build: Int, channel: UpdateChannel = .stable) -> UpdateOffer {
        let tag = channel == .stable ? "v0.7.0" : "nightly-\(build)"
        return UpdateOffer(channel: channel, tag: tag, version: "0.7.0", build: build,
                           sourceRevision: String(repeating: "c", count: 40), archiveName: "NotchShot-0.7.0.zip",
                           archiveURL: URL(string: "https://github.com/bchewy/notchshot/releases/download/\(tag)/NotchShot-0.7.0.zip")!,
                           archiveSHA256: String(repeating: "a", count: 64), archiveSize: 4096, page: nil)
    }
}

@MainActor
private final class FakeUpdateService: UpdateServing {
    var latest: Result<UpdateOffer?, Error> = .success(nil)
    var stageError: Error?
    var installError: Error?
    var holdChecks = false
    private(set) var checkedChannels: [UpdateChannel] = []
    private(set) var stagedOffers: [UpdateOffer] = []
    private(set) var installed: [StagedUpdate] = []
    private(set) var discarded: [StagedUpdate] = []
    private var held: [CheckedContinuation<Void, Never>] = []
    private var heldCheckArrived: CheckedContinuation<Void, Never>?

    func latestOffer(for channel: UpdateChannel) async throws -> UpdateOffer? {
        checkedChannels.append(channel)
        if holdChecks {
            await withCheckedContinuation { continuation in
                held.append(continuation)
                heldCheckArrived?.resume()
                heldCheckArrived = nil
            }
        }
        return try latest.get()
    }

    func stage(_ offer: UpdateOffer) async throws -> StagedUpdate {
        if let stageError { throw stageError }
        stagedOffers.append(offer)
        let directory = URL(fileURLWithPath: "/tmp/NotchShotUpdateControllerTests/\(offer.build)", isDirectory: true)
        return StagedUpdate(offer: offer, directory: directory, app: directory.appendingPathComponent("NotchShot.app"))
    }

    func install(_ update: StagedUpdate) throws {
        if let installError { throw installError }
        installed.append(update)
    }

    func discard(_ update: StagedUpdate) {
        discarded.append(update)
    }

    func waitForHeldCheck() async {
        guard held.isEmpty else { return }
        await withCheckedContinuation { heldCheckArrived = $0 }
    }

    func releaseHeldChecks() {
        holdChecks = false
        held.forEach { $0.resume() }
        held = []
    }
}

/// Advances logical time only; each test drives the controller's deadlines.
@MainActor
private final class VirtualUpdateClock {
    private struct Job {
        let due: Duration
        let action: @MainActor () -> Void
        var done = false
    }
    private var now = Duration.zero
    private var jobs: [Int: Job] = [:]
    private var nextID = 0
    var activeCount: Int { jobs.values.filter { !$0.done }.count }

    func schedule(_ delay: Duration, action: @escaping @MainActor () -> Void) -> (() -> Void) {
        nextID += 1
        let id = nextID
        jobs[id] = Job(due: now + delay, action: action)
        return { [weak self] in self?.jobs[id]?.done = true }
    }

    func advance(by interval: Duration) {
        let target = now + interval
        while let next = jobs.filter({ !$0.value.done && $0.value.due <= target })
            .min(by: { $0.value.due == $1.value.due ? $0.key < $1.key : $0.value.due < $1.value.due }) {
            now = next.value.due
            jobs[next.key]?.done = true
            next.value.action()
        }
        now = target
    }
}

@MainActor
private final class PendingPasteStub: AssistedPasteServing {
    var onResult: ((AssistedPasteResult) -> Void)?
    var hasPendingPaste = false
    func arm(capture: CaptureResult, clipboard: NSPasteboard) -> Bool { false }
    func cancel() {}
    func stop() {}
}
