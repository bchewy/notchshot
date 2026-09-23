// SPDX-License-Identifier: MIT
import AppKit
import XCTest
@testable import NotchShot

final class CopySoundTests: XCTestCase {
    @MainActor
    func testConfirmationResourceDecodesAndRapidCopiesRestartOneVoice() throws {
        let url = try XCTUnwrap(CopySoundService.resourceURL)
        let decoded = try XCTUnwrap(NSSound(contentsOf: url, byReference: false))
        XCTAssertGreaterThan(decoded.duration, 0)
        XCTAssertLessThan(decoded.duration, 1, "Copy feedback should remain a short confirmation.")

        let player = CopyPlaybackSpy()
        let service = CopySoundService(sound: player)
        XCTAssertEqual(player.volume, 0.65, accuracy: 0.001)
        service.play()
        service.play()
        XCTAssertEqual(player.events, ["stop", "rewind", "play", "stop", "rewind", "play"])
        XCTAssertEqual(player.currentTime, 0)
    }

    @MainActor
    func testVolumeChangesAreSafeAndNeverAutoplay() {
        let player = CopyPlaybackSpy()
        let service = CopySoundService(sound: player)
        let cases: [(Float, Float)] = [(0.2, 0.2), (-1, 0), (2, 1), (.nan, 0.65), (.infinity, 0.65), (-.infinity, 0.65)]
        for (input, expected) in cases {
            service.setVolume(input)
            XCTAssertEqual(player.volume, expected, accuracy: 0.001)
        }
        XCTAssertTrue(player.events.isEmpty)
        service.play()
        let playbackEvents = player.events
        service.setVolume(0.4)
        XCTAssertEqual(player.volume, 0.4, accuracy: 0.001)
        XCTAssertEqual(player.events, playbackEvents, "Moving the shared volume slider must not restart playback.")
    }

    @MainActor
    func testSuccessfulManualCopiesConfirmOnceAndMissingContentStaysSilent() throws {
        let fixture = makeFixture()
        let store = fixture.store
        defer { store.stop() }
        let capture = try makeImageCapture("Copy target")
        store.captures = [capture]
        store.selectedID = capture.id

        XCTAssertTrue(store.copyCapture(capture.id))
        XCTAssertEqual(fixture.sound.playCount, 1)
        XCTAssertEqual(fixture.clipboard.string(forType: .string), capture.clipboardText)
        XCTAssertEqual(fixture.clipboard.data(forType: .png), capture.pngData)
        store.copyImage()
        XCTAssertEqual(fixture.sound.playCount, 2)
        XCTAssertEqual(fixture.clipboard.data(forType: .png), capture.pngData)
        store.copyText()
        XCTAssertEqual(fixture.sound.playCount, 3)
        XCTAssertTrue(fixture.clipboard.string(forType: .string)?.contains(capture.accessibilityText) == true)
        store.copyTree()
        XCTAssertEqual(fixture.sound.playCount, 4)
        XCTAssertEqual(fixture.clipboard.string(forType: .string), capture.clipboardText)
        store.copyContext()
        XCTAssertEqual(fixture.sound.playCount, 5, "Copy all delegates to copyCapture and should not confirm twice.")

        let copiedChangeCount = fixture.clipboard.changeCount
        XCTAssertFalse(store.copyCapture(UUID()))
        store.captures = []
        store.copyImage()
        store.copyText()
        store.copyTree()
        store.copyContext()
        XCTAssertEqual(fixture.sound.playCount, 5)
        XCTAssertEqual(fixture.clipboard.changeCount, copiedChangeCount)

        let empty = CaptureResult(appName: "Empty", bundleIdentifier: "com.example.copy-sound", windowTitle: "Empty")
        store.captures = [empty]
        store.selectedID = empty.id
        store.copyImage()
        store.copyText()
        store.copyTree()
        XCTAssertEqual(fixture.sound.playCount, 5, "Unavailable screenshot, text, or tree must not report a successful copy.")
        XCTAssertEqual(fixture.clipboard.changeCount, copiedChangeCount)
    }

    @MainActor
    func testMuteChoicePersistsWhileCopyingAndSharedVolumeStillWork() {
        let fixture = makeFixture()
        let store = fixture.store
        defer { store.stop() }
        let capture = makeCapture("Muted copy")
        store.captures = [capture]
        XCTAssertTrue(store.copySoundEnabled)
        XCTAssertEqual(fixture.sound.volumes, [0.65])

        store.copySoundEnabled = false
        store.captureSoundVolume = 0.23
        XCTAssertTrue(store.copyCapture(capture.id))
        XCTAssertEqual(fixture.clipboard.string(forType: .string), capture.clipboardText)
        XCTAssertEqual(fixture.sound.playCount, 0)
        XCTAssertEqual(fixture.sound.volumes.last ?? -1, 0.23, accuracy: 0.001)

        let restoredSound = CopyFeedbackSpy()
        let restored = CaptureStore(preferences: fixture.preferences,
                                    captureSound: SilentCaptureSound(),
                                    clipboard: fixture.clipboard,
                                    copySound: restoredSound)
        defer { restored.stop() }
        XCTAssertFalse(restored.copySoundEnabled)
        XCTAssertEqual(restoredSound.volumes.last ?? -1, 0.23, accuracy: 0.001)
        XCTAssertEqual(restoredSound.playCount, 0)
        restored.captures = [capture]
        restored.captureSoundEnabled = false
        restored.copySoundEnabled = true
        XCTAssertTrue(restored.copyCapture(capture.id))
        XCTAssertEqual(restoredSound.playCount, 1, "Copy feedback has its own toggle, independent of the capture shutter.")
    }

    @MainActor
    func testAutoCopyConfirmsOnlyCompletedFirstCopyAndNotShelfCollection() {
        let fixture = makeFixture()
        let store = fixture.store
        defer { store.stop() }
        let capture = makeCapture("Automatic copy")
        fixture.clipboard.setString("Existing clipboard", forType: .string)
        let initialChangeCount = fixture.clipboard.changeCount

        store.autoCopyCompletedCapture(capture)
        store.autoCopyCapture = true
        store.isCapturing = true
        store.autoCopyCompletedCapture(capture)
        XCTAssertEqual(fixture.sound.playCount, 0)
        XCTAssertEqual(fixture.clipboard.changeCount, initialChangeCount)

        store.isCapturing = false
        store.autoCopyCompletedCapture(capture)
        XCTAssertEqual(fixture.sound.playCount, 1)
        XCTAssertEqual(fixture.clipboard.string(forType: .string), capture.clipboardText)
        fixture.clipboard.clearContents()
        fixture.clipboard.setString("Copied later in another app", forType: .string)
        let laterChangeCount = fixture.clipboard.changeCount
        store.autoCopyCompletedCapture(capture)
        store.pendingCapture = capture
        store.acceptPendingCapture()
        XCTAssertEqual(fixture.sound.playCount, 1)
        XCTAssertEqual(fixture.clipboard.changeCount, laterChangeCount)
        XCTAssertEqual(fixture.clipboard.string(forType: .string), "Copied later in another app")
        XCTAssertEqual(store.captures.map(\.id), [capture.id])

        store.copySoundEnabled = false
        let muted = makeCapture("Muted automatic copy")
        store.autoCopyCompletedCapture(muted)
        XCTAssertEqual(fixture.sound.playCount, 1)
        XCTAssertEqual(fixture.clipboard.string(forType: .string), muted.clipboardText)
    }

    @MainActor
    private func makeFixture() -> (store: CaptureStore, preferences: UserDefaults, clipboard: NSPasteboard, sound: CopyFeedbackSpy) {
        let suite = "NotchShotCopySoundTests-\(UUID())"
        let preferences = UserDefaults(suiteName: suite)!
        let clipboard = NSPasteboard(name: .init(suite))
        let sound = CopyFeedbackSpy()
        addTeardownBlock {
            preferences.removePersistentDomain(forName: suite)
            clipboard.releaseGlobally()
        }
        let store = CaptureStore(preferences: preferences,
                                 captureSound: SilentCaptureSound(),
                                 clipboard: clipboard,
                                 copySound: sound)
        return (store, preferences, clipboard, sound)
    }

    private func makeCapture(_ name: String) -> CaptureResult {
        CaptureResult(appName: name, bundleIdentifier: "com.example.copy-sound", windowTitle: name,
                      axTree: [AXNode(id: 1, role: "AXButton", roleDescription: "button", title: "Submit")],
                      accessibilityText: "Accessible content for \(name)")
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
}

@MainActor
private final class CopyPlaybackSpy: CaptureSoundPlayback {
    var events: [String] = []
    var currentTime: TimeInterval = 0.2 {
        didSet { events.append("rewind") }
    }
    var volume: Float = 1
    func stop() -> Bool { events.append("stop"); return true }
    func play() -> Bool { events.append("play"); return true }
}

@MainActor
private final class CopyFeedbackSpy: CopySoundPlaying {
    var playCount = 0
    var volumes: [Float] = []
    func play() { playCount += 1 }
    func setVolume(_ volume: Float) { volumes.append(volume) }
}

@MainActor
private final class SilentCaptureSound: CaptureSoundPlaying {
    func play() {}
}
