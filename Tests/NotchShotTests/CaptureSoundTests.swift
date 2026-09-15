// SPDX-License-Identifier: MIT
import AppKit
import AVFoundation
import XCTest
@testable import NotchShot

final class CaptureSoundTests: XCTestCase {
    @MainActor
    func testBundledShutterDecodesAsShortNonSilentAudio() throws {
        for choice in CaptureShutterSound.allCases {
            let url = try XCTUnwrap(choice.resourceURL, choice.title)
            let sound = try XCTUnwrap(NSSound(contentsOf: url, byReference: false), choice.title)
            XCTAssertGreaterThan(sound.duration, 0.05, choice.title)
            XCTAssertLessThan(sound.duration, 1, choice.title)

            let file = try AVAudioFile(forReading: url)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                      frameCapacity: AVAudioFrameCount(file.length)))
            try file.read(into: buffer)
            let channel = try XCTUnwrap(buffer.floatChannelData?[0])
            let samples = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
            let peak = try XCTUnwrap(samples.map { abs($0) }.max())
            XCTAssertGreaterThan(peak, 0.01, "\(choice.title) must not be silent.")
            XCTAssertLessThan(peak, 0.9, "\(choice.title) should leave comfortable playback headroom.")
        }
    }

    @MainActor
    func testRepeatsRestartOneRetainedSoundAtModerateVolume() {
        let player = PlaybackSpy()
        let service = CaptureSoundService(sound: player)
        XCTAssertEqual(player.volume, 0.65, accuracy: 0.001)
        service.play()
        service.play()
        XCTAssertEqual(player.events, ["stop", "rewind", "play", "stop", "rewind", "play"])
        XCTAssertEqual(player.currentTime, 0)
    }

    @MainActor
    func testVolumeAdjustsActiveVoiceWithoutPlayingOrRestarting() {
        let player = PlaybackSpy()
        let service = CaptureSoundService(sound: player)
        service.play()
        let playbackEvents = player.events

        service.setVolume(0.23)

        XCTAssertEqual(player.volume, 0.23, accuracy: 0.001)
        XCTAssertEqual(player.events, playbackEvents, "Adjusting volume must not autoplay or interrupt an active preview.")
        service.play()
        XCTAssertEqual(player.volume, 0.23, accuracy: 0.001)
    }

    @MainActor
    func testVolumeIsClampedAndInvalidValuesUseModerateFallback() {
        let player = PlaybackSpy()
        let service = CaptureSoundService(sound: player)
        let cases: [(Float, Float)] = [(-0.2, 0), (1.7, 1), (.nan, 0.65), (.infinity, 0.65), (-.infinity, 0.65)]
        for (input, expected) in cases {
            service.setVolume(input)
            XCTAssertEqual(player.volume, expected, accuracy: 0.001)
        }
        XCTAssertTrue(player.events.isEmpty, "Invalid saved values must not cause a preview to play.")
    }

    @MainActor
    func testNewAndCachedVoicesUseLatestVolumeWithoutAutoplay() throws {
        let alternative = try XCTUnwrap(CaptureShutterSound.allCases.first { $0 != .defaultSound })
        let defaultURL = try XCTUnwrap(CaptureShutterSound.defaultSound.resourceURL)
        let first = PlaybackSpy()
        let second = PlaybackSpy()
        var loadCount = 0
        let service = CaptureSoundService { url in
            loadCount += 1
            return url == defaultURL ? first : second
        }

        service.setVolume(0.2)
        service.select(alternative)
        XCTAssertEqual(second.volume, 0.2, accuracy: 0.001)
        XCTAssertTrue(second.events.isEmpty)

        service.setVolume(0.8)
        service.select(.defaultSound)
        XCTAssertEqual(first.volume, 0.8, accuracy: 0.001)
        service.setVolume(0.4)
        service.select(alternative)
        XCTAssertEqual(second.volume, 0.4, accuracy: 0.001)
        XCTAssertEqual(loadCount, 2, "Volume changes must not reload cached resources.")
        XCTAssertFalse(first.events.contains("play"))
        XCTAssertFalse(second.events.contains("play"))
    }

    @MainActor
    func testSelectionLoadsMatchingResourceStopsOldVoiceAndReusesCachedVoices() throws {
        let alternative = try XCTUnwrap(CaptureShutterSound.allCases.first { $0 != .defaultSound })
        let defaultURL = try XCTUnwrap(CaptureShutterSound.defaultSound.resourceURL)
        let alternativeURL = try XCTUnwrap(alternative.resourceURL)
        let first = PlaybackSpy()
        let second = PlaybackSpy()
        var loadedURLs: [URL] = []
        let service = CaptureSoundService { url in
            loadedURLs.append(url)
            return url == defaultURL ? first : second
        }

        service.play()
        service.select(alternative)

        XCTAssertEqual(loadedURLs, [defaultURL, alternativeURL])
        XCTAssertEqual(service.selectedChoice, alternative)
        XCTAssertEqual(first.events, ["stop", "rewind", "play", "stop"])
        XCTAssertTrue(second.events.isEmpty, "Selecting a sound must not play it automatically.")
        XCTAssertEqual(second.volume, 0.65, accuracy: 0.001)
        service.play()
        XCTAssertEqual(second.events, ["stop", "rewind", "play"])

        service.select(alternative)
        XCTAssertEqual(second.events, ["stop", "rewind", "play"], "Reselecting the current voice must not interrupt it.")
        service.select(.defaultSound)
        XCTAssertEqual(second.events.last, "stop")
        XCTAssertEqual(loadedURLs.count, 2, "Previously loaded voices should be retained.")
        XCTAssertEqual(service.selectedChoice, .defaultSound)
        service.play()
        XCTAssertEqual(first.events.suffix(3), ["stop", "rewind", "play"])
    }

    @MainActor
    func testFailedSelectionKeepsWorkingVoiceAndCanRetryLater() throws {
        let alternative = try XCTUnwrap(CaptureShutterSound.allCases.first { $0 != .defaultSound })
        let defaultURL = try XCTUnwrap(CaptureShutterSound.defaultSound.resourceURL)
        let first = PlaybackSpy()
        let second = PlaybackSpy()
        var resourceAvailable = false
        let service = CaptureSoundService { url in
            if url == defaultURL { return first }
            return resourceAvailable ? second : nil
        }

        service.select(alternative)
        XCTAssertEqual(service.selectedChoice, .defaultSound)
        XCTAssertTrue(first.events.isEmpty, "A failed selection must not stop the working voice.")
        service.play()
        XCTAssertEqual(first.events, ["stop", "rewind", "play"])

        resourceAvailable = true
        service.select(alternative)
        XCTAssertEqual(service.selectedChoice, alternative)
        XCTAssertEqual(first.events.last, "stop")
        service.play()
        XCTAssertEqual(second.events, ["stop", "rewind", "play"])
    }

    @MainActor
    func testSavedSelectionIsRestoredAndPreviewUsesItWhileMuted() throws {
        let alternative = try XCTUnwrap(CaptureShutterSound.allCases.first { $0 != .defaultSound })
        let suite = "NotchShotCaptureSoundTests-\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        preferences.set(false, forKey: "captureSoundEnabled")
        preferences.set(alternative.rawValue, forKey: "captureShutterSound")
        let sound = SoundSpy()
        let store = CaptureStore(preferences: preferences, captureSound: sound)
        defer { store.stop() }

        XCTAssertEqual(store.captureShutterSound, alternative)
        XCTAssertEqual(sound.selectedChoices, [alternative])
        store.previewCaptureSound()
        XCTAssertEqual(sound.playCount, 1)
        XCTAssertFalse(store.captureSoundEnabled)
        store.captureShutterSound = .defaultSound
        XCTAssertEqual(sound.selectedChoices, [alternative, .defaultSound])
        XCTAssertEqual(preferences.string(forKey: "captureShutterSound"), CaptureShutterSound.defaultSound.rawValue)
    }

    @MainActor
    func testUnknownSavedSoundUsesExistingDefault() {
        let suite = "NotchShotCaptureSoundTests-\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        preferences.set("missing-camera-model", forKey: "captureShutterSound")
        let sound = SoundSpy()
        let store = CaptureStore(preferences: preferences, captureSound: sound)
        defer { store.stop() }
        XCTAssertEqual(store.captureShutterSound, .defaultSound)
        XCTAssertEqual(sound.selectedChoices, [.defaultSound])
    }

    @MainActor
    func testExplicitPreviewPlaysWhileMutedWithoutChangingPreferenceOrShelf() {
        let suite = "NotchShotCaptureSoundTests-\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        preferences.set(false, forKey: "captureSoundEnabled")
        let sound = SoundSpy()
        let store = CaptureStore(preferences: preferences, captureSound: sound)
        defer { store.stop() }

        store.previewCaptureSound()

        XCTAssertEqual(sound.playCount, 1)
        XCTAssertFalse(store.captureSoundEnabled)
        XCTAssertFalse(preferences.bool(forKey: "captureSoundEnabled"))
        XCTAssertTrue(store.captures.isEmpty)
        XCTAssertNil(store.pendingCapture)
        XCTAssertNil(store.selectedID)
        XCTAssertFalse(store.isExpanded)
        XCTAssertEqual(store.page, .shelf)
    }
}

@MainActor
private final class PlaybackSpy: CaptureSoundPlayback {
    var events: [String] = []
    var currentTime: TimeInterval = 0.2 {
        didSet { events.append("rewind") }
    }
    var volume: Float = 1
    func stop() -> Bool { events.append("stop"); return true }
    func play() -> Bool { events.append("play"); return true }
}

@MainActor
private final class SoundSpy: CaptureSoundPlaying {
    var playCount = 0
    var selectedChoices: [CaptureShutterSound] = []
    func play() { playCount += 1 }
    func select(_ choice: CaptureShutterSound) { selectedChoices.append(choice) }
}
