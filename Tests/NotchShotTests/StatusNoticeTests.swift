// SPDX-License-Identifier: MIT
import AppKit
import XCTest
@testable import NotchShot

final class StatusNoticeTests: XCTestCase {
    func testNoticeExpiryIsBoundedAndDoesNotRestartWhenReadAgain() {
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        let cases: [(StatusNotice.Kind, TimeInterval)] = [(.success, 3), (.info, 5), (.error, 8)]
        for (kind, duration) in cases {
            let notice = StatusNotice(kind: kind, title: "Status", message: "Status", createdAt: createdAt)
            let deadline = createdAt.addingTimeInterval(duration)
            XCTAssertEqual(notice.createdAt, createdAt)
            XCTAssertEqual(notice.expiresAt, deadline)
            XCTAssertEqual(notice.remainingDuration(at: createdAt), duration, accuracy: 0.001)
            XCTAssertFalse(notice.isExpired(at: deadline.addingTimeInterval(-0.001)))
            XCTAssertTrue(notice.isExpired(at: deadline))
            XCTAssertEqual(notice.remainingDuration(at: deadline), 0)
            XCTAssertTrue(notice.isExpired(at: deadline.addingTimeInterval(60)))
            XCTAssertEqual(notice.remainingDuration(at: deadline.addingTimeInterval(60)), 0)
            XCTAssertEqual(notice.expiresAt, deadline, "Reading an old notice must not give it a fresh display lifetime.")
        }
    }

    func testNoticeKeepsTheKindTitleAndFullMessageItWasGiven() {
        let message = "Could not export to Exported items. The copied archive could not be saved."
        let notice = StatusNotice(kind: .error, title: "Needs attention", message: message)
        XCTAssertEqual(notice.kind, .error)
        XCTAssertEqual(notice.title, "Needs attention")
        XCTAssertEqual(notice.message, message)

        let copied = StatusNotice(kind: .success, title: "Copied", message: "2 shots copied. Your next ⌘V pastes the screenshots in order.")
        XCTAssertEqual(copied.kind, .success, "The producer's kind stands whatever the wording says.")
        XCTAssertEqual(copied.title, "Copied")
    }

    @MainActor
    func testRepeatedReportsCreateFreshNoticesAndClearingRemovesThem() throws {
        let fixture = makeFixture()
        let store = fixture.store
        defer { store.stop() }
        store.report(.success, "Copied", message: "Screenshot copied.")
        let first = try XCTUnwrap(store.statusNotice)
        store.report(.success, "Copied", message: "Screenshot copied.")
        let second = try XCTUnwrap(store.statusNotice)
        XCTAssertNotEqual(second.id, first.id, "The same action repeated should replay its confirmation.")
        XCTAssertEqual(second.message, first.message)
        XCTAssertGreaterThanOrEqual(second.createdAt, first.createdAt)
        XCTAssertGreaterThanOrEqual(second.expiresAt, first.expiresAt)
        XCTAssertEqual(store.statusNotice?.message, "Screenshot copied.")

        store.clearStatus()
        XCTAssertNil(store.statusNotice)
        XCTAssertNil(store.statusNotice?.message)
        store.report(.success, "Copied", message: "Text copied with its source labels.")
        XCTAssertNotNil(store.statusNotice)
        XCTAssertEqual(store.page, .shelf)
        XCTAssertFalse(store.isExpanded)
    }

    @MainActor
    func testExplicitErrorsRetainTheirFullDiagnosticWithoutNavigation() throws {
        let fixture = makeFixture()
        let store = fixture.store
        defer { store.stop() }
        store.page = .settings
        store.isExpanded = true
        let message = "Captured window could not be read.\nThe accessibility provider returned error -25204."
        store.reportError(message)
        let notice = try XCTUnwrap(store.statusNotice)
        XCTAssertEqual(notice.kind, .error)
        XCTAssertEqual(notice.title, "Needs attention")
        XCTAssertEqual(notice.message, message)
        XCTAssertEqual(store.statusNotice?.message, message)
        XCTAssertEqual(store.page, .settings)
        XCTAssertTrue(store.isExpanded)
    }

    @MainActor
    func testBatchAndSingleCopiesAreBothSuccessNoticesWhateverTheirWording() throws {
        let fixture = makeFixture()
        let store = fixture.store
        defer { store.stop() }
        let first = CaptureResult(appName: "First", bundleIdentifier: "com.example.first", windowTitle: "One",
                                  accessibilityText: "Alpha")
        let second = CaptureResult(appName: "Second", bundleIdentifier: "com.example.second", windowTitle: "Two",
                                   accessibilityText: "Beta")
        store.captures = [first, second]
        store.isExpanded = true
        store.beginShelfSelection()
        store.selectAllShelfShots()
        XCTAssertNotNil(store.selectedBatch)
        XCTAssertTrue(store.copyShelfSelection())
        let batchNotice = try XCTUnwrap(store.statusNotice)
        XCTAssertEqual(batchNotice.kind, .success)
        XCTAssertEqual(batchNotice.title, "Copied")
        XCTAssertTrue(batchNotice.message.hasPrefix("2 shots copied."), batchNotice.message)

        XCTAssertTrue(store.copyCapture(first.id))
        let singleNotice = try XCTUnwrap(store.statusNotice)
        XCTAssertEqual(singleNotice.kind, .success)
        XCTAssertEqual(singleNotice.title, "Copied")
        XCTAssertEqual(singleNotice.message, "First shot copied.")
    }

    func testExportNoticeRetainsItsRevealDestinationEvenAfterExpiry() {
        let folder = URL(fileURLWithPath: "/tmp/NotchShot test export", isDirectory: true)
        let notice = StatusNotice(kind: .success, title: "Exported", message: "Exported to NotchShot test export.",
                                  revealURL: folder, createdAt: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(notice.title, "Exported")
        XCTAssertEqual(notice.revealURL, folder)
        XCTAssertTrue(notice.isExpired(at: notice.expiresAt.addingTimeInterval(1)))
        XCTAssertEqual(notice.revealURL, folder, "Expiry hides feedback; it must not alter its export destination.")
    }

    @MainActor
    func testHoverCopyStillCopiesTheTargetAndNavigationDoesNotRestartItsNotice() throws {
        let fixture = makeFixture()
        let store = fixture.store
        defer { store.stop() }
        let selected = CaptureResult(appName: "Selected", bundleIdentifier: "com.example.selected", windowTitle: "Selected window")
        var target = CaptureResult(appName: "Hovered", bundleIdentifier: "com.example.hovered", windowTitle: "Hovered window",
                                   accessibilityText: "The hovered shot's text")
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for x in 0..<2 {
            for y in 0..<2 { bitmap.setColor(.systemMint, atX: x, y: y) }
        }
        target.pngData = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        store.captures = [selected, target]
        store.selectedID = selected.id
        store.page = .shelf
        store.isExpanded = true

        XCTAssertTrue(store.copyCapture(target.id))
        let notice = try XCTUnwrap(store.statusNotice)
        XCTAssertEqual(notice.title, "Copied")
        XCTAssertEqual(notice.kind, .success)
        XCTAssertNil(notice.revealURL)
        XCTAssertEqual(fixture.clipboard.string(forType: .string), target.contextText)
        XCTAssertEqual(fixture.clipboard.data(forType: .png), target.pngData)
        XCTAssertEqual(store.selectedID, selected.id)
        XCTAssertEqual(store.page, .shelf)
        XCTAssertTrue(store.isExpanded)
        XCTAssertEqual(fixture.sound.playCount, 1)

        let changeCount = fixture.clipboard.changeCount
        XCTAssertFalse(store.copyCapture(UUID()))
        XCTAssertEqual(fixture.clipboard.changeCount, changeCount)
        XCTAssertEqual(store.statusNotice, notice)
        store.isExpanded = false
        store.page = .settings
        store.isExpanded = true
        XCTAssertEqual(store.statusNotice, notice, "Reopening or changing pages must not replay old feedback.")
        let reopenedNotice = try XCTUnwrap(store.statusNotice)
        XCTAssertTrue(reopenedNotice.isExpired(at: notice.expiresAt.addingTimeInterval(1)))
    }

    @MainActor
    private func makeFixture() -> (store: CaptureStore, clipboard: NSPasteboard, sound: NoticeSoundSpy) {
        let (preferences, clipboard) = isolatedStoreDependencies()
        preferences.set(false, forKey: "collapseAfterCopy")
        let sound = NoticeSoundSpy()
        let store = CaptureStore(preferences: preferences, captureSound: NoticeSoundSpy(), clipboard: clipboard, copySound: sound)
        return (store, clipboard, sound)
    }
}

@MainActor
private final class NoticeSoundSpy: CaptureSoundPlaying, CopySoundPlaying {
    var playCount = 0
    func play() { playCount += 1 }
    func setVolume(_ volume: Float) {}
}
