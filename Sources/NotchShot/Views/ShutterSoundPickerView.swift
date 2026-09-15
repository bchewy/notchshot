// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI

struct ShutterSoundPickerView: View {
    @Bindable var store: CaptureStore

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("Shutter")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.8))
                Spacer()
                Text("Click to hear")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            HStack(spacing: 8) {
                ForEach(CaptureShutterSound.allCases) { sound in
                    ShutterSoundTile(sound: sound, selected: store.captureShutterSound == sound) {
                        store.captureShutterSound = sound
                        store.previewCaptureSound()
                    }
                }
            }
        }
        .padding(.top, 5)
    }
}

private struct ShutterSoundTile: View {
    let sound: CaptureShutterSound
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Group {
                    if let image = CameraArtwork.images[sound] {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                    } else {
                        Image(systemName: "camera")
                            .font(.system(size: 29, weight: .light))
                            .foregroundStyle(Color.white.opacity(0.65))
                    }
                }
                .frame(width: 90, height: 54)
                .accessibilityHidden(true)

                Text(sound.shortTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(selected ? Color.white : Color.white.opacity(0.8))
                Text(sound.familyTitle)
                    .font(.system(size: 7, weight: .medium))
                    .tracking(1.2)
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 94)
        }
        .buttonStyle(ShutterTileButtonStyle(selected: selected))
        .accessibilityLabel("Select and preview \(sound.title) shutter")
        .accessibilityValue(selected ? "Selected" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help("\(sound.title). Click to select and hear the shutter at your chosen volume.")
    }
}

private struct ShutterTileButtonStyle: ButtonStyle {
    let selected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        let raised = hovering && !configuration.isPressed
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 11)
                    .fill(Color.white.opacity(selected ? 0.075 : hovering ? 0.055 : 0.025))
                    .overlay {
                        if selected {
                            RoundedRectangle(cornerRadius: 11)
                                .fill(NotchStyle.accent.opacity(0.035))
                        }
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(selected ? NotchStyle.accent.opacity(0.65) : Color.white.opacity(hovering ? 0.2 : 0.1), lineWidth: 1)
            }
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(NotchStyle.accent)
                        .padding(7)
                        .accessibilityHidden(true)
                }
            }
            .shadow(color: selected ? NotchStyle.accent.opacity(0.06) : .clear, radius: 5, y: 2)
            .contentShape(RoundedRectangle(cornerRadius: 11))
            .scaleEffect(reduceMotion ? 1 : configuration.isPressed ? 0.98 : raised ? 1.025 : 1)
            .offset(y: reduceMotion ? 0 : raised ? -1.5 : 0)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovering)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
            .onHover { hovering = $0 }
    }
}
