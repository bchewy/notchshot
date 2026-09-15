// SPDX-License-Identifier: MIT
import AppKit

@MainActor
protocol CopySoundPlaying: AnyObject {
    func play()
    func setVolume(_ volume: Float)
}

extension CopySoundPlaying {
    func setVolume(_ volume: Float) {}
}

/// A short native confirmation, distinct from the capture shutter. The sound
/// stays in macOS; it is not copied into or redistributed with the app.
@MainActor
final class CopySoundService: CopySoundPlaying {
    private let sound: (any CaptureSoundPlayback)?

    static var resourceURL: URL? {
        let url = URL(fileURLWithPath: "/System/Library/Sounds/Tink.aiff")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    init() {
        sound = Self.resourceURL.flatMap { NSSound(contentsOf: $0, byReference: false) }
        sound?.volume = 0.65
    }

    init(sound: any CaptureSoundPlayback) {
        self.sound = sound
        sound.volume = 0.65
    }

    func setVolume(_ volume: Float) {
        sound?.volume = volume.isFinite ? min(max(volume, 0), 1) : 0.65
    }

    func play() {
        sound?.stop()
        sound?.currentTime = 0
        sound?.play()
    }
}
