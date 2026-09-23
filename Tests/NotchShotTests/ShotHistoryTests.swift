// SPDX-License-Identifier: MIT
import AppKit
import XCTest
@testable import NotchShot

@MainActor
final class ShotHistoryTests: XCTestCase {
    private var root: URL!
    private let now = Date(timeIntervalSince1970: 10_000_000)

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchShotHistoryTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("History", isDirectory: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    func testHistoryIsOffByDefaultAndSavesNothing() async {
        let (preferences, _) = isolatedStoreDependencies()
        let history = makeHistory(preferences)
        XCTAssertFalse(history.isEnabled)
        XCTAssertEqual(history.retention, .month)
        history.record(shot("Notes", daysAgo: 0))
        history.rememberShelf([UUID()])
        await history.settle()
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path), "Nothing touches the disk while history is off.")
        XCTAssertFalse(history.holdsShelf([]))
    }

    func testSavedShotsAreListedNewestFirstAndFilteredBySearchAndPins() async {
        let (preferences, _) = isolatedStoreDependencies()
        let history = makeHistory(preferences)
        history.isEnabled = true
        let old = shot("Safari", daysAgo: 3, text: "release checklist")
        let new = shot("Notes", daysAgo: 1, text: "coffee checklist")
        history.record(new)
        history.record(old)
        await history.settle()
        XCTAssertEqual(history.entries.map(\.id), [new.id, old.id])
        XCTAssertGreaterThan(history.storageBytes, 0)

        history.query = "checklist"
        XCTAssertEqual(history.results.map(\.id), [new.id, old.id])
        history.query = "RELEASE safari"
        XCTAssertEqual(history.results.map(\.id), [old.id])
        history.query = ""
        history.setPinned(true, for: old.id)
        history.showsPinnedOnly = true
        XCTAssertEqual(history.results.map(\.id), [old.id])

        await history.settle()
        let reopened = makeHistory(preferences)
        reopened.load()
        await reopened.settle()
        XCTAssertEqual(reopened.entries.map(\.id), [new.id, old.id])
        XCTAssertEqual(reopened.entries.map(\.isPinned), [false, true], "Pins persist.")
    }

    func testRetentionDeletesOnlyOldUnpinnedShotsThatAreOffTheShelf() async {
        let (preferences, _) = isolatedStoreDependencies()
        let history = makeHistory(preferences)
        history.retention = .forever
        history.isEnabled = true
        let expired = shot("Old", daysAgo: 40)
        let pinned = shot("Pinned", daysAgo: 40)
        let onShelf = shot("Shelf", daysAgo: 40)
        let recent = shot("Recent", daysAgo: 10)
        [expired, pinned, onShelf, recent].forEach(history.record)
        await history.settle()
        history.setPinned(true, for: pinned.id)
        history.rememberShelf([onShelf.id])
        await history.settle()
        XCTAssertEqual(history.entries.count, 4, "Forever keeps everything.")

        history.retention = .month
        await history.settle()
        XCTAssertEqual(Set(history.entries.map(\.id)), [pinned.id, onShelf.id, recent.id])
        history.retention = .week
        await history.settle()
        XCTAssertEqual(Set(history.entries.map(\.id)), [pinned.id, onShelf.id])

        // After a relaunch, the saved shelf is protected before it is restored.
        let relaunched = makeHistory(preferences)
        relaunched.load()
        await relaunched.settle()
        XCTAssertEqual(Set(relaunched.entries.map(\.id)), [pinned.id, onShelf.id])
        XCTAssertEqual(preferences.string(forKey: "historyRetention"), "week")
    }

    func testTurningHistoryOffKeepsSavedShotsUntilTheyAreDeleted() async {
        let (preferences, _) = isolatedStoreDependencies()
        let history = makeHistory(preferences)
        history.isEnabled = true
        history.record(shot("Notes", daysAgo: 0))
        await history.settle()

        history.isEnabled = false
        XCTAssertEqual(history.entries, [])
        XCTAssertGreaterThan(history.storageBytes, 0)
        let relaunched = makeHistory(preferences)
        relaunched.load()
        await relaunched.settle()
        XCTAssertFalse(relaunched.isEnabled)
        XCTAssertGreaterThan(relaunched.storageBytes, 0, "Leftover shots are still found so they can be deleted.")

        relaunched.deleteAll()
        await relaunched.settle()
        XCTAssertEqual(relaunched.storageBytes, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testQuittingWaitsForAShotStillBeingSaved() async {
        let (preferences, _) = isolatedStoreDependencies()
        let history = makeHistory(preferences)
        history.isEnabled = true
        let lastShot = shot("Last", daysAgo: 0)
        history.record(lastShot)
        history.rememberShelf([lastShot.id])
        await history.settle(timeout: .seconds(3))

        let relaunched = makeHistory(preferences)
        relaunched.load()
        let shelf = await relaunched.restoreShelf()
        XCTAssertEqual(shelf.map(\.id), [lastShot.id], "A shot captured just before quitting comes back.")
    }

    func testLeavingTheShelfEndsProtectionFromRetention() async {
        let (preferences, _) = isolatedStoreDependencies()
        let history = makeHistory(preferences)
        history.isEnabled = true
        let old = shot("Old", daysAgo: 40)
        history.record(old)
        history.rememberShelf([old.id])
        await history.settle()
        XCTAssertEqual(history.entries.map(\.id), [old.id], "Kept while it is on the shelf.")

        history.rememberShelf([])
        await history.settle()
        XCTAssertEqual(history.entries, [], "Pruned as soon as it leaves the shelf.")
    }

    func testFailedDeletionShowsTheShotAgainWithAReason() async throws {
        let (preferences, _) = isolatedStoreDependencies()
        let history = makeHistory(preferences)
        history.isEnabled = true
        let kept = shot("Kept", daysAgo: 0)
        history.record(kept)
        await history.settle()

        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path) }
        history.delete([kept.id])
        XCTAssertEqual(history.entries, [], "Removed from the list right away.")
        await history.settle()
        XCTAssertEqual(history.entries.map(\.id), [kept.id], "Still on disk, so it is listed again.")
        XCTAssertEqual(history.failure, "Couldn’t delete a shot from history.")
    }

    func testShelfComesBackAfterRelaunchInOrder() async throws {
        let (preferences, clipboard) = isolatedStoreDependencies()
        let history = makeHistory(preferences)
        history.isEnabled = true
        let store = CaptureStore(preferences: preferences, clipboard: clipboard, history: history)
        defer { store.stop() }
        let first = shot("First", daysAgo: 0), second = shot("Second", daysAgo: 0)
        collect(first, into: store)
        collect(second, into: store)
        await history.settle()
        XCTAssertEqual(history.entries.map(\.id).sorted(), [first.id, second.id].sorted())

        let relaunchedHistory = makeHistory(preferences)
        relaunchedHistory.load()
        let relaunched = CaptureStore(preferences: preferences, clipboard: clipboard, history: relaunchedHistory)
        defer { relaunched.stop() }
        relaunched.restoreSavedShelf()
        try await waitUntil { relaunched.captures.count == 2 }
        XCTAssertEqual(relaunched.captures.map(\.id), [second.id, first.id])
        XCTAssertEqual(relaunched.captures.first?.accessibilityText, second.accessibilityText)
        XCTAssertEqual(relaunched.captures.first?.pngData, second.pngData)
    }

    func testUpdatesMayRelaunchOnlyWhenTheShelfWouldComeBack() async {
        let (preferences, clipboard) = isolatedStoreDependencies()
        let history = makeHistory(preferences)
        let store = CaptureStore(preferences: preferences, clipboard: clipboard, history: history)
        defer { store.stop() }
        store.captures = [shot("Unsaved", daysAgo: 0)]
        XCTAssertFalse(store.canRelaunchUnnoticed, "History off: the shelf would be lost.")

        history.isEnabled = true
        await history.settle()
        XCTAssertTrue(store.canRelaunchUnnoticed, "Turning history on saves the shelf already there.")

        store.captures.insert(shot("Arriving", daysAgo: 0), at: 0)
        XCTAssertFalse(store.canRelaunchUnnoticed, "Not until the new shot is saved.")
        collect(store.captures[0], into: store)
        await history.settle()
        XCTAssertFalse(store.canRelaunchUnnoticed, "A new shot opens the shelf.")
        store.collapse()
        XCTAssertTrue(store.canRelaunchUnnoticed)

        store.isExpanded = true
        XCTAssertFalse(store.canRelaunchUnnoticed, "The notch is in use.")
    }

    func testOpeningFromHistoryPutsTheShotBackOnTheShelf() async throws {
        let (preferences, clipboard) = isolatedStoreDependencies()
        let history = makeHistory(preferences)
        history.isEnabled = true
        let store = CaptureStore(preferences: preferences, clipboard: clipboard, history: history)
        defer { store.stop() }
        let saved = shot("Saved", daysAgo: 2, text: "reopen me")
        collect(saved, into: store)
        await history.settle()
        store.clearHistory()
        XCTAssertEqual(history.entries.map(\.id), [saved.id], "Clearing the shelf keeps history.")

        store.showHistory()
        XCTAssertEqual(store.page, .history)
        store.openFromHistory(saved.id)
        try await waitUntil { store.page == .detail }
        XCTAssertEqual(store.captures.map(\.id), [saved.id])
        XCTAssertEqual(store.selectedCapture?.accessibilityText, "reopen me")

        history.delete([saved.id])
        await history.settle()
        store.openFromHistory(saved.id)
        try await waitUntil { store.statusNotice?.kind == .error }
        XCTAssertEqual(store.statusNotice?.message, "That shot is no longer in history.")
    }

    func testCopyingFromHistoryUsesTheCopyContentSetting() async throws {
        let (preferences, clipboard) = isolatedStoreDependencies()
        let history = makeHistory(preferences)
        history.isEnabled = true
        let store = CaptureStore(preferences: preferences, clipboard: clipboard, copySound: SilentHistoryCopySound(), history: history)
        defer { store.stop() }
        store.copyContent = .treeOnly
        let saved = shot("Saved", daysAgo: 1, text: "tree words")
        collect(saved, into: store)
        await history.settle()
        store.clearHistory()
        clipboard.clearContents()

        store.copyFromHistory(saved.id)
        try await waitUntil { clipboard.string(forType: .string) != nil }
        XCTAssertTrue(clipboard.string(forType: .string)?.contains("tree words") == true)
        XCTAssertNil(clipboard.data(forType: .png), "AX tree only never includes image data.")
        XCTAssertEqual(store.captures, [], "Copying does not add the shot to the shelf.")
    }

    // MARK: - Helpers

    private func makeHistory(_ preferences: UserDefaults) -> ShotHistory {
        ShotHistory(preferences: preferences, archive: ShotArchive(root: root), now: { [now] in now })
    }

    private func shot(_ app: String, daysAgo: Double, text: String = "text") -> CaptureResult {
        makeHistoryCapture(appName: app, title: "\(app) window", text: text, png: historyPNG(),
                           date: now.addingTimeInterval(-daysAgo * 86_400))
    }

    /// The same path a finished capture takes onto the shelf.
    private func collect(_ capture: CaptureResult, into store: CaptureStore) {
        store.pendingCapture = capture
        store.acceptPendingCapture()
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for history work to finish.")
    }
}

private final class SilentHistoryCopySound: CopySoundPlaying { func play() {} }

extension CaptureResult: Equatable {
    public static func == (lhs: CaptureResult, rhs: CaptureResult) -> Bool { lhs.id == rhs.id }
}
