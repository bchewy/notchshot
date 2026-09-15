// SPDX-License-Identifier: MIT
import AppKit

@MainActor
protocol CaptureSoundPlaying: AnyObject {
    func play()
    func select(_ choice: CaptureShutterSound)
    func setVolume(_ volume: Float)
}

extension CaptureSoundPlaying {
    func select(_ choice: CaptureShutterSound) {}
    func setVolume(_ volume: Float) {}
}

/// A small playback boundary lets tests verify repeat behavior without audio.
@MainActor
protocol CaptureSoundPlayback: AnyObject {
    var currentTime: TimeInterval { get set }
    var volume: Float { get set }
    @discardableResult func stop() -> Bool
    @discardableResult func play() -> Bool
}

extension NSSound: CaptureSoundPlayback {}

@MainActor
final class CaptureSoundService: CaptureSoundPlaying {
    typealias Loader = (URL) -> (any CaptureSoundPlayback)?

    private let loader: Loader
    private var sounds: [CaptureShutterSound: any CaptureSoundPlayback] = [:]
    private var sound: (any CaptureSoundPlayback)?
    private var volume: Float = 0.65
    private(set) var selectedChoice: CaptureShutterSound = .defaultSound

    /// The packaged app owns its resource directly. The SwiftPM bundle is only
    /// a fallback for `swift run` and tests, never a requirement of the app.
    static var resourceURL: URL? {
        CaptureShutterSound.defaultSound.resourceURL
    }

    init(loader: @escaping Loader = { NSSound(contentsOf: $0, byReference: false) }) {
        self.loader = loader
        // Preload once, keeping capture-time playback entirely in memory.
        sound = Self.resourceURL.flatMap(loader)
        sound?.volume = volume
        if let sound { sounds[.defaultSound] = sound }
    }

    init(sound: any CaptureSoundPlayback) {
        loader = { NSSound(contentsOf: $0, byReference: false) }
        self.sound = sound
        sounds[.defaultSound] = sound
        sound.volume = volume
    }

    func select(_ choice: CaptureShutterSound) {
        guard choice != selectedChoice else { return }
        guard let nextSound = sounds[choice] ?? choice.resourceURL.flatMap(loader) else {
            // A missing or damaged resource must not silence a working voice.
            return
        }
        sound?.stop()
        nextSound.volume = volume
        sounds[choice] = nextSound
        sound = nextSound
        selectedChoice = choice
    }

    func setVolume(_ volume: Float) {
        self.volume = volume.isFinite ? min(max(volume, 0), 1) : 0.65
        // Changing the slider adjusts an active preview without restarting it.
        // Cached voices pick up the same setting when they are selected again.
        sound?.volume = self.volume
    }

    func play() {
        // An explicit audition or a quick repeat restarts the same voice.
        // Multiple shutters must not stack and get louder.
        sound?.stop()
        sound?.currentTime = 0
        sound?.play()
    }
}
