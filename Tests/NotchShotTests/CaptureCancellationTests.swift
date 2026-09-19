// SPDX-License-Identifier: MIT
import CoreGraphics
import Foundation
import XCTest
@testable import NotchShot

final class CaptureCancellationTests: XCTestCase {
    func testDetachedWorkerReceivesParentCancellation() async {
        let started = expectation(description: "Detached worker started")
        let resume = DispatchSemaphore(value: 0)
        let observedCancellation = LockedFlag()
        let task = Task {
            try await CaptureWorker.run {
                started.fulfill()
                guard resume.wait(timeout: .now() + 3) == .success else {
                    throw TestError.timeout
                }
                observedCancellation.set(Task.isCancelled)
                return "late result"
            }
        }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        resume.signal()
        await assertCancelled(task)
        XCTAssertTrue(observedCancellation.value, "AX traversal must see cancellation in its own detached task.")
    }

    func testCancellationInvokesBlockingFrameworkCancellationHook() async {
        let started = expectation(description: "Blocking framework request started")
        let cancelRequest = expectation(description: "Framework cancel called")
        let resume = DispatchSemaphore(value: 0)
        let task = Task {
            try await CaptureWorker.run(onCancel: {
                cancelRequest.fulfill()
                resume.signal()
            }) {
                started.fulfill()
                guard resume.wait(timeout: .now() + 3) == .success else {
                    throw TestError.timeout
                }
                // Vision can report a framework error after VNRequest.cancel().
                throw TestError.frameworkCancelled
            } as String
        }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        await assertCancelled(task)
        await fulfillment(of: [cancelRequest], timeout: 2)
    }

    @MainActor
    func testAlreadyCancelledCaptureStartsNoStages() async {
        let entered = LockedFlag()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await CaptureService().captureContent(
                initial: fixture,
                readAccessibility: { entered.set(true); return AccessibilityReadResult() },
                screenshot: { entered.set(true); return nil },
                recognizeText: { _ in entered.set(true); return "text" },
                onScreenshot: { _ in entered.set(true) }
            )
        }
        await assertCancelled(task)
        XCTAssertFalse(entered.value)
    }

    @MainActor
    func testCancelledScreenshotDoesNotPublishPartialOrStartOCR() async {
        let started = expectation(description: "Screenshot request started")
        let gate = AsyncGate(started: started)
        let published = LockedFlag()
        let ocrStarted = LockedFlag()
        let image = makeImage()
        let task = Task {
            try await CaptureService().captureContent(
                initial: fixture,
                readAccessibility: { AccessibilityReadResult() },
                screenshot: {
                    await gate.wait()
                    return (image, .zero) // ScreenCaptureKit may finish after cancellation.
                },
                recognizeText: { _ in ocrStarted.set(true); return "text" },
                onScreenshot: { _ in published.set(true) }
            )
        }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        await gate.release()
        await assertCancelled(task)
        XCTAssertFalse(published.value)
        XCTAssertFalse(ocrStarted.value)
    }

    @MainActor
    func testCancelledAccessibilityDoesNotStartFallbackOCR() async {
        let started = expectation(description: "AX request started")
        let gate = AsyncGate(started: started)
        let ocrStarted = LockedFlag()
        let image = makeImage()
        let task = Task {
            try await CaptureService().captureContent(
                initial: fixture,
                readAccessibility: {
                    await gate.wait()
                    return AccessibilityReadResult()
                },
                screenshot: { (image, .zero) },
                recognizeText: { _ in ocrStarted.set(true); return "text" }
            )
        }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        await gate.release()
        await assertCancelled(task)
        XCTAssertFalse(ocrStarted.value)
    }

    @MainActor
    func testCancelledOCRDoesNotReturnCompletedCapture() async {
        let started = expectation(description: "OCR request started")
        let gate = AsyncGate(started: started)
        let image = makeImage()
        let task = Task {
            try await CaptureService().captureContent(
                initial: fixture,
                readAccessibility: { AccessibilityReadResult() },
                screenshot: { (image, .zero) },
                recognizeText: { _ in
                    await gate.wait()
                    return "late recognized text"
                }
            )
        }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        await gate.release()
        await assertCancelled(task)
    }

    @MainActor
    func testOrdinaryScreenshotFailureStillReturnsAccessibility() async throws {
        let result = try await CaptureService().captureContent(
            initial: fixture,
            readAccessibility: {
                AccessibilityReadResult(tree: [AXNode(id: 1, role: "AXWindow", roleDescription: "window")], text: "Visible content")
            },
            screenshot: { throw TestError.screenshotUnavailable },
            recognizeText: { _ in XCTFail("No image to recognize"); return "" }
        )
        XCTAssertEqual(result.accessibilityText, "Visible content")
        XCTAssertTrue(result.warnings.contains { $0.hasPrefix("Screenshot unavailable:") })
    }

    private var fixture: CaptureResult {
        CaptureResult(appName: "QA", bundleIdentifier: "test.notchshot.capture", windowTitle: "Cancellation fixture")
    }

    private func makeImage() -> CGImage {
        CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
    }

    private func assertCancelled<Value>(_ task: Task<Value, Error>, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await task.value
            XCTFail("A cancelled capture must not return a result", file: file, line: line)
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, received \(error)", file: file, line: line)
        }
    }

    private enum TestError: Error { case timeout, frameworkCancelled, screenshotUnavailable }

    private final class LockedFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = false
        var value: Bool { lock.withLock { storage } }
        func set(_ value: Bool) { lock.withLock { storage = value } }
    }

    /// Deliberately does not cooperate with cancellation, like an in-flight OS
    /// call; the production boundary must discard its eventual return value.
    private actor AsyncGate {
        let started: XCTestExpectation
        private var continuation: CheckedContinuation<Void, Never>?
        private var released = false
        init(started: XCTestExpectation) { self.started = started }
        func wait() async {
            if released { return }
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                started.fulfill()
            }
        }
        func release() {
            released = true
            continuation?.resume()
            continuation = nil
        }
    }
}
