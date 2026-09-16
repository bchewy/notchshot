// SPDX-License-Identifier: MIT
import AppKit
import XCTest
@testable import NotchShot

final class ShotRemovalTests: XCTestCase {
    @MainActor
    func testRemovingSelectedShotChoosesItsNextNeighborOrPreviousAtEnd() {
        for removedIndex in 0..<3 {
            let store = makeStore()
            defer { store.stop() }
            let shots = (0..<3).map { makeCapture("Shot \($0)") }
            store.captures = shots
            store.selectedID = shots[removedIndex].id
            store.page = .detail
            store.isExpanded = true

            store.removeCapture(shots[removedIndex].id)

            let remaining = shots.enumerated().filter { $0.offset != removedIndex }.map(\.element)
            XCTAssertEqual(store.captures.map(\.id), remaining.map(\.id))
            XCTAssertEqual(store.selectedID, remaining[min(removedIndex, remaining.count - 1)].id)
            XCTAssertEqual(store.page, .detail)
            XCTAssertTrue(store.isExpanded)
        }
    }

    @MainActor
    func testRemovingUnselectedShotKeepsTheDetailBeingViewed() {
        let store = makeStore()
        defer { store.stop() }
        let first = makeCapture("First"), selected = makeCapture("Selected"), last = makeCapture("Last")
        store.captures = [first, selected, last]
        store.selectedID = selected.id
        store.page = .detail
        store.isExpanded = true

        store.removeCapture(first.id)

        XCTAssertEqual(store.captures.map(\.id), [selected.id, last.id])
        XCTAssertEqual(store.selectedID, selected.id)
        XCTAssertEqual(store.selectedCapture?.id, selected.id)
        XCTAssertEqual(store.page, .detail)
        XCTAssertTrue(store.isExpanded)
    }

    @MainActor
    func testRemovingLastShotClearsSelectionAndReturnsDetailsToShelfWithoutOpening() {
        for expanded in [true, false] {
            let store = makeStore()
            defer { store.stop() }
            let shot = makeCapture("Only shot")
            store.captures = [shot]
            store.selectedID = shot.id
            store.page = .detail
            store.isExpanded = expanded

            store.removeCapture(shot.id)

            XCTAssertTrue(store.captures.isEmpty)
            XCTAssertNil(store.selectedID)
            XCTAssertNil(store.selectedCapture)
            XCTAssertEqual(store.page, .shelf)
            XCTAssertEqual(store.isExpanded, expanded)
        }
    }

    @MainActor
    func testRemovalPreservesSettingsAndCollapsedNavigation() {
        for page in [NotchPage.settings, .shelf] {
            for expanded in [true, false] {
                let store = makeStore()
                defer { store.stop() }
                let shot = makeCapture("Only shot")
                store.captures = [shot]
                store.selectedID = shot.id
                store.page = page
                store.isExpanded = expanded

                store.removeCapture(shot.id)

                XCTAssertEqual(store.page, page)
                XCTAssertEqual(store.isExpanded, expanded)
                XCTAssertNil(store.selectedID)
            }
        }
    }

    @MainActor
    func testUnknownIDIsANoOpIncludingStatusAndPendingCapture() {
        let store = makeStore()
        defer { store.stop() }
        let saved = makeCapture("Saved"), incoming = makeCapture("Incoming")
        store.captures = [saved]
        store.selectedID = saved.id
        store.page = .settings
        store.pendingCapture = incoming
        store.isCapturing = true
        store.statusMessage = "Reading accessibility text…"
        var dismissals = 0
        store.onDismissCard = { dismissals += 1 }

        store.removeCapture(UUID())

        XCTAssertEqual(store.captures.map(\.id), [saved.id])
        XCTAssertEqual(store.selectedID, saved.id)
        XCTAssertEqual(store.pendingCapture?.id, incoming.id)
        XCTAssertTrue(store.isCapturing)
        XCTAssertEqual(store.statusMessage, "Reading accessibility text…")
        XCTAssertEqual(store.page, .settings)
        XCTAssertFalse(store.isExpanded)
        XCTAssertEqual(dismissals, 0)
    }

    @MainActor
    func testRemovingSavedShotDuringFlightKeepsPendingCaptureAndCompletionValid() async throws {
        let store = makeStore()
        defer { store.stop() }
        let saved = makeCapture("Saved"), incoming = makeCapture("Incoming")
        store.captures = [saved]
        store.selectedID = saved.id
        store.pendingCapture = incoming
        var finish: (() -> Void)?
        var dismissals = 0
        store.onLandCard = { finish = $0 }
        store.onDismissCard = { dismissals += 1 }
        store.endCardDrag(accepted: false)
        try await waitUntil { finish != nil }
        let destination = CGRect(x: 100, y: 200, width: 70, height: 36)
        store.reportShelfLandingFrame(destination, captureID: incoming.id, owner: UUID())

        store.removeCapture(saved.id)

        XCTAssertTrue(store.captures.isEmpty)
        XCTAssertNil(store.selectedID)
        XCTAssertEqual(store.pendingCapture?.id, incoming.id)
        XCTAssertTrue(store.isLandingCapture)
        XCTAssertEqual(store.shelfLandingFrame, destination)
        XCTAssertEqual(dismissals, 0)

        finish?()
        finish?()
        XCTAssertEqual(store.captures.map(\.id), [incoming.id])
        XCTAssertEqual(store.selectedID, incoming.id)
        XCTAssertNil(store.pendingCapture)
        XCTAssertFalse(store.isLandingCapture)
        XCTAssertEqual(store.page, .shelf)
        XCTAssertTrue(store.isExpanded)
        XCTAssertEqual(dismissals, 1)
    }

    @MainActor
    func testRemovingSavedShotDoesNotInvalidateAnImportAlreadyInProgress() async throws {
        let store = makeStore()
        defer { store.stop() }
        let saved = makeCapture("Saved")
        store.captures = [saved]
        store.selectedID = saved.id
        let pasteboard = NSPasteboard(name: .init("NotchShot.RemovalImport.\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString("A local imported shot", forType: .string)

        XCTAssertTrue(store.receiveDrop(pasteboard))
        XCTAssertTrue(store.isImporting)
        store.removeCapture(saved.id)
        XCTAssertTrue(store.isImporting)
        try await waitUntil { !store.isImporting }

        XCTAssertEqual(store.captures.count, 1)
        XCTAssertEqual(store.captures.first?.importedText, "A local imported shot")
        XCTAssertNotEqual(store.captures.first?.id, saved.id)
        XCTAssertEqual(store.selectedID, store.captures.first?.id)
    }

    @MainActor
    func testDraggingARemovedInternalIDCannotResurrectItThroughTextFallback() {
        let store = makeStore()
        defer { store.stop() }
        let removed = makeCapture("Removed"), retained = makeCapture("Retained")
        store.captures = [removed, retained]
        store.selectedID = retained.id
        let pasteboard = NSPasteboard(name: .init("NotchShot.RemovedDrag.\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.declareTypes([CaptureCardPasteboard.captureID, .string], owner: nil)
        pasteboard.setString(removed.id.uuidString, forType: CaptureCardPasteboard.captureID)
        pasteboard.setString("Removed shot context", forType: .string)
        XCTAssertTrue(store.canReceiveDrop(pasteboard))

        store.removeCapture(removed.id)
        let statusAfterRemoval = store.statusMessage

        XCTAssertFalse(store.canReceiveDrop(pasteboard))
        XCTAssertFalse(store.receiveDrop(pasteboard))
        XCTAssertEqual(store.captures.map(\.id), [retained.id])
        XCTAssertEqual(store.selectedID, retained.id)
        XCTAssertFalse(store.isImporting)
        XCTAssertFalse(store.isExpanded)
        XCTAssertEqual(store.statusMessage, statusAfterRemoval)
    }

    @MainActor
    private func makeStore() -> CaptureStore {
        let (preferences, clipboard) = isolatedStoreDependencies()
        return CaptureStore(preferences: preferences,
                            landingPreviewDelay: .milliseconds(1),
                            shelfPreparationDelay: .milliseconds(1),
                            captureSound: SilentRemovalTestSound(),
                            clipboard: clipboard)
    }

    private func makeCapture(_ name: String) -> CaptureResult {
        CaptureResult(appName: name, bundleIdentifier: "com.example.removal-test", windowTitle: name)
    }

    @MainActor
    private func waitUntil(_ predicate: @MainActor () -> Bool) async throws {
        for _ in 0..<200 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw NSError(domain: "ShotRemovalTests", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for a capture or import to complete."])
    }
}

@MainActor
private final class SilentRemovalTestSound: CaptureSoundPlaying {
    func play() {}
}
