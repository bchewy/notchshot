// SPDX-License-Identifier: MIT
import SwiftUI

struct CaptureEmptyView: View {
    @Bindable var store: CaptureStore
    var reviewingPermissions = false

    private var isReady: Bool { store.accessibilityGranted && store.screenRecordingGranted }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if reviewingPermissions {
                    AutoCollapseSettingsView(store: store)
                    ShortcutSettingsView(
                        shortcut: store.captureShortcut,
                        isRecording: $store.isRecordingShortcut,
                        bothShiftEnabled: $store.bothShiftEnabled,
                        registrationError: store.shortcutError,
                        shortcutAvailable: store.shortcutAvailable,
                        onRecord: store.setCaptureShortcut,
                        onReset: store.resetCaptureShortcut
                    )
                    CaptureBehaviorSettingsView(store: store)
                    BatchCopySettingsView(store: store)
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 20) {
                            Toggle("Capture sound", isOn: $store.captureSoundEnabled)
                            Toggle("Copy sound", isOn: $store.copySoundEnabled)
                                .help("Play a short confirmation after copying a shot, image, text, or tree.")
                            Spacer(minLength: 0)
                        }
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11))
                        .tint(NotchStyle.accent)
                        ShutterSoundPickerView(store: store)
                        HStack(spacing: 8) {
                            Text("Volume")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.white.opacity(0.6))
                            Slider(value: $store.captureSoundVolume, in: 0...1)
                                .controlSize(.small)
                                .tint(NotchStyle.accent)
                                .accessibilityLabel("Sound volume")
                                .help("Volume for capture shutters and copy confirmations.")
                                .accessibilityValue("\(Int((store.captureSoundVolume * 100).rounded())) percent")
                            Text("\(Int((store.captureSoundVolume * 100).rounded()))%")
                                .font(.system(size: 10).monospacedDigit())
                                .foregroundStyle(Color.white.opacity(0.6))
                                .frame(width: 31, alignment: .trailing)
                                .accessibilityHidden(true)
                        }
                    }
                    Divider().padding(.vertical, 2)
                }
                introduction

                VStack(spacing: 0) {
                    permissionRow(
                        title: "Accessibility",
                        detail: "Window text and controls",
                        symbol: "accessibility",
                        granted: store.accessibilityGranted,
                        action: store.requestAccessibility
                    )
                    Rectangle().fill(NotchStyle.border).frame(height: 1).padding(.leading, 38)
                    permissionRow(
                        title: "Screen Recording",
                        detail: "The app's screenshot",
                        symbol: "rectangle.inset.filled",
                        granted: store.screenRecordingGranted,
                        action: store.requestScreenRecording
                    )
                }
                .background(NotchStyle.subtle, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(NotchStyle.border, lineWidth: 1))

                VStack(alignment: .leading, spacing: 6) {
                    Text(isReady ? "Recent shots stay in memory until you quit." : "Already enabled? Reopen to refresh macOS access.")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button(action: store.refreshPermissions) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(CompactPermissionButtonStyle())
                        if !isReady {
                            Button("Reopen app", action: store.reopenForPermissions)
                                .buttonStyle(CompactPermissionButtonStyle())
                                .help("Restart NotchShot after a permission change. Session captures will be cleared.")
                        }
                        Spacer(minLength: 0)
                    }
                }

                if !store.hasAvailableCaptureShortcut && !store.isRecordingShortcut {
                    Label("Choose another shortcut above, or capture from the menu bar.", systemImage: "keyboard")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.orange.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden, axes: .vertical)
        .defaultScrollAnchor(.top)
    }

    private var introduction: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: reviewingPermissions ? "lock.open" : "macwindow.on.rectangle")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(NotchStyle.accent)
                .frame(width: 28, height: 28)
                .background(NotchStyle.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(reviewingPermissions ? "Capture permissions" : isReady ? "Ready to capture" : "Allow app capture")
                    .font(.system(size: 13, weight: .semibold))
                Text(isReady
                     ? store.captureHintHelp
                     : "Allow NotchShot in System Settings to capture app images, text, and controls.")
                    .font(.system(size: 10))
                    .lineSpacing(2)
                    .foregroundStyle(Color.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func permissionRow(title: String, detail: String, symbol: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.6))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 11, weight: .semibold))
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if granted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(NotchStyle.accent)
                    .fixedSize()
            } else {
                Button("Enable", action: action)
                    .buttonStyle(CompactPermissionButtonStyle())
                    .accessibilityLabel("Enable \(title)")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 45)
    }
}

private struct CompactPermissionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.88))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(NotchStyle.subtle, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(NotchStyle.border, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}
