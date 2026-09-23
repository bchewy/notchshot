// SPDX-License-Identifier: MIT
import AppKit

/// Bundled camera artwork for the shutter picker.
/// Pointer feedback and capture poses must not decode these large PNGs again.
@MainActor
enum CameraArtwork {
    static let images: [CaptureShutterSound: NSImage] = Dictionary(
        uniqueKeysWithValues: CaptureShutterSound.allCases.compactMap { sound in
            guard let url = sound.cameraIconURL, let image = NSImage(contentsOf: url) else { return nil }
            return (sound, image)
        }
    )
}
