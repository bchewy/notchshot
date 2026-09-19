// SPDX-License-Identifier: MIT
import AppKit
import XCTest
@testable import NotchShot

final class ShelfNavigationTests: XCTestCase {
    @MainActor
    func testLaunchIsCollapsedAndOpeningStartsOnShelf() {
        let store = makeStore()
        defer { store.stop() }
        XCTAssertFalse(store.isExpanded)
        XCTAssertEqual(store.page, .shelf)

        store.toggleExpanded()
        XCTAssertTrue(store.isExpanded)
        XCTAssertEqual(store.page, .shelf)
    }

    @MainActor
    func testSelectionDoesNotNavigateUntilUserOpensDetails() {
        let store = makeStore()
        defer { store.stop() }
        let first = makeCapture(), second = makeCapture()
        store.captures = [first, second]
        store.showShelf()
        store.selectedID = second.id
        XCTAssertEqual(store.page, .shelf)
        XCTAssertEqual(store.selectedCapture?.id, second.id)

        store.showCaptureDetail(second.id)
        XCTAssertEqual(store.page, .detail)
        XCTAssertTrue(store.isExpanded)
        store.showCaptureDetail(UUID())
        XCTAssertEqual(store.selectedID, second.id, "A stale thumbnail must not replace the current capture.")
    }

    @MainActor
    func testCollapseKeepsPageStableButNextOpenReturnsToShelf() {
        let store = makeStore()
        defer { store.stop() }
        let capture = makeCapture()
        store.captures = [capture]
        store.showCaptureDetail(capture.id)
        store.collapse()
        XCTAssertFalse(store.isExpanded)
        XCTAssertEqual(store.page, .detail, "Keep the outgoing content and expanded geometry stable during collapse.")

        store.toggleExpanded()
        XCTAssertTrue(store.isExpanded)
        XCTAssertEqual(store.page, .shelf)
        XCTAssertEqual(store.selectedID, capture.id)
    }

    @MainActor
    func testCollectingCaptureOpensShelfAndKeepsDetailsOptIn() {
        let store = makeStore()
        defer { store.stop() }
        let previous = makeCapture(), incoming = makeCapture()
        store.captures = [previous]
        store.showCaptureDetail(previous.id)
        store.pendingCapture = incoming
        store.acceptPendingCapture()

        XCTAssertTrue(store.isExpanded)
        XCTAssertEqual(store.page, .shelf)
        XCTAssertEqual(store.selectedID, incoming.id)
        XCTAssertEqual(store.captures.map(\.id), [incoming.id, previous.id])
        XCTAssertNil(store.pendingCapture)
    }

    @MainActor
    func testAutomaticArrivalOpensAndStaysOnShelfAfterCompletion() async throws {
        let store = makeStore()
        defer { store.stop() }
        let incoming = makeCapture()
        store.pendingCapture = incoming
        var finish: (() -> Void)?
        store.onLandCard = { finish = $0 }
        store.endCardDrag(accepted: false)
        try await waitUntil { finish != nil }

        XCTAssertTrue(store.isExpanded)
        XCTAssertEqual(store.page, .shelf)
        XCTAssertTrue(store.captures.isEmpty)
        finish?()
        try await Task.sleep(for: .milliseconds(25))

        XCTAssertTrue(store.isExpanded)
        XCTAssertEqual(store.page, .shelf)
        XCTAssertEqual(store.captures.map(\.id), [incoming.id])
        XCTAssertFalse(store.isLandingCapture)
    }

    @MainActor
    func testOpeningSettingsDuringFlightCollectsShotAndRejectsLateNavigation() async throws {
        let store = makeStore()
        defer { store.stop() }
        let incoming = makeCapture()
        store.pendingCapture = incoming
        var finish: (() -> Void)?
        store.onLandCard = { finish = $0 }
        store.endCardDrag(accepted: false)
        try await waitUntil { finish != nil }

        store.showCaptureSettings()
        finish?()

        XCTAssertTrue(store.isExpanded)
        XCTAssertEqual(store.page, .settings)
        XCTAssertTrue(store.showingSettings)
        XCTAssertEqual(store.captures.map(\.id), [incoming.id])
        XCTAssertFalse(store.isLandingCapture)
    }

    @MainActor
    func testDetailSelectionEvictedByArrivalReturnsToShelf() async throws {
        let store = makeStore()
        defer { store.stop() }
        store.captures = (0..<8).map { _ in makeCapture() }
        let oldestID = try XCTUnwrap(store.captures.last?.id)
        let incoming = makeCapture()
        store.pendingCapture = incoming
        var finish: (() -> Void)?
        store.onLandCard = { finish = $0 }
        store.endCardDrag(accepted: false)
        try await waitUntil { finish != nil }

        store.showCaptureDetail(oldestID)
        finish?()

        XCTAssertEqual(store.page, .shelf)
        XCTAssertEqual(store.selectedID, incoming.id)
        XCTAssertEqual(store.captures.count, 8)
        XCTAssertFalse(store.captures.contains(where: { $0.id == oldestID }))
    }

    @MainActor
    func testNavigationDuringPreviewDelayCollectsWithoutDelayedPageChange() async throws {
        for destination in [NotchPage.settings, .detail] {
            let store = makeStore(previewDelay: .milliseconds(50))
            defer { store.stop() }
            let previous = makeCapture(), incoming = makeCapture()
            store.captures = [previous]
            store.showShelf()
            store.pendingCapture = incoming
            var flights = 0
            store.onLandCard = { _ in flights += 1 }
            store.endCardDrag(accepted: false)
            XCTAssertFalse(store.isLandingCapture)

            if destination == .settings { store.showCaptureSettings() }
            else { store.showCaptureDetail(previous.id) }
            try await Task.sleep(for: .milliseconds(80))

            XCTAssertEqual(store.page, destination)
            XCTAssertTrue(store.isExpanded)
            XCTAssertNil(store.pendingCapture)
            XCTAssertEqual(store.captures.map(\.id), [incoming.id, previous.id])
            XCTAssertEqual(flights, 0)
            if destination == .detail { XCTAssertEqual(store.selectedID, previous.id) }
        }
    }

    @MainActor
    func testCollapseDuringPreviewDelaySavesCaptureAndPreservesOutgoingPage() async throws {
        let store = makeStore(previewDelay: .milliseconds(50))
        defer { store.stop() }
        let previous = makeCapture(), incoming = makeCapture()
        store.captures = [previous]
        store.showCaptureDetail(previous.id)
        store.pendingCapture = incoming
        var flights = 0
        store.onLandCard = { _ in flights += 1 }
        store.endCardDrag(accepted: false)
        XCTAssertFalse(store.isLandingCapture)

        store.collapse()
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertFalse(store.isExpanded)
        XCTAssertEqual(store.page, .detail)
        XCTAssertEqual(store.selectedID, previous.id)
        XCTAssertEqual(store.captures.map(\.id), [incoming.id, previous.id])
        XCTAssertNil(store.pendingCapture)
        XCTAssertEqual(flights, 0)
    }

    @MainActor
    func testNavigationWhileCaptureIsReadingAXQuietlyCollectsItsFinishedResult() async throws {
        for destination in [NotchPage.settings, .detail] {
            let store = makeStore()
            defer { store.stop() }
            let previous = makeCapture()
            var incoming = makeCapture()
            store.captures = [previous]
            store.showShelf()
            store.isCapturing = true
            store.pendingCapture = incoming
            var flights = 0
            store.onLandCard = { _ in flights += 1 }

            if destination == .settings { store.showCaptureSettings() }
            else { store.showCaptureDetail(previous.id) }
            XCTAssertEqual(store.pendingCapture?.id, incoming.id, "The partial screenshot must wait for its complete accessibility data.")
            XCTAssertEqual(store.captures.count, 1)

            incoming.accessibilityText = "Completed accessibility text"
            store.pendingCapture = incoming
            store.isCapturing = false
            store.endCardDrag(accepted: false)
            try await Task.sleep(for: .milliseconds(25))

            XCTAssertEqual(store.page, destination)
            XCTAssertTrue(store.isExpanded)
            XCTAssertNil(store.pendingCapture)
            XCTAssertEqual(store.captures.first?.accessibilityText, "Completed accessibility text")
            XCTAssertEqual(flights, 0)
            if destination == .detail { XCTAssertEqual(store.selectedID, previous.id) }
        }
    }

    @MainActor
    func testCollapseWhileCaptureIsReadingAXKeepsItsCompletedArrivalClosed() async throws {
        let store = makeStore()
        defer { store.stop() }
        let incoming = makeCapture()
        store.showShelf()
        store.isCapturing = true
        store.pendingCapture = incoming
        var flights = 0
        store.onLandCard = { _ in flights += 1 }
        store.collapse()
        store.isCapturing = false
        store.endCardDrag(accepted: false)
        try await Task.sleep(for: .milliseconds(25))

        XCTAssertFalse(store.isExpanded)
        XCTAssertEqual(store.page, .shelf)
        XCTAssertNil(store.pendingCapture)
        XCTAssertEqual(store.captures.map(\.id), [incoming.id])
        XCTAssertEqual(flights, 0)
    }

    @MainActor
    func testExistingShotDropReturnsToShelfWithoutOpeningDetails() {
        let store = makeStore()
        defer { store.stop() }
        let first = makeCapture(), second = makeCapture()
        store.captures = [first, second]
        store.showCaptureDetail(first.id)
        let pasteboard = NSPasteboard(name: .init("NotchShot.NavigationDrop.\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.declareTypes([CaptureCardPasteboard.captureID], owner: nil)
        pasteboard.setString(second.id.uuidString, forType: CaptureCardPasteboard.captureID)

        XCTAssertTrue(store.receiveDrop(pasteboard))
        XCTAssertEqual(store.page, .shelf)
        XCTAssertTrue(store.isExpanded)
        XCTAssertEqual(store.selectedID, second.id)
        XCTAssertEqual(store.captures.count, 2)
    }

    @MainActor
    func testExternalTextDropOpensShelfAndKeepsImportedDetailsOptIn() async throws {
        let store = makeStore()
        defer { store.stop() }
        let pasteboard = NSPasteboard(name: .init("NotchShot.NavigationImport.\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString("A local test Appshot", forType: .string)

        XCTAssertTrue(store.receiveDrop(pasteboard))
        XCTAssertTrue(store.isExpanded)
        XCTAssertEqual(store.page, .shelf)
        try await waitUntil { !store.isImporting }
        XCTAssertEqual(store.page, .shelf)
        XCTAssertEqual(store.selectedCapture?.importedText, "A local test Appshot")
    }

    @MainActor
    func testClearingDetailLeavesAnEmptyShelfWithoutChangingExpandedState() {
        let store = makeStore()
        defer { store.stop() }
        let capture = makeCapture()
        store.captures = [capture]
        store.showCaptureDetail(capture.id)
        store.clearHistory()

        XCTAssertEqual(store.page, .shelf)
        XCTAssertTrue(store.isExpanded)
        XCTAssertNil(store.selectedCapture)
        XCTAssertTrue(store.captures.isEmpty)
    }

    @MainActor
    private func makeStore(previewDelay: Duration = .milliseconds(1)) -> CaptureStore {
        let (preferences, clipboard) = isolatedStoreDependencies()
        preferences.set(false, forKey: "captureSoundEnabled")
        return CaptureStore(preferences: preferences,
                            landingPreviewDelay: previewDelay, shelfPreparationDelay: .milliseconds(1),
                            clipboard: clipboard)
    }

    private func makeCapture() -> CaptureResult {
        CaptureResult(appName: "Navigation Test", bundleIdentifier: "com.example.navigation", windowTitle: "Example")
    }

    @MainActor
    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw NSError(domain: "ShelfNavigationTests", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for shelf navigation."])
    }
}
