// SPDX-License-Identifier: MIT
import AppKit
import XCTest
@testable import NotchShot

final class AssistedPasteTests: XCTestCase {
    @MainActor
    func testOnePasteSendsImageThenExactContextAndRestoresRichClipboard() async throws {
        let fixture = try makeFixture()
        let original = fixture.clipboard.pasteboardItems!.first!
        let originalRTFD = original.data(forType: .rtfd)
        XCTAssertTrue(fixture.arm())
        XCTAssertTrue(fixture.service.isArmed)
        XCTAssertEqual(fixture.clipboard.string(forType: .string), fixture.capture.clipboardText)

        XCTAssertTrue(fixture.emit(.paste(isRepeat: false)))
        try await waitUntil { fixture.environment.posts.count == 1 && fixture.sleep.contains(AssistedPasteFixture.imageDelay) }
        XCTAssertTrue(fixture.service.isPasting)
        XCTAssertEqual(fixture.environment.posts[0].png, fixture.capture.pngData)
        XCTAssertNil(fixture.environment.posts[0].text, "The first paste must offer an image without a competing text representation.")
        XCTAssertNil(fixture.environment.posts[0].rtfd)
        XCTAssertEqual(fixture.environment.posts[0].target, fixture.environment.target)

        try await fixture.advanceImageDelay()
        XCTAssertEqual(fixture.environment.posts.count, 2)
        XCTAssertNil(fixture.environment.posts[1].png)
        XCTAssertEqual(fixture.environment.posts[1].text, fixture.capture.clipboardText)
        XCTAssertEqual(fixture.environment.posts[1].text, CapturedContext.opening
                       + "\nWindow: \"Fixture window\", App: Assisted paste fixture.\nbutton Complete tree\n"
                       + CapturedContext.closing)
        XCTAssertEqual(fixture.environment.posts[1].target, fixture.environment.posts[0].target)

        try await fixture.advanceRestoreDelay()
        XCTAssertFalse(fixture.service.isArmed)
        XCTAssertFalse(fixture.service.isPasting)
        XCTAssertEqual(fixture.clipboard.data(forType: .rtfd), originalRTFD)
        XCTAssertEqual(fixture.clipboard.data(forType: .png), fixture.capture.pngData)
        XCTAssertEqual(fixture.clipboard.string(forType: .string), fixture.capture.clipboardText)
        XCTAssertFalse(fixture.emit(.paste(isRepeat: false)), "Assistance consumes only the next paste after copying a shot.")
        XCTAssertEqual(fixture.environment.posts.count, 2)
    }

    @MainActor
    func testMissingFrontmostAppOrPermissionPassesThroughWithoutChangingClipboard() throws {
        for invalidCase in 0..<2 {
            let fixture = try makeFixture()
            XCTAssertTrue(fixture.arm())
            if invalidCase == 0 { fixture.environment.frontmostProcessIdentifier = nil }
            else { fixture.environment.isAccessibilityTrusted = false }
            let changeCount = fixture.clipboard.changeCount

            XCTAssertFalse(fixture.emit(.paste(isRepeat: false)))

            XCTAssertEqual(fixture.clipboard.changeCount, changeCount)
            XCTAssertEqual(fixture.clipboard.string(forType: .string), fixture.capture.clipboardText)
            XCTAssertTrue(fixture.environment.posts.isEmpty)
            XCTAssertFalse(fixture.service.isPasting)
        }
    }

    @MainActor
    func testNativeCallbackReservesPasteBeforeAnyTargetLookupOrClipboardWrite() async throws {
        let fixture = try makeFixture()
        XCTAssertTrue(fixture.arm())
        let changeCount = fixture.clipboard.changeCount

        XCTAssertTrue(fixture.emit(.paste(isRepeat: false)))

        XCTAssertTrue(fixture.service.isPasting)
        XCTAssertEqual(fixture.environment.targetReadCount, 0, "AX preflight must occur after returning from the event callback.")
        XCTAssertTrue(fixture.environment.posts.isEmpty)
        XCTAssertEqual(fixture.clipboard.changeCount, changeCount)
        try await waitUntil { fixture.environment.posts.count == 1 && fixture.sleep.contains(AssistedPasteFixture.imageDelay) }
        XCTAssertGreaterThan(fixture.environment.targetReadCount, 0)
    }

    @MainActor
    func testUnavailableInitialAXTargetReplaysOneNormalPasteWithUntouchedRichClipboard() async throws {
        let fixture = try makeFixture()
        XCTAssertTrue(fixture.arm())
        fixture.environment.target = nil
        let changeCount = fixture.clipboard.changeCount

        XCTAssertTrue(fixture.emit(.paste(isRepeat: false)))
        try await waitUntil { !fixture.service.isPasting }

        XCTAssertTrue(fixture.environment.posts.isEmpty)
        XCTAssertEqual(fixture.environment.fallbacks.map(\.processIdentifier), [42])
        XCTAssertEqual(fixture.environment.fallbacks.first?.text, fixture.capture.clipboardText)
        XCTAssertEqual(fixture.environment.fallbacks.first?.png, fixture.capture.pngData)
        XCTAssertNotNil(fixture.environment.fallbacks.first?.rtfd)
        XCTAssertEqual(fixture.clipboard.changeCount, changeCount)
        XCTAssertFalse(fixture.service.isArmed)
    }

    @MainActor
    func testInterveningInputDuringPreparationCancelsWithoutPostingOrWriting() async throws {
        for event in [AssistedPasteEvent.keyDown, .pointerDown] {
            let fixture = try makeFixture()
            XCTAssertTrue(fixture.arm())
            let changeCount = fixture.clipboard.changeCount

            XCTAssertTrue(fixture.emit(.paste(isRepeat: false)))
            XCTAssertFalse(fixture.emit(event))
            try await Task.sleep(for: .milliseconds(2))

            XCTAssertTrue(fixture.environment.posts.isEmpty)
            XCTAssertTrue(fixture.environment.fallbacks.isEmpty)
            XCTAssertEqual(fixture.clipboard.changeCount, changeCount)
            XCTAssertFalse(fixture.service.isArmed)
            XCTAssertFalse(fixture.service.isPasting)
        }
    }

    @MainActor
    func testPreparationWillNotReplayIntoChangedAppOrOverwriteNewClipboard() async throws {
        for changedCase in 0..<3 {
            let fixture = try makeFixture()
            XCTAssertTrue(fixture.arm())
            fixture.environment.target = nil
            XCTAssertTrue(fixture.emit(.paste(isRepeat: false)))
            if changedCase == 0 { fixture.environment.frontmostProcessIdentifier = 43 }
            else if changedCase == 1 { fixture.copyUnrelatedText("New copy during preflight") }
            else { fixture.environment.isAccessibilityTrusted = false }
            let changeCount = fixture.clipboard.changeCount

            try await waitUntil { !fixture.service.isPasting }

            XCTAssertTrue(fixture.environment.posts.isEmpty)
            XCTAssertTrue(fixture.environment.fallbacks.isEmpty)
            XCTAssertEqual(fixture.clipboard.changeCount, changeCount)
            XCTAssertFalse(fixture.service.isArmed)
        }
    }

    @MainActor
    func testSuspendedAXQueryCannotResumeAfterUserInputOrClipboardChange() async throws {
        for changedCase in 0..<3 {
            let fixture = try makeFixture()
            XCTAssertTrue(fixture.arm())
            fixture.environment.suspendNextTargetQuery = true
            XCTAssertTrue(fixture.emit(.paste(isRepeat: false)))
            try await waitUntil { fixture.environment.hasPendingTargetQuery }
            if changedCase == 0 { XCTAssertFalse(fixture.emit(.pointerDown)) }
            else if changedCase == 1 { fixture.copyUnrelatedText("New clipboard while AX query is waiting") }
            else { fixture.environment.frontmostProcessIdentifier = 43 }
            let changeCount = fixture.clipboard.changeCount

            fixture.environment.resumeTargetQueries()
            try await waitUntil { !fixture.service.isPasting }

            XCTAssertTrue(fixture.environment.posts.isEmpty)
            XCTAssertTrue(fixture.environment.fallbacks.isEmpty)
            XCTAssertEqual(fixture.clipboard.changeCount, changeCount)
            XCTAssertFalse(fixture.service.isArmed)
        }
    }

    @MainActor
    func testChangingClipboardBeforePastePassesThroughUserContent() throws {
        let fixture = try makeFixture()
        XCTAssertTrue(fixture.arm())
        fixture.copyUnrelatedText("A later copy from another app")
        let changeCount = fixture.clipboard.changeCount

        XCTAssertFalse(fixture.emit(.paste(isRepeat: false)))

        XCTAssertEqual(fixture.clipboard.changeCount, changeCount)
        XCTAssertEqual(fixture.clipboard.string(forType: .string), "A later copy from another app")
        XCTAssertTrue(fixture.environment.posts.isEmpty)
        XCTAssertFalse(fixture.service.isArmed)
    }

    @MainActor
    func testExpiredArmPassesThroughWithoutRewritingClipboard() throws {
        let fixture = try makeFixture()
        XCTAssertTrue(fixture.arm())
        fixture.clock.now.addTimeInterval(121)
        let changeCount = fixture.clipboard.changeCount

        XCTAssertFalse(fixture.emit(.paste(isRepeat: false)))

        XCTAssertEqual(fixture.clipboard.changeCount, changeCount)
        XCTAssertTrue(fixture.environment.posts.isEmpty)
        XCTAssertFalse(fixture.service.isArmed)
    }

    @MainActor
    func testMonitoringFailureKeepsNormalRichClipboardPasteAvailable() throws {
        let fixture = try makeFixture()
        fixture.environment.canStartMonitoring = false
        let changeCount = fixture.clipboard.changeCount

        XCTAssertFalse(fixture.arm())

        XCTAssertFalse(fixture.service.isArmed)
        XCTAssertFalse(fixture.service.isPasting)
        XCTAssertEqual(fixture.clipboard.changeCount, changeCount)
        XCTAssertNotNil(fixture.clipboard.data(forType: .rtfd))
        XCTAssertEqual(fixture.clipboard.string(forType: .string), fixture.capture.clipboardText)
        XCTAssertTrue(fixture.environment.posts.isEmpty)
    }

    @MainActor
    func testTextOnlyCorruptOrMismatchedShotsCannotArmAssistance() throws {
        for invalidCase in 0..<3 {
            let fixture = try makeFixture()
            var invalidCapture = fixture.capture
            if invalidCase == 0 { invalidCapture.pngData = nil }
            else if invalidCase == 1 { invalidCapture.pngData = Data("broken image".utf8) }
            else { invalidCapture.axTree[0].title = "This capture does not match the copied shot" }
            let changeCount = fixture.clipboard.changeCount

            XCTAssertFalse(fixture.service.arm(capture: invalidCapture, clipboard: fixture.clipboard))

            XCTAssertEqual(fixture.clipboard.changeCount, changeCount)
            XCTAssertFalse(fixture.service.isArmed)
            XCTAssertEqual(fixture.environment.startCount, 0)
            XCTAssertTrue(fixture.environment.posts.isEmpty)
        }
    }

    @MainActor
    func testOrdinaryInputBeforePasteLetsUserChooseDestinationWithoutDisarming() throws {
        let fixture = try makeFixture()
        XCTAssertTrue(fixture.arm())
        let changeCount = fixture.clipboard.changeCount

        XCTAssertFalse(fixture.emit(.pointerDown))
        XCTAssertFalse(fixture.emit(.keyDown))

        XCTAssertTrue(fixture.service.isArmed)
        XCTAssertFalse(fixture.service.isPasting)
        XCTAssertEqual(fixture.clipboard.changeCount, changeCount)
        XCTAssertTrue(fixture.environment.posts.isEmpty)
    }

    @MainActor
    func testUnrelatedClipboardChangeBetweenImageAndTextAbortsWithoutOverwriting() async throws {
        let fixture = try makeFixture()
        XCTAssertTrue(fixture.arm())
        XCTAssertTrue(fixture.emit(.paste(isRepeat: false)))
        try await waitUntil { fixture.environment.posts.count == 1 && fixture.sleep.contains(AssistedPasteFixture.imageDelay) }
        fixture.copyUnrelatedText("Keep this new clipboard content")
        let changeCount = fixture.clipboard.changeCount

        try await fixture.advanceImageDelay(expectSecondPost: false)

        XCTAssertEqual(fixture.environment.posts.count, 1)
        XCTAssertEqual(fixture.clipboard.changeCount, changeCount)
        XCTAssertEqual(fixture.clipboard.string(forType: .string), "Keep this new clipboard content")
        XCTAssertFalse(fixture.service.isPasting)
        XCTAssertFalse(fixture.service.isArmed)
    }

    @MainActor
    func testAppWindowOrFocusedControlChangePreventsSecondPaste() async throws {
        let targets: [AssistedPasteTarget] = [
            .init(processIdentifier: 43, focusIdentity: "window-A/control-A"),
            .init(processIdentifier: 42, focusIdentity: "window-B/control-A"),
            .init(processIdentifier: 42, focusIdentity: "window-A/control-B")
        ]
        for target in targets {
            let fixture = try makeFixture()
            XCTAssertTrue(fixture.arm())
            XCTAssertTrue(fixture.emit(.paste(isRepeat: false)))
            try await waitUntil { fixture.environment.posts.count == 1 && fixture.sleep.contains(AssistedPasteFixture.imageDelay) }
            fixture.environment.target = target

            try await fixture.advanceImageDelay(expectSecondPost: false)

            XCTAssertEqual(fixture.environment.posts.count, 1)
            XCTAssertFalse(fixture.service.isPasting)
            XCTAssertFalse(fixture.service.isArmed)
        }
    }

    @MainActor
    func testUserKeyboardOrPointerInputCancelsPendingTextPaste() async throws {
        for event in [AssistedPasteEvent.keyDown, .pointerDown] {
            let fixture = try makeFixture()
            XCTAssertTrue(fixture.arm())
            XCTAssertTrue(fixture.emit(.paste(isRepeat: false)))
            try await waitUntil { fixture.environment.posts.count == 1 && fixture.sleep.contains(AssistedPasteFixture.imageDelay) }

            XCTAssertFalse(fixture.emit(event), "The user's intervening input must not be swallowed.")
            try await fixture.advanceImageDelay(expectSecondPost: false)

            XCTAssertEqual(fixture.environment.posts.count, 1)
            XCTAssertFalse(fixture.service.isPasting)
            XCTAssertFalse(fixture.service.isArmed)
        }
    }

    @MainActor
    func testCancellationCallbackDefersRestorationAndRespectsInterveningCopy() async throws {
        for hasNewCopy in [false, true] {
            let fixture = try makeFixture()
            XCTAssertTrue(fixture.arm())
            XCTAssertTrue(fixture.emit(.paste(isRepeat: false)))
            try await waitUntil { fixture.environment.posts.count == 1 && fixture.sleep.contains(AssistedPasteFixture.imageDelay) }
            let stagedChangeCount = fixture.clipboard.changeCount

            XCTAssertFalse(fixture.emit(.pointerDown))

            XCTAssertFalse(fixture.service.isPasting)
            XCTAssertEqual(fixture.clipboard.changeCount, stagedChangeCount,
                           "Cancellation must invalidate the sequence immediately and defer large clipboard restoration until after the event callback.")
            if hasNewCopy { fixture.copyUnrelatedText("New content before deferred cleanup") }
            let expectedText = hasNewCopy ? "New content before deferred cleanup" : fixture.capture.clipboardText
            let latestChangeCount = fixture.clipboard.changeCount
            try await fixture.advanceImageDelay(expectSecondPost: false)
            try await waitUntil { fixture.clipboard.string(forType: .string) == expectedText }

            XCTAssertEqual(fixture.environment.posts.count, 1)
            if hasNewCopy { XCTAssertEqual(fixture.clipboard.changeCount, latestChangeCount) }
            else { XCTAssertEqual(fixture.clipboard.data(forType: .png), fixture.capture.pngData) }
        }
    }

    @MainActor
    func testPermissionRevocationOrUnavailableMonitorCancelsPendingTextPaste() async throws {
        for monitorUnavailable in [false, true] {
            let fixture = try makeFixture()
            XCTAssertTrue(fixture.arm())
            XCTAssertTrue(fixture.emit(.paste(isRepeat: false)))
            try await waitUntil { fixture.environment.posts.count == 1 && fixture.sleep.contains(AssistedPasteFixture.imageDelay) }
            if monitorUnavailable { XCTAssertFalse(fixture.emit(.unavailable)) }
            else { fixture.environment.isAccessibilityTrusted = false }

            try await fixture.advanceImageDelay(expectSecondPost: false)

            XCTAssertEqual(fixture.environment.posts.count, 1)
            XCTAssertFalse(fixture.service.isPasting)
            XCTAssertFalse(fixture.service.isArmed)
        }
    }

    @MainActor
    func testUserCopyAfterTextPasteSurvivesDelayedClipboardRestoration() async throws {
        let fixture = try makeFixture()
        XCTAssertTrue(fixture.arm())
        XCTAssertTrue(fixture.emit(.paste(isRepeat: false)))
        try await waitUntil { fixture.environment.posts.count == 1 && fixture.sleep.contains(AssistedPasteFixture.imageDelay) }
        try await fixture.advanceImageDelay()
        fixture.copyUnrelatedText("New content copied after both paste events")
        let changeCount = fixture.clipboard.changeCount

        try await fixture.advanceRestoreDelay()

        XCTAssertEqual(fixture.environment.posts.count, 2)
        XCTAssertEqual(fixture.clipboard.changeCount, changeCount)
        XCTAssertEqual(fixture.clipboard.string(forType: .string), "New content copied after both paste events")
        XCTAssertFalse(fixture.service.isPasting)
        XCTAssertFalse(fixture.service.isArmed)
    }

    @MainActor
    func testCancelAndStopInvalidateSleepingSequenceAndSavedEventCallback() async throws {
        for shouldStop in [false, true] {
            let fixture = try makeFixture()
            XCTAssertTrue(fixture.arm())
            let oldHandler = fixture.environment.onEvent
            XCTAssertTrue(fixture.emit(.paste(isRepeat: false)))
            try await waitUntil { fixture.environment.posts.count == 1 && fixture.sleep.contains(AssistedPasteFixture.imageDelay) }

            if shouldStop { fixture.service.stop() }
            else { fixture.service.cancel() }
            try await fixture.advanceImageDelay(expectSecondPost: false)

            XCTAssertEqual(fixture.environment.posts.count, 1)
            XCTAssertFalse(fixture.service.isPasting)
            XCTAssertFalse(fixture.service.isArmed)
            XCTAssertFalse(oldHandler?(.paste(isRepeat: false)) ?? false)
        }
    }

    @MainActor
    func testRepeatedPasteDuringSequenceCannotStartAnotherSequence() async throws {
        let fixture = try makeFixture()
        XCTAssertTrue(fixture.arm())
        XCTAssertTrue(fixture.emit(.paste(isRepeat: false)))
        try await waitUntil { fixture.environment.posts.count == 1 && fixture.sleep.contains(AssistedPasteFixture.imageDelay) }

        XCTAssertFalse(fixture.emit(.paste(isRepeat: true)))
        XCTAssertFalse(fixture.emit(.paste(isRepeat: false)))
        try await fixture.advanceImageDelay(expectSecondPost: false)
        fixture.sleep.resumeAll()
        await Task.yield()

        XCTAssertEqual(fixture.environment.posts.count, 1, "Held or repeated paste must cancel pending text and never launch a duplicate pair.")
        XCTAssertEqual(fixture.environment.posts.filter { $0.png != nil }.count, 1)
        XCTAssertFalse(fixture.service.isArmed)
        XCTAssertFalse(fixture.service.isPasting)
    }

    @MainActor
    func testNewShotArmCannotBeOverwrittenByAnOlderCancelledSequence() async throws {
        let fixture = try makeFixture()
        XCTAssertTrue(fixture.arm())
        XCTAssertTrue(fixture.emit(.paste(isRepeat: false)))
        try await waitUntil { fixture.environment.posts.count == 1 && fixture.sleep.contains(AssistedPasteFixture.imageDelay) }
        var newCapture = fixture.capture
        newCapture.id = UUID()
        newCapture.accessibilityText = "This new shot must remain on the clipboard"
        fixture.clipboard.clearContents()
        XCTAssertTrue(fixture.clipboard.writeObjects([CaptureClipboardService.makeItem(for: newCapture)]))
        XCTAssertTrue(fixture.service.arm(capture: newCapture, clipboard: fixture.clipboard))
        let newChangeCount = fixture.clipboard.changeCount

        try await fixture.advanceImageDelay(expectSecondPost: false)

        XCTAssertEqual(fixture.environment.posts.count, 1)
        XCTAssertEqual(fixture.clipboard.changeCount, newChangeCount)
        XCTAssertEqual(fixture.clipboard.string(forType: .string), newCapture.clipboardText)
        XCTAssertTrue(fixture.service.isArmed)
        XCTAssertFalse(fixture.service.isPasting)
    }

    @MainActor
    func testFailedPastePostingStopsBeforeSendingAnyFurtherPhase() async throws {
        for failedPhase in [1, 2] {
            let fixture = try makeFixture()
            fixture.environment.failPostNumber = failedPhase
            XCTAssertTrue(fixture.arm())
            XCTAssertTrue(fixture.emit(.paste(isRepeat: false)))
            try await waitUntil { fixture.environment.posts.count == 1 }
            if failedPhase == 2 { try await fixture.advanceImageDelay() }
            try await waitUntil { !fixture.service.isPasting }
            fixture.sleep.resumeAll()
            await Task.yield()

            XCTAssertEqual(fixture.environment.posts.count, failedPhase)
            XCTAssertFalse(fixture.service.isArmed)
            XCTAssertEqual(fixture.clipboard.data(forType: .png), fixture.capture.pngData)
            XCTAssertEqual(fixture.clipboard.string(forType: .string), fixture.capture.clipboardText)
        }
    }

    @MainActor
    func testImmediateAbortRestorationFailureReportsOnlyFailure() async throws {
        let fixture = try makeFixture()
        XCTAssertTrue(fixture.arm())
        XCTAssertTrue(fixture.emit(.paste(isRepeat: false)))
        try await waitUntil { fixture.sleep.contains(AssistedPasteFixture.imageDelay) }
        fixture.writer.failWriteNumber = 2
        fixture.environment.target = .init(processIdentifier: 42, focusIdentity: "a different control")

        try await fixture.advanceImageDelay(expectSecondPost: false)
        try await waitUntil { !fixture.results.isEmpty }

        XCTAssertEqual(fixture.results, [.failed("Could not restore the rich shot. Copy the shot again to retry.")])
        XCTAssertEqual(fixture.writer.writeCount, 2)
        XCTAssertFalse(fixture.service.isPasting)
        XCTAssertEqual(fixture.environment.posts.count, 1)
    }

    @MainActor
    func testDeferredAbortRestorationFailureReportsOnlyFailureAfterCallback() async throws {
        let fixture = try makeFixture()
        XCTAssertTrue(fixture.arm())
        XCTAssertTrue(fixture.emit(.paste(isRepeat: false)))
        try await waitUntil { fixture.sleep.contains(AssistedPasteFixture.imageDelay) }
        fixture.writer.failWriteNumber = 2
        let stagedChangeCount = fixture.clipboard.changeCount

        XCTAssertFalse(fixture.emit(.pointerDown))
        XCTAssertTrue(fixture.results.isEmpty, "The cancellation notice must wait for the restoration outcome.")
        XCTAssertEqual(fixture.writer.writeCount, 1, "Do not write from the native event callback.")
        XCTAssertEqual(fixture.clipboard.changeCount, stagedChangeCount)
        try await waitUntil { !fixture.results.isEmpty }

        XCTAssertEqual(fixture.results, [.failed("Could not restore the rich shot. Copy the shot again to retry.")])
        XCTAssertEqual(fixture.writer.writeCount, 2)
        XCTAssertFalse(fixture.service.isPasting)
        fixture.sleep.resumeAll()
        await Task.yield()
        XCTAssertEqual(fixture.results.count, 1, "The invalidated sequence must not also report cancellation.")
    }

    @MainActor
    func testCancelRestorationFailureReportsFailure() async throws {
        let fixture = try makeFixture()
        XCTAssertTrue(fixture.arm())
        XCTAssertTrue(fixture.emit(.paste(isRepeat: false)))
        try await waitUntil { fixture.sleep.contains(AssistedPasteFixture.imageDelay) }
        fixture.writer.failWriteNumber = 2

        fixture.service.cancel()

        XCTAssertEqual(fixture.results, [.failed("Could not restore the rich shot. Copy the shot again to retry.")])
        XCTAssertFalse(fixture.service.isPasting)
        XCTAssertEqual(fixture.writer.writeCount, 2)
    }

    @MainActor
    func testSuccessfulPasteReportsRestorationFailureWithoutClaimingCancellation() async throws {
        let fixture = try makeFixture()
        XCTAssertTrue(fixture.arm())
        XCTAssertTrue(fixture.emit(.paste(isRepeat: false)))
        try await waitUntil { fixture.sleep.contains(AssistedPasteFixture.imageDelay) }
        try await fixture.advanceImageDelay()
        fixture.writer.failWriteNumber = 3

        try await fixture.advanceRestoreDelay()

        XCTAssertEqual(fixture.environment.posts.count, 2)
        XCTAssertEqual(fixture.results, [.eventsSent, .failed("Could not restore the rich shot. Copy the shot again to retry.")])
        XCTAssertEqual(fixture.writer.writeCount, 3)
        XCTAssertFalse(fixture.service.isPasting)
    }

    @MainActor
    func testDeferredRestorationSkipsInterveningCopyWithoutReportingWriteFailure() async throws {
        let fixture = try makeFixture()
        XCTAssertTrue(fixture.arm())
        XCTAssertTrue(fixture.emit(.paste(isRepeat: false)))
        try await waitUntil { fixture.sleep.contains(AssistedPasteFixture.imageDelay) }
        fixture.writer.failWriteNumber = 2

        XCTAssertFalse(fixture.emit(.pointerDown))
        fixture.copyUnrelatedText("Keep the newer copy")
        let newChangeCount = fixture.clipboard.changeCount
        try await waitUntil { !fixture.results.isEmpty }

        XCTAssertEqual(fixture.results, [.cancelled("Paste assistance stopped because you started another action.")])
        XCTAssertEqual(fixture.writer.writeCount, 1, "An ownership change skips restoration entirely.")
        XCTAssertEqual(fixture.clipboard.changeCount, newChangeCount)
        XCTAssertEqual(fixture.clipboard.string(forType: .string), "Keep the newer copy")
    }

    @MainActor
    func testOwnershipChangeDuringFailedRestoreIsNotReportedAsOurWriteFailure() async throws {
        for isDeferred in [false, true] {
            let fixture = try makeFixture()
            XCTAssertTrue(fixture.arm())
            XCTAssertTrue(fixture.emit(.paste(isRepeat: false)))
            try await waitUntil { fixture.sleep.contains(AssistedPasteFixture.imageDelay) }
            fixture.writer.replaceClipboardOnWriteNumber = 2

            if isDeferred {
                XCTAssertFalse(fixture.emit(.pointerDown))
            } else {
                fixture.environment.target = .init(processIdentifier: 42, focusIdentity: "a different control")
                try await fixture.advanceImageDelay(expectSecondPost: false)
            }
            try await waitUntil { !fixture.results.isEmpty }

            XCTAssertEqual(fixture.writer.writeCount, 2)
            XCTAssertEqual(fixture.clipboard.string(forType: .string), "A newer clipboard owner won the write")
            XCTAssertEqual(fixture.results.count, 1)
            guard case .cancelled = fixture.results[0] else {
                return XCTFail("A concurrent clipboard copy is cancellation, not our restoration failure.")
            }
            XCTAssertFalse(fixture.service.isPasting)
        }
    }

    @MainActor
    func testRepeatedCancelOrStopPreservesDeferredRestorationAndSingleNotice() async throws {
        for shouldStop in [false, true] {
            let fixture = try makeFixture()
            XCTAssertTrue(fixture.arm())
            XCTAssertTrue(fixture.emit(.paste(isRepeat: false)))
            try await waitUntil { fixture.sleep.contains(AssistedPasteFixture.imageDelay) }
            XCTAssertFalse(fixture.emit(.pointerDown))
            XCTAssertFalse(fixture.service.isPasting)
            XCTAssertTrue(fixture.results.isEmpty)

            if shouldStop { fixture.service.stop() }
            else { fixture.service.cancel() }
            try await waitUntil { !fixture.results.isEmpty }

            XCTAssertEqual(fixture.results, [.cancelled("Paste assistance stopped because you started another action.")])
            XCTAssertEqual(fixture.writer.writeCount, 2)
            XCTAssertEqual(fixture.clipboard.data(forType: .png), fixture.capture.pngData)
            XCTAssertEqual(fixture.clipboard.string(forType: .string), fixture.capture.clipboardText)
            XCTAssertNotNil(fixture.clipboard.data(forType: .rtfd))
            fixture.sleep.resumeAll()
            for _ in 0..<5 { await Task.yield() }
            XCTAssertEqual(fixture.results.count, 1)
            XCTAssertFalse(fixture.service.isArmed)
            XCTAssertFalse(fixture.service.isPasting)
        }
    }

    @MainActor
    func testRearmInvalidatesDeferredRestorationAndItsNotice() async throws {
        let fixture = try makeFixture()
        XCTAssertTrue(fixture.arm())
        XCTAssertTrue(fixture.emit(.paste(isRepeat: false)))
        try await waitUntil { fixture.sleep.contains(AssistedPasteFixture.imageDelay) }
        fixture.writer.failWriteNumber = 2
        XCTAssertFalse(fixture.emit(.pointerDown))
        fixture.clipboard.clearContents()
        XCTAssertTrue(fixture.clipboard.writeObjects([CaptureClipboardService.makeItem(for: fixture.capture)]))
        XCTAssertTrue(fixture.arm())
        let newChangeCount = fixture.clipboard.changeCount

        fixture.sleep.resumeAll()
        // Give the queued cleanup and old sequence both a chance to run.
        for _ in 0..<5 { await Task.yield() }

        XCTAssertTrue(fixture.service.isArmed)
        XCTAssertTrue(fixture.results.isEmpty, "A superseded cleanup must not report over the newly armed shot.")
        XCTAssertEqual(fixture.writer.writeCount, 1)
        XCTAssertEqual(fixture.clipboard.changeCount, newChangeCount)
        XCTAssertEqual(fixture.clipboard.string(forType: .string), fixture.capture.clipboardText)
    }

    @MainActor
    private func makeFixture() throws -> AssistedPasteFixture {
        let clipboard = NSPasteboard(name: .init("NotchShotAssistedPasteTests-\(UUID())"))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for x in 0..<2 {
            for y in 0..<2 { bitmap.setColor(NSColor(deviceRed: 0.2, green: 0.8, blue: 0.6, alpha: 1), atX: x, y: y) }
        }
        let capture = CaptureResult(appName: "Assisted paste fixture", bundleIdentifier: "com.example.assisted-paste",
                                    windowTitle: "Fixture window", pngData: try XCTUnwrap(bitmap.representation(using: .png, properties: [:])),
                                    axTree: [AXNode(id: 1, role: "AXButton", roleDescription: "button", title: "Complete tree")],
                                    accessibilityText: "Exact AX text — 你好 📷", ocrText: "OCR supplement", importedText: "Imported context")
        XCTAssertTrue(clipboard.writeObjects([CaptureClipboardService.makeItem(for: capture)]))
        let fixture = AssistedPasteFixture(capture: capture, clipboard: clipboard)
        addTeardownBlock {
            await MainActor.run {
                fixture.service.stop()
                fixture.sleep.resumeAll()
                fixture.environment.resumeTargetQueries()
                fixture.clipboard.releaseGlobally()
            }
        }
        return fixture
    }

    @MainActor
    private func waitUntil(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<300 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Timed out waiting for an assisted paste phase.", file: file, line: line)
    }
}

@MainActor
private final class AssistedPasteFixture {
    static let imageDelay: Duration = .milliseconds(111)
    static let restoreDelay: Duration = .milliseconds(222)
    let capture: CaptureResult
    let clipboard: NSPasteboard
    let environment: AssistedPasteEnvironmentSpy
    let clock = AssistedPasteClock()
    let sleep = AssistedPasteSleepGate()
    let writer = AssistedPasteClipboardWriter()
    private(set) var results: [AssistedPasteResult] = []
    let service: AssistedPasteService

    init(capture: CaptureResult, clipboard: NSPasteboard) {
        self.capture = capture
        self.clipboard = clipboard
        environment = AssistedPasteEnvironmentSpy(clipboard: clipboard)
        let sleep = self.sleep
        let clock = self.clock
        let writer = self.writer
        service = AssistedPasteService(environment: environment,
                                       imageDelay: Self.imageDelay, restoreDelay: Self.restoreDelay,
                                       armTimeout: .seconds(120), sleep: { try await sleep.wait($0) },
                                       now: { clock.now }, startPolling: false,
                                       writeClipboardItem: { writer.write($1, to: $0) })
        service.onResult = { [weak self] in self?.results.append($0) }
    }

    func arm() -> Bool { service.arm(capture: capture, clipboard: clipboard) }
    func emit(_ event: AssistedPasteEvent) -> Bool { environment.onEvent?(event) ?? false }
    func copyUnrelatedText(_ text: String) {
        clipboard.clearContents()
        clipboard.setString(text, forType: .string)
    }

    func advanceImageDelay(expectSecondPost: Bool = true) async throws {
        try await advance(Self.imageDelay)
        if expectSecondPost { try await waitUntil { self.environment.posts.count == 2 } }
        else { await Task.yield() }
    }

    func advanceRestoreDelay() async throws {
        try await advance(Self.restoreDelay)
        try await waitUntil { !self.service.isPasting }
    }

    private func advance(_ duration: Duration) async throws {
        try await waitUntil { self.sleep.contains(duration) }
        sleep.resume(duration)
        await Task.yield()
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0..<300 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Timed out waiting for a controlled assisted paste delay.")
    }
}

@MainActor
private final class AssistedPasteClipboardWriter {
    var failWriteNumber: Int?
    var replaceClipboardOnWriteNumber: Int?
    private(set) var writeCount = 0

    func write(_ item: NSPasteboardItem, to clipboard: NSPasteboard) -> Bool {
        writeCount += 1
        if writeCount == replaceClipboardOnWriteNumber {
            clipboard.clearContents()
            clipboard.setString("A newer clipboard owner won the write", forType: .string)
            return false
        }
        guard writeCount != failWriteNumber else { return false }
        return clipboard.writeObjects([item])
    }
}

@MainActor
private final class AssistedPasteClock {
    var now = Date(timeIntervalSince1970: 1_700_000_000)
}

@MainActor
private final class AssistedPasteSleepGate {
    private var waiters: [(Duration, CheckedContinuation<Void, Error>)] = []
    func wait(_ duration: Duration) async throws {
        try Task.checkCancellation()
        try await withCheckedThrowingContinuation { waiters.append((duration, $0)) }
        try Task.checkCancellation()
    }
    func contains(_ duration: Duration) -> Bool { waiters.contains { $0.0 == duration } }
    func resume(_ duration: Duration) {
        guard let index = waiters.firstIndex(where: { $0.0 == duration }) else { return }
        waiters.remove(at: index).1.resume()
    }
    func resumeAll() {
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.1.resume() }
    }
}

@MainActor
private final class AssistedPasteEnvironmentSpy: AssistedPasteEnvironment {
    struct PostedPaste {
        let target: AssistedPasteTarget
        let png: Data?
        let text: String?
        let rtfd: Data?
    }
    struct FallbackPaste {
        let processIdentifier: pid_t
        let png: Data?
        let text: String?
        let rtfd: Data?
    }
    var onEvent: ((AssistedPasteEvent) -> Bool)?
    var isAccessibilityTrusted = true
    var frontmostProcessIdentifier: pid_t? = 42
    var canStartMonitoring = true
    var target: AssistedPasteTarget? = .init(processIdentifier: 42, focusIdentity: "window-A/control-A")
    var failPostNumber: Int?
    var suspendNextTargetQuery = false
    private(set) var posts: [PostedPaste] = []
    private(set) var fallbacks: [FallbackPaste] = []
    private(set) var targetReadCount = 0
    private var pendingTargetQueries: [(AssistedPasteTarget?, CheckedContinuation<AssistedPasteTarget?, Never>)] = []
    var hasPendingTargetQuery: Bool { !pendingTargetQueries.isEmpty }
    private(set) var startCount = 0
    private(set) var stopCount = 0
    let clipboard: NSPasteboard
    init(clipboard: NSPasteboard) { self.clipboard = clipboard }
    func startMonitoring() -> Bool { startCount += 1; return canStartMonitoring }
    func stopMonitoring() { stopCount += 1 }
    func currentTarget() async -> AssistedPasteTarget? {
        targetReadCount += 1
        guard suspendNextTargetQuery else { return target }
        suspendNextTargetQuery = false
        let snapshot = target
        return await withCheckedContinuation { pendingTargetQueries.append((snapshot, $0)) }
    }
    func resumeTargetQueries() {
        let pending = pendingTargetQueries
        pendingTargetQueries.removeAll()
        pending.forEach { $0.1.resume(returning: $0.0) }
    }
    func postPaste(to target: AssistedPasteTarget) -> Bool {
        posts.append(PostedPaste(target: target, png: clipboard.data(forType: .png),
                                 text: clipboard.string(forType: .string), rtfd: clipboard.data(forType: .rtfd)))
        return posts.count != failPostNumber
    }
    func postFallbackPaste(to processIdentifier: pid_t) -> Bool {
        fallbacks.append(FallbackPaste(processIdentifier: processIdentifier, png: clipboard.data(forType: .png),
                                        text: clipboard.string(forType: .string), rtfd: clipboard.data(forType: .rtfd)))
        return true
    }
}
