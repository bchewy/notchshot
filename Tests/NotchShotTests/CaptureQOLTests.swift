// SPDX-License-Identifier: MIT
import AppKit
import XCTest
@testable import NotchShot

final class CaptureQOLTests: XCTestCase {
    @MainActor
    func testPreferencesKeepExistingBehaviorByDefaultAndRestoreUserChoices() {
        let fixture = makeFixture()
        let store = fixture.store
        defer { store.stop() }
        XCTAssertFalse(store.autoCopyCapture)
        XCTAssertTrue(store.openShelfAfterCapture)
        XCTAssertEqual(store.captureSoundVolume, 0.65, accuracy: 0.001)
        XCTAssertEqual(fixture.sound.volumes, [0.65])

        store.autoCopyCapture = true
        store.openShelfAfterCapture = false
        store.captureSoundVolume = 0.27

        let restoredSound = QOLSoundSpy()
        let restored = CaptureStore(preferences: fixture.preferences,
                                    captureSound: restoredSound,
                                    clipboard: fixture.clipboard)
        defer { restored.stop() }
        XCTAssertTrue(restored.autoCopyCapture)
        XCTAssertFalse(restored.openShelfAfterCapture)
        XCTAssertEqual(restored.captureSoundVolume, 0.27, accuracy: 0.001)
        XCTAssertEqual(restoredSound.volumes.last ?? -1, 0.27, accuracy: 0.001)
        XCTAssertEqual(fixture.sound.playCount, 0)
        XCTAssertEqual(restoredSound.playCount, 0)
    }

    @MainActor
    func testInvalidVolumeIsSanitizedPersistedAndAppliedWithoutPlaying() {
        let fixture = makeFixture()
        defer { fixture.store.stop() }
        let cases: [(Double, Double)] = [(-1, 0), (2, 1), (.nan, 0.65), (.infinity, 0.65), (-.infinity, 0.65)]
        for (input, expected) in cases {
            fixture.store.captureSoundVolume = input
            XCTAssertEqual(fixture.store.captureSoundVolume, expected, accuracy: 0.001)
            XCTAssertEqual(fixture.preferences.double(forKey: "captureSoundVolume"), expected, accuracy: 0.001)
            XCTAssertEqual(fixture.sound.volumes.last ?? -1, Float(expected), accuracy: 0.001)
        }
        XCTAssertEqual(fixture.sound.playCount, 0)

        // An out-of-range value from an older preference file is safe on launch, too.
        fixture.preferences.set(12.0, forKey: "captureSoundVolume")
        let restoredSound = QOLSoundSpy()
        let restored = CaptureStore(preferences: fixture.preferences,
                                    captureSound: restoredSound,
                                    clipboard: fixture.clipboard)
        defer { restored.stop() }
        XCTAssertEqual(restored.captureSoundVolume, 1)
        XCTAssertEqual(restoredSound.volumes, [1])
        XCTAssertEqual(restoredSound.playCount, 0)
    }

    @MainActor
    func testCopyHoveredShotUsesItsExactContextAndImageWithoutChangingNavigation() throws {
        let fixture = makeFixture()
        let store = fixture.store
        defer { store.stop() }
        let selected = makeCapture("Selected detail")
        let hovered = try makeImageCapture("Hovered thumbnail")
        store.captures = [selected, hovered]
        store.selectedID = selected.id
        store.page = .detail
        store.isExpanded = true

        XCTAssertTrue(store.copyCapture(hovered.id))

        XCTAssertEqual(fixture.clipboard.string(forType: .string), hovered.contextText)
        XCTAssertEqual(fixture.clipboard.data(forType: .png), hovered.pngData)
        let tiff = try XCTUnwrap(fixture.clipboard.data(forType: .tiff))
        XCTAssertNotNil(NSImage(data: tiff))
        XCTAssertEqual(store.selectedID, selected.id)
        XCTAssertEqual(store.page, .detail)
        XCTAssertTrue(store.isExpanded)
        XCTAssertEqual(store.captures.map(\.id), [selected.id, hovered.id])

        let changeCount = fixture.clipboard.changeCount
        let status = store.statusNotice?.message
        XCTAssertFalse(store.copyCapture(UUID()))
        XCTAssertEqual(fixture.clipboard.changeCount, changeCount, "A stale hover must leave the user's clipboard intact.")
        XCTAssertEqual(fixture.clipboard.string(forType: .string), hovered.contextText)
        XCTAssertEqual(store.statusNotice?.message, status)
    }

    @MainActor
    func testAutoCopyWaitsForCompletedCaptureAndDoesNotOverwriteLaterUserCopies() throws {
        let fixture = makeFixture()
        let store = fixture.store
        defer { store.stop() }
        let completed = try makeImageCapture("Complete capture")
        fixture.clipboard.setString("Original clipboard", forType: .string)
        let originalChangeCount = fixture.clipboard.changeCount

        store.autoCopyCompletedCapture(completed)
        XCTAssertEqual(fixture.clipboard.changeCount, originalChangeCount, "Auto-copy starts disabled.")

        store.autoCopyCapture = true
        store.isCapturing = true
        var partial = completed
        partial.axTree = []
        partial.accessibilityText = ""
        partial.ocrText = ""
        store.autoCopyCompletedCapture(partial)
        XCTAssertEqual(fixture.clipboard.changeCount, originalChangeCount, "The screenshot callback is not a completed appshot.")

        store.isCapturing = false
        store.autoCopyCompletedCapture(completed)
        let copiedText = try XCTUnwrap(fixture.clipboard.string(forType: .string))
        XCTAssertEqual(copiedText, completed.contextText)
        XCTAssertTrue(copiedText.contains("## Accessibility text\nAccessible content for Complete capture"))
        XCTAssertTrue(copiedText.contains("## Accessibility tree"))
        XCTAssertTrue(copiedText.contains("button Submit Complete capture"))
        XCTAssertTrue(copiedText.contains("## Text recognized from screenshot (OCR)"))
        XCTAssertEqual(fixture.clipboard.data(forType: .png), completed.pngData)
        XCTAssertNotNil(fixture.clipboard.data(forType: .tiff))

        fixture.clipboard.clearContents()
        fixture.clipboard.setString("Copied something else while the card was flying", forType: .string)
        let userChangeCount = fixture.clipboard.changeCount
        store.autoCopyCompletedCapture(completed)
        store.pendingCapture = completed
        store.acceptPendingCapture()
        XCTAssertEqual(fixture.clipboard.changeCount, userChangeCount, "Collection must not repeat the earlier automatic copy.")
        XCTAssertEqual(fixture.clipboard.string(forType: .string), "Copied something else while the card was flying")
        XCTAssertEqual(store.captures.map(\.id), [completed.id])
    }

    @MainActor
    func testCollectingACompletedCaptureCanPerformItsFirstAutomaticCopy() {
        let fixture = makeFixture()
        let store = fixture.store
        defer { store.stop() }
        let completed = makeCapture("Collected capture")
        store.autoCopyCapture = true
        store.pendingCapture = completed

        store.acceptPendingCapture()

        XCTAssertEqual(fixture.clipboard.string(forType: .string), completed.contextText)
        XCTAssertEqual(store.captures.map(\.id), [completed.id])
    }

    @MainActor
    func testQuietArrivalFliesAndCollectsWithoutOpeningCollapsedNotch() async throws {
        let fixture = makeFixture()
        let store = fixture.store
        defer { store.stop() }
        let capture = makeCapture("Quiet arrival")
        store.openShelfAfterCapture = false
        store.pendingCapture = capture
        var finish: (() -> Void)?
        var dismissed = 0
        store.onLandCard = { finish = $0 }
        store.onDismissCard = { dismissed += 1 }

        store.endCardDrag(accepted: false)
        try await waitUntil { finish != nil }

        XCTAssertTrue(store.isLandingCapture)
        XCTAssertFalse(store.isExpanded)
        XCTAssertEqual(store.page, .shelf)
        XCTAssertTrue(store.captures.isEmpty)
        XCTAssertEqual(store.pendingCapture?.id, capture.id)
        finish?()
        finish?()
        XCTAssertFalse(store.isExpanded)
        XCTAssertEqual(store.page, .shelf)
        XCTAssertEqual(store.captures.map(\.id), [capture.id])
        XCTAssertNil(store.pendingCapture)
        XCTAssertFalse(store.isLandingCapture)
        XCTAssertEqual(dismissed, 1)
    }

    @MainActor
    func testQuietArrivalPreservesExpandedDetailAndItsSelectionAtHistoryLimit() async throws {
        let fixture = makeFixture()
        let store = fixture.store
        defer { store.stop() }
        let existing = (0..<8).map { makeCapture("Existing \($0)") }
        let selected = try XCTUnwrap(existing.last)
        let incoming = makeCapture("New incoming")
        store.openShelfAfterCapture = false
        store.captures = existing
        store.selectedID = selected.id
        store.page = .detail
        store.isExpanded = true
        store.pendingCapture = incoming
        var finish: (() -> Void)?
        store.onLandCard = { finish = $0 }

        store.endCardDrag(accepted: false)
        try await waitUntil { finish != nil }
        XCTAssertTrue(store.isExpanded)
        XCTAssertEqual(store.page, .detail)
        XCTAssertEqual(store.selectedID, selected.id)
        finish?()

        XCTAssertTrue(store.isExpanded)
        XCTAssertEqual(store.page, .detail)
        XCTAssertEqual(store.selectedID, selected.id)
        XCTAssertEqual(store.selectedCapture?.id, selected.id)
        XCTAssertEqual(store.captures.count, 8)
        XCTAssertEqual(store.captures.first?.id, incoming.id)
        XCTAssertTrue(store.captures.contains { $0.id == selected.id })
        XCTAssertNil(store.pendingCapture)
    }

    @MainActor
    func testQuietArrivalPreservesSettingsButExplicitCollectionStillOpensShelf() async throws {
        let fixture = makeFixture()
        let store = fixture.store
        defer { store.stop() }
        store.openShelfAfterCapture = false
        store.page = .settings
        store.isExpanded = true
        store.pendingCapture = makeCapture("Quiet settings arrival")
        var finish: (() -> Void)?
        store.onLandCard = { finish = $0 }
        store.endCardDrag(accepted: false)
        try await waitUntil { finish != nil }
        finish?()
        XCTAssertEqual(store.page, .settings)
        XCTAssertTrue(store.isExpanded)

        store.collapse()
        let explicitlyCollected = makeCapture("Explicit collection")
        store.pendingCapture = explicitlyCollected
        store.acceptPendingCapture()
        XCTAssertTrue(store.isExpanded)
        XCTAssertEqual(store.page, .shelf)
        XCTAssertEqual(store.selectedID, explicitlyCollected.id)
    }

    @MainActor
    private func makeFixture() -> (store: CaptureStore, preferences: UserDefaults, clipboard: NSPasteboard, sound: QOLSoundSpy) {
        let suite = "NotchShotQOLTests-\(UUID())"
        let preferences = UserDefaults(suiteName: suite)!
        let clipboard = NSPasteboard(name: .init(suite))
        let sound = QOLSoundSpy()
        addTeardownBlock {
            preferences.removePersistentDomain(forName: suite)
            clipboard.releaseGlobally()
        }
        let store = CaptureStore(preferences: preferences,
                                 landingPreviewDelay: .milliseconds(1),
                                 shelfPreparationDelay: .milliseconds(1),
                                 captureSound: sound,
                                 clipboard: clipboard,
                                 copySound: QOLSoundSpy())
        return (store, preferences, clipboard, sound)
    }

    private func makeCapture(_ name: String) -> CaptureResult {
        CaptureResult(appName: name, bundleIdentifier: "com.example.qol", windowTitle: name,
                      axTree: [AXNode(id: 1, role: "AXButton", roleDescription: "button", title: "Submit \(name)")],
                      accessibilityText: "Accessible content for \(name)",
                      ocrText: "Recognized screenshot content for \(name)")
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

    @MainActor
    private func waitUntil(_ predicate: @MainActor () -> Bool) async throws {
        for _ in 0..<200 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw NSError(domain: "CaptureQOLTests", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for capture arrival."])
    }
}

@MainActor
private final class QOLSoundSpy: CaptureSoundPlaying, CopySoundPlaying {
    var playCount = 0
    var volumes: [Float] = []
    func play() { playCount += 1 }
    func setVolume(_ volume: Float) { volumes.append(volume) }
}
