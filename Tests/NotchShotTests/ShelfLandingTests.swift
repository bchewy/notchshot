// SPDX-License-Identifier: MIT
import AppKit
import XCTest
@testable import NotchShot

final class ShelfLandingTests: XCTestCase {
    @MainActor
    func testReceivingSlotOpensBeforeFlightAndCompletionCollectsOnlyOnce() async throws {
        let store = makeStore(preparationDelay: .milliseconds(50))
        defer { store.stop() }
        let capture = makeCapture()
        store.showingSettings = true
        store.isExpanded = false
        store.pendingCapture = capture
        var finish: (() -> Void)?
        store.onLandCard = { finish = $0 }

        store.endCardDrag(accepted: false)
        try await waitUntil { store.isLandingCapture }
        XCTAssertTrue(store.isExpanded)
        XCTAssertFalse(store.showingSettings)
        XCTAssertNil(finish, "The notch needs time to open and measure the reserved slot before flight.")
        XCTAssertTrue(store.captures.isEmpty)
        try await waitUntil { finish != nil }
        finish?()
        finish?()

        XCTAssertEqual(store.captures.map(\.id), [capture.id])
        XCTAssertNil(store.pendingCapture)
        XCTAssertFalse(store.isLandingCapture)
        XCTAssertNil(store.shelfLandingFrame)
    }

    @MainActor
    func testReplacementDuringShelfPreparationCancelsEarlierFlight() async throws {
        let store = makeStore(preparationDelay: .milliseconds(50))
        defer { store.stop() }
        store.pendingCapture = makeCapture()
        var flights = 0
        store.onLandCard = { _ in flights += 1 }
        store.endCardDrag(accepted: false)
        try await waitUntil { store.isLandingCapture }

        let replacement = makeCapture()
        store.pendingCapture = replacement
        XCTAssertFalse(store.isLandingCapture)
        try await Task.sleep(for: .milliseconds(75))
        XCTAssertEqual(flights, 0)
        XCTAssertEqual(store.pendingCapture?.id, replacement.id)
        XCTAssertTrue(store.captures.isEmpty)
    }

    @MainActor
    func testDragAndResumeRejectsOldCompletionEvenForSameCaptureID() async throws {
        let store = makeStore()
        defer { store.stop() }
        let capture = makeCapture()
        store.pendingCapture = capture
        var finishes: [() -> Void] = []
        store.onLandCard = { finishes.append($0) }
        store.endCardDrag(accepted: false)
        try await waitUntil { finishes.count == 1 }

        store.beginCardDrag()
        XCTAssertFalse(store.isLandingCapture)
        store.endCardDrag(accepted: false)
        try await waitUntil { finishes.count == 2 }
        finishes[0]()
        XCTAssertEqual(store.pendingCapture?.id, capture.id)
        XCTAssertTrue(store.isLandingCapture)
        XCTAssertTrue(store.captures.isEmpty)

        finishes[1]()
        XCTAssertEqual(store.captures.map(\.id), [capture.id])
        XCTAssertFalse(store.isLandingCapture)
    }

    @MainActor
    func testClearOrDismissInvalidatesInFlightCompletion() async throws {
        for clearHistory in [true, false] {
            let store = makeStore()
            defer { store.stop() }
            store.pendingCapture = makeCapture()
            var finish: (() -> Void)?
            store.onLandCard = { finish = $0 }
            store.endCardDrag(accepted: false)
            try await waitUntil { finish != nil }

            if clearHistory { store.clearHistory() } else { store.dismissPendingCapture() }
            finish?()
            XCTAssertNil(store.pendingCapture)
            XCTAssertFalse(store.isLandingCapture)
            XCTAssertTrue(store.captures.isEmpty)
        }
    }

    @MainActor
    func testStoppedPreparationDoesNotCallFlight() async throws {
        let store = makeStore(preparationDelay: .milliseconds(50))
        store.pendingCapture = makeCapture()
        var flights = 0
        store.onLandCard = { _ in flights += 1 }
        store.endCardDrag(accepted: false)
        try await waitUntil { store.isLandingCapture }
        store.stop()
        try await Task.sleep(for: .milliseconds(75))
        XCTAssertFalse(store.isLandingCapture)
        XCTAssertEqual(flights, 0)
    }

    @MainActor
    func testClosingDuringPreparationSavesCaptureWithoutFlightOrReopening() async throws {
        let store = makeStore(preparationDelay: .milliseconds(50))
        defer { store.stop() }
        let capture = makeCapture()
        store.pendingCapture = capture
        var flights = 0
        var dismissals = 0
        store.onLandCard = { _ in flights += 1 }
        store.onDismissCard = { dismissals += 1 }
        store.endCardDrag(accepted: false)
        try await waitUntil { store.isLandingCapture }

        store.collapse()
        try await Task.sleep(for: .milliseconds(75))

        XCTAssertFalse(store.isExpanded)
        XCTAssertFalse(store.isLandingCapture)
        XCTAssertNil(store.pendingCapture)
        XCTAssertEqual(store.captures.map(\.id), [capture.id])
        XCTAssertEqual(flights, 0)
        XCTAssertEqual(dismissals, 1)
    }

    @MainActor
    func testClosingDuringFlightSavesCaptureAndRejectsLateReopeningCompletion() async throws {
        let store = makeStore()
        defer { store.stop() }
        let capture = makeCapture()
        store.pendingCapture = capture
        var finish: (() -> Void)?
        var dismissals = 0
        store.onLandCard = { finish = $0 }
        store.onDismissCard = { dismissals += 1 }
        store.endCardDrag(accepted: false)
        try await waitUntil { finish != nil }

        store.collapse()
        finish?()
        finish?()

        XCTAssertFalse(store.isExpanded)
        XCTAssertFalse(store.isLandingCapture)
        XCTAssertNil(store.pendingCapture)
        XCTAssertEqual(store.captures.map(\.id), [capture.id])
        XCTAssertEqual(dismissals, 1)
    }

    @MainActor
    func testOldReporterCannotClearNewDestinationOrPublishForReplacedCapture() {
        let store = makeStore()
        defer { store.stop() }
        let capture = makeCapture()
        store.pendingCapture = capture
        store.isLandingCapture = true
        let firstOwner = UUID(), newOwner = UUID()
        let firstFrame = CGRect(x: 100, y: 200, width: 70, height: 36)
        let newFrame = CGRect(x: 120, y: 230, width: 70, height: 36)
        store.reportShelfLandingFrame(firstFrame, captureID: capture.id, owner: firstOwner)
        store.reportShelfLandingFrame(newFrame, captureID: capture.id, owner: newOwner)
        store.clearShelfLandingFrame(owner: firstOwner)
        XCTAssertEqual(store.shelfLandingFrame, newFrame)

        store.pendingCapture = makeCapture()
        XCTAssertNil(store.shelfLandingFrame)
        store.isLandingCapture = true
        store.reportShelfLandingFrame(firstFrame, captureID: capture.id, owner: firstOwner)
        XCTAssertNil(store.shelfLandingFrame)
    }

    @MainActor
    func testNativeReporterMeasuresThumbnailAcrossFlippedViewAndWindowMovement() throws {
        _ = NSApplication.shared
        guard NotchGeometry.preferredScreen != nil else {
            throw XCTSkip("Native destination measurement requires WindowServer display access.")
        }
        let store = makeStore()
        let capture = makeCapture()
        store.pendingCapture = capture
        store.isLandingCapture = true
        let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 440, height: 480),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close(); store.stop() }
        let container = FlippedShelfFixture(frame: CGRect(x: 20, y: 30, width: 200, height: 100))
        let reporter = ShelfLandingTargetNSView(frame: CGRect(x: 11, y: 13, width: 70, height: 36))
        window.contentView?.addSubview(container)
        container.addSubview(reporter)
        reporter.configure(store: store, captureID: capture.id)
        reporter.layout()
        XCTAssertEqual(store.shelfLandingFrame, CGRect(x: 131, y: 181, width: 70, height: 36))
        XCTAssertFalse(window.isVisible)

        window.setFrameOrigin(CGPoint(x: 200, y: 300))
        reporter.layout()
        XCTAssertEqual(store.shelfLandingFrame, CGRect(x: 231, y: 381, width: 70, height: 36))
        reporter.stopReporting()
        XCTAssertNil(store.shelfLandingFrame)
    }

    @MainActor
    private func makeStore(preparationDelay: Duration = .milliseconds(1)) -> CaptureStore {
        let (preferences, clipboard) = isolatedStoreDependencies()
        return CaptureStore(preferences: preferences, landingPreviewDelay: .milliseconds(1),
                            shelfPreparationDelay: preparationDelay, clipboard: clipboard)
    }

    private func makeCapture() -> CaptureResult {
        CaptureResult(appName: "Shelf Test", bundleIdentifier: "com.example.shelf-test", windowTitle: "Example")
    }

    @MainActor
    private func waitUntil(_ predicate: @MainActor () -> Bool) async throws {
        for _ in 0..<200 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw NSError(domain: "ShelfLandingTests", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for the landing phase."])
    }
}

private final class FlippedShelfFixture: NSView {
    override var isFlipped: Bool { true }
}
