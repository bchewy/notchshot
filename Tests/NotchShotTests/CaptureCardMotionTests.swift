// SPDX-License-Identifier: MIT
import AppKit
import XCTest
@testable import NotchShot

final class CaptureCardMotionTests: XCTestCase {
    @MainActor
    func testScreenshotEntranceStartsAtCapturedWindowAndEndsAtCenteredPreview() async throws {
        let (store, controller, window) = try makeHiddenCard()
        defer { controller.dismiss(); window.close(); store.stop() }
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let source = CGRect(x: screen.frame.minX + 80, y: 80, width: 800, height: 500)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 20,
                                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let pixelColor = try XCTUnwrap(NSColor.systemTeal.usingColorSpace(.deviceRGB))
        for y in 0..<20 { for x in 0..<32 { bitmap.setColor(pixelColor, atX: x, y: y) } }
        var capture = makeCapture()
        capture.pngData = bitmap.representation(using: .png, properties: [:])
        capture.sourceWindowFrame = source
        store.pendingCapture = capture
        controller.present(capture)
        let sourceNative = CaptureCardGeometry.appKitFrame(fromCGFrame: source, mainDisplayTop: screen.frame.maxY)
        XCTAssertEqual(window.frame, sourceNative)
        let canvas = try XCTUnwrap(window.contentView as? CaptureCardTransitionView)
        XCTAssertNotNil(canvas.cardImage, "The full card must rasterize before its native window changes size.")
        XCTAssertNotNil(canvas.screenshot)
        try await waitForMotion { window.frame.width < source.width - 2 }
        XCTAssertGreaterThan(window.frame.width, 268)
        try await waitForMotion { !controller.isAnimating }
        XCTAssertEqual(window.frame.width, 268)
        XCTAssertEqual(window.frame.midX, sourceNative.midX, accuracy: 0.5)
        XCTAssertEqual(window.frame.midY, sourceNative.midY, accuracy: 0.5)
    }

    func testScreenshotPeelsIntoCardThenShrinksToShelfWithoutFadingAway() {
        let source = CGRect(x: 50, y: 80, width: 1200, height: 750)
        let preview = CGRect(x: 510, y: 345, width: 268, height: 218)
        let slot = CGRect(x: 560, y: 806, width: 70, height: 36)
        XCTAssertEqual(CaptureCardMotion.entrance(from: source, to: preview, progress: 0).frame, source)
        XCTAssertGreaterThan(CaptureCardMotion.entrance(from: source, to: preview, progress: 0.13).flash, 0)
        let peel = CaptureCardMotion.entrance(from: source, to: preview, progress: 0.5)
        XCTAssertLessThan(peel.frame.width, source.width)
        XCTAssertGreaterThan(peel.frame.width, preview.width)
        XCTAssertEqual(CaptureCardMotion.entrance(from: source, to: preview, progress: 1).frame, preview)
        var previousWidth = preview.width
        for step in 0...100 {
            let sample = CaptureCardMotion.flight(from: preview, to: slot, progress: CGFloat(step) / 100)
            XCTAssertLessThanOrEqual(sample.frame.width, previousWidth)
            XCTAssertGreaterThanOrEqual(sample.frame.width, slot.width)
            XCTAssertGreaterThanOrEqual(sample.frame.height, slot.height)
            XCTAssertEqual(sample.alpha, 1, "The screenshot must remain visible throughout its flight.")
            previousWidth = sample.frame.width
        }
        XCTAssertEqual(CaptureCardMotion.flight(from: preview, to: slot, progress: 1).frame, slot)
    }

    @MainActor
    func testSameCaptureUpdatePreservesEntranceAndMeasuredLandingCompletesOnce() async throws {
        let (store, controller, window) = try makeHiddenCard()
        defer { controller.dismiss(); window.close(); store.stop() }
        var capture = makeCapture()
        store.pendingCapture = capture
        controller.present(capture)
        XCTAssertTrue(controller.isAnimating)
        XCTAssertEqual(window.alphaValue, 0)
        XCTAssertEqual(window.animationBehavior, .none)
        let initialFrame = window.frame
        capture.accessibilityText = "The final accessibility text"
        controller.present(capture)
        XCTAssertEqual(window.alphaValue, 0)
        XCTAssertEqual(window.frame, initialFrame)
        try await waitForMotion { window.frame.width > initialFrame.width }
        let intermediateFrame = window.frame
        let intermediateAlpha = window.alphaValue
        controller.present(capture)
        XCTAssertEqual(window.frame, intermediateFrame)
        XCTAssertEqual(window.alphaValue, intermediateAlpha)
        try await waitForMotion { !controller.isAnimating }
        XCTAssertEqual(window.alphaValue, 1)
        XCTAssertEqual(window.frame.width, 268)
        let preview = window.frame
        let destination = CGRect(x: preview.midX - 170, y: preview.maxY + 110, width: 70, height: 36)
        store.isLandingCapture = true
        store.reportShelfLandingFrame(destination, captureID: capture.id, owner: UUID())
        var completions = 0
        controller.landInShelf { completions += 1 }
        try await waitForMotion { window.frame.width < preview.width - 1 }
        XCTAssertEqual(window.alphaValue, 1)
        let flightFrame = window.frame
        controller.present(capture)
        XCTAssertEqual(window.frame, flightFrame)
        XCTAssertTrue(controller.isAnimating)
        try await waitForMotion { completions == 1 && !controller.isAnimating }
        XCTAssertEqual(window.frame.minX, destination.minX, accuracy: 0.5)
        XCTAssertEqual(window.frame.minY, destination.minY, accuracy: 0.5)
        XCTAssertEqual(window.frame.size, destination.size)
        XCTAssertFalse(window.isVisible, "Native regression tests must never present UI.")
        XCTAssertEqual(completions, 1)
    }

    @MainActor
    func testDismissAndReplacementCancelPreviousLandingCompletions() async throws {
        let (store, controller, window) = try makeHiddenCard()
        defer { controller.dismiss(); window.close(); store.stop() }
        var completions = 0
        func presentWithTarget() {
            let capture = makeCapture()
            store.pendingCapture = capture
            controller.present(capture)
            store.isLandingCapture = true
            store.reportShelfLandingFrame(CGRect(x: 560, y: 800, width: 70, height: 36), captureID: capture.id, owner: UUID())
        }
        presentWithTarget()
        controller.landInShelf { completions += 1 }
        XCTAssertTrue(controller.isAnimating)
        controller.dismiss()
        XCTAssertFalse(controller.isAnimating)
        presentWithTarget()
        controller.landInShelf { completions += 1 }
        presentWithTarget()
        try await waitForMotion { !controller.isAnimating }
        XCTAssertEqual(completions, 0)
        controller.landInShelf { completions += 1 }
        try await waitForMotion { completions == 1 && !controller.isAnimating }
        XCTAssertFalse(window.isVisible)
    }

    @MainActor
    func testMissingTargetAndReducedMotionStillCollectWithoutSpatialFlight() async throws {
        var reduced = false
        let (store, controller, window) = try makeHiddenCard(reduceMotion: { reduced })
        defer { controller.dismiss(); window.close(); store.stop() }
        let capture = makeCapture()
        store.pendingCapture = capture
        controller.present(capture)
        var completions = 0
        controller.landInShelf { completions += 1 }
        XCTAssertEqual(completions, 1)
        XCTAssertFalse(controller.isAnimating)
        reduced = true
        controller.present(capture)
        XCTAssertFalse(controller.isAnimating)
        XCTAssertEqual(window.alphaValue, 1)
        store.isLandingCapture = true
        store.reportShelfLandingFrame(CGRect(x: 560, y: 800, width: 70, height: 36), captureID: capture.id, owner: UUID())
        controller.landInShelf { completions += 1 }
        XCTAssertEqual(completions, 2)
        XCTAssertFalse(controller.isAnimating)
    }

    @MainActor
    func testReduceMotionEnabledMidFlightSettlesAndCollects() async throws {
        var reduced = false
        let (store, controller, window) = try makeHiddenCard(reduceMotion: { reduced })
        defer { controller.dismiss(); window.close(); store.stop() }
        let capture = makeCapture()
        store.pendingCapture = capture
        controller.present(capture)
        try await waitForMotion { !controller.isAnimating }
        store.isLandingCapture = true
        let slot = CGRect(x: 560, y: 800, width: 70, height: 36)
        store.reportShelfLandingFrame(slot, captureID: capture.id, owner: UUID())
        var completions = 0
        controller.landInShelf { completions += 1 }
        reduced = true
        try await waitForMotion { completions == 1 && !controller.isAnimating }
        XCTAssertEqual(window.frame.size, slot.size)
    }

    @MainActor
    private func makeHiddenCard(reduceMotion: @escaping () -> Bool = { false }) throws -> (CaptureStore, CaptureCardController, NSWindow) {
        _ = NSApplication.shared
        guard NotchGeometry.preferredScreen != nil else { throw XCTSkip("Requires WindowServer display access.") }
        let previousWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
        let (preferences, clipboard) = isolatedStoreDependencies()
        let store = CaptureStore(preferences: preferences, clipboard: clipboard)
        let controller = CaptureCardController(store: store, presentsWindow: false, reduceMotion: reduceMotion)
        let window = try XCTUnwrap(NSApp.windows.first {
            !previousWindows.contains(ObjectIdentifier($0)) && $0.title == "NotchShot capture preview"
        })
        XCTAssertFalse(window.isVisible)
        return (store, controller, window)
    }

    private func makeCapture() -> CaptureResult {
        CaptureResult(appName: "Motion Test", bundleIdentifier: "com.example.motion-test", windowTitle: "Preview", pngData: nil)
    }

    @MainActor
    private func waitForMotion(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<300 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw NSError(domain: "CaptureCardMotionTests", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Card motion did not settle within 1.5 seconds."])
    }
}
