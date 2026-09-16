// SPDX-License-Identifier: MIT
import AppKit
import XCTest
@testable import NotchShot

/// Drives CaptureStore.captureFrontmost through a fake capture service, so the
/// partial-then-complete presentation, error routing, and cancellation run
/// under test instead of only in production.
final class CaptureFrontmostTests: XCTestCase {
    @MainActor
    func testPartialThenCompleteResultPresentsTheCardTwiceAndAcceptsOnce() async throws {
        let f = makeFixture()
        defer { f.store.stop() }
        f.store.autoCollectCaptures = false
        f.store.captureFrontmost()
        XCTAssertTrue(f.store.isCapturing)
        XCTAssertNil(f.store.statusNotice)
        try await f.service.waitForCaptureRequest()
        XCTAssertEqual(f.service.captureCalls.map(\.appName), ["Fake App"])

        let partial = makeCapture()
        f.service.deliverPartial(partial)
        XCTAssertEqual(f.store.pendingCapture?.id, partial.id)
        XCTAssertEqual(f.recorder.presented.map(\.id), [partial.id])
        XCTAssertEqual(f.captureSound.playCount, 1)
        XCTAssertTrue(f.store.isCapturing, "The busy flag stays until the full result arrives.")

        var complete = partial
        complete.accessibilityText = "Hello"
        f.service.complete(with: complete)
        try await waitUntil { !f.store.isCapturing }
        XCTAssertEqual(f.store.pendingCapture?.accessibilityText, "Hello")
        XCTAssertEqual(f.recorder.presented.map(\.id), [partial.id, partial.id])
        XCTAssertEqual(f.captureSound.playCount, 1, "The shutter plays once per capture, not once per callback.")

        f.store.acceptPendingCapture()
        XCTAssertNil(f.store.pendingCapture)
        XCTAssertEqual(f.store.captures.map(\.accessibilityText), ["Hello"])
        XCTAssertEqual(f.store.statusNotice?.title, "Captured")
        XCTAssertEqual(f.store.page, .shelf)
        XCTAssertTrue(f.store.isExpanded)
    }

    @MainActor
    func testFailureReportsAnErrorAndReturnsToTheShelf() async throws {
        let f = makeFixture()
        defer { f.store.stop() }
        f.store.captureFrontmost()
        try await f.service.waitForCaptureRequest()
        f.service.fail(with: CaptureServiceError.nothingCaptured("Nothing could be captured."))
        try await waitUntil { !f.store.isCapturing }
        XCTAssertNil(f.store.pendingCapture)
        XCTAssertEqual(f.store.statusNotice?.kind, .error)
        XCTAssertEqual(f.store.statusNotice?.message, "Nothing could be captured.")
        XCTAssertEqual(f.store.page, .shelf)
        XCTAssertTrue(f.store.isExpanded)
        XCTAssertTrue(f.store.captures.isEmpty)
    }

    @MainActor
    func testMissingPermissionsRouteToSettingsWithoutCapturing() {
        let f = makeFixture()
        defer { f.store.stop() }
        f.service.permissions = PermissionStatus(accessibility: false, screenRecording: false)
        f.store.captureFrontmost()
        XCTAssertFalse(f.store.isCapturing)
        XCTAssertTrue(f.service.captureCalls.isEmpty)
        XCTAssertEqual(f.store.page, .settings)
        XCTAssertTrue(f.store.isExpanded)
        XCTAssertEqual(f.store.statusNotice?.kind, .info)
    }

    @MainActor
    func testWithoutAFrontmostAppTheShelfOpensWithAHint() {
        let f = makeFixture()
        defer { f.store.stop() }
        f.service.target = nil
        f.store.captureFrontmost()
        XCTAssertFalse(f.store.isCapturing)
        XCTAssertTrue(f.service.captureCalls.isEmpty)
        XCTAssertEqual(f.store.page, .shelf)
        XCTAssertTrue(f.store.isExpanded)
        XCTAssertEqual(f.store.statusNotice?.title, "Open an app")
    }

    @MainActor
    func testClearingHistoryCancelsTheCaptureAndFreesTheNextOne() async throws {
        let f = makeFixture()
        defer { f.store.stop() }
        f.store.captureFrontmost()
        try await f.service.waitForCaptureRequest()
        let partial = makeCapture()
        f.service.deliverPartial(partial)
        XCTAssertEqual(f.store.pendingCapture?.id, partial.id)

        f.store.clearHistory()
        XCTAssertFalse(f.store.isCapturing, "Clearing must not leave the store blocked behind abandoned work.")
        XCTAssertNil(f.store.pendingCapture)
        try await waitUntil { f.service.cancelledRequests == 1 }

        f.service.deliverPartial(partial)
        f.service.complete(with: partial)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertNil(f.store.pendingCapture, "A cancelled capture's late results are ignored.")
        XCTAssertTrue(f.store.captures.isEmpty)
        XCTAssertEqual(f.recorder.presented.count, 1)

        f.store.captureFrontmost()
        XCTAssertTrue(f.store.isCapturing)
        try await waitUntil { f.service.captureCalls.count == 2 }
    }

    @MainActor
    func testStoppingTheStoreCancelsTheCapture() async throws {
        let f = makeFixture()
        f.store.captureFrontmost()
        try await f.service.waitForCaptureRequest()
        f.store.stop()
        XCTAssertFalse(f.store.isCapturing)
        try await waitUntil { f.service.cancelledRequests == 1 }
    }

    private struct Fixture {
        let store: CaptureStore
        let service: CaptureServiceFake
        let recorder: PresentationRecorder
        let captureSound: CaptureSoundCounter
    }

    @MainActor
    private func makeFixture() -> Fixture {
        let (preferences, clipboard) = isolatedStoreDependencies()
        preferences.set(false, forKey: "collapseAfterCopy")
        let service = CaptureServiceFake()
        let sound = CaptureSoundCounter()
        let store = CaptureStore(preferences: preferences,
                                 landingPreviewDelay: .milliseconds(1),
                                 shelfPreparationDelay: .milliseconds(1),
                                 captureSound: sound,
                                 clipboard: clipboard,
                                 captureService: service)
        let recorder = PresentationRecorder()
        store.onPresentCard = { recorder.presented.append($0) }
        return Fixture(store: store, service: service, recorder: recorder, captureSound: sound)
    }

    private func makeCapture() -> CaptureResult {
        CaptureResult(appName: "Fake App", bundleIdentifier: "com.example.fake", windowTitle: "Window",
                      pngData: Data([0x89, 0x50, 0x4E, 0x47]))
    }

    @MainActor
    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<300 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw NSError(domain: "CaptureFrontmostTests", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for the capture store."])
    }
}

@MainActor
private final class CaptureServiceFake: CaptureServing {
    var target: CaptureTarget? = CaptureTarget(pid: 4242, appName: "Fake App", bundleIdentifier: "com.example.fake")
    var permissions = PermissionStatus(accessibility: true, screenRecording: true)
    private(set) var captureCalls: [CaptureTarget] = []
    private(set) var cancelledRequests = 0
    private var onScreenshot: ((CaptureResult) -> Void)?
    private var continuation: CheckedContinuation<CaptureResult, Error>?

    func frontmostTarget() -> CaptureTarget? { target }

    func permissionStatus() -> PermissionStatus { permissions }

    func capture(target: CaptureTarget, onScreenshot: ((CaptureResult) -> Void)?) async throws -> CaptureResult {
        captureCalls.append(target)
        self.onScreenshot = onScreenshot
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    self.cancelledRequests += 1
                    continuation.resume(throwing: CancellationError())
                } else {
                    self.continuation = continuation
                }
            }
        } onCancel: {
            Task { @MainActor in
                guard let continuation = self.continuation else { return }
                self.continuation = nil
                self.cancelledRequests += 1
                continuation.resume(throwing: CancellationError())
            }
        }
    }

    func waitForCaptureRequest() async throws {
        for _ in 0..<300 {
            if continuation != nil { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw NSError(domain: "CaptureServiceFake", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "The store never asked for a capture."])
    }

    func deliverPartial(_ result: CaptureResult) {
        onScreenshot?(result)
    }

    func complete(with result: CaptureResult) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: result)
    }

    func fail(with error: Error) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(throwing: error)
    }
}

@MainActor
private final class PresentationRecorder {
    var presented: [CaptureResult] = []
}

@MainActor
private final class CaptureSoundCounter: CaptureSoundPlaying {
    var playCount = 0
    func play() { playCount += 1 }
}
