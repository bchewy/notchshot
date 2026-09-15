// SPDX-License-Identifier: MIT
import SwiftUI

struct ShortcutSettingsView: View {
    let shortcut: CaptureShortcut
    @Binding var isRecording: Bool
    @Binding var bothShiftEnabled: Bool
    let registrationError: String?
    let shortcutAvailable: Bool
    let onRecord: (CaptureShortcut) -> Void
    let onReset: () -> Void

    @State private var validationMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Capture shortcuts")
                .font(.system(size: 12, weight: .semibold))

            Toggle("Shift + Shift to capture", isOn: $bothShiftEnabled)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .tint(NotchStyle.accent)
            Text("Press left Shift + right Shift together.")
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.45))

            Rectangle().fill(NotchStyle.border).frame(height: 1)
                .padding(.vertical, 2)
            Text("Alternative shortcut")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.6))

            HStack(spacing: 8) {
                ShortcutRecorderView(
                    shortcut: shortcut,
                    isRecording: $isRecording,
                    validationMessage: $validationMessage,
                    onRecord: onRecord
                )
                .frame(maxWidth: .infinity)
                .frame(height: 32)

                Button("Reset") {
                    isRecording = false
                    validationMessage = nil
                    onReset()
                }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(Color.white.opacity(0.7))
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(NotchStyle.subtle, in: RoundedRectangle(cornerRadius: 7))
                .disabled(shortcut == .defaultShortcut && !isRecording)
                .accessibilityLabel("Reset capture shortcut")
                .help("Restore the alternative shortcut to ⌘⇧2.")
            }

            Text(feedback)
                .font(.system(size: 10))
                .foregroundStyle(hasError ? Color.orange.opacity(0.85) : Color.white.opacity(0.5))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 14, alignment: .topLeading)
                .accessibilityLabel(feedback)

        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NotchStyle.subtle, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(NotchStyle.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .onChange(of: isRecording) { _, recording in
            if !recording { validationMessage = nil }
        }
    }

    private var hasError: Bool {
        validationMessage != nil || (!isRecording && (registrationError != nil || !shortcutAvailable))
    }

    private var feedback: String {
        if let validationMessage { return validationMessage }
        if isRecording { return "Press keys with ⌘, ⌥ or ⌃. Esc cancels; Tab moves on." }
        if let registrationError { return registrationError }
        if !shortcutAvailable { return "Shortcut unavailable. Choose a different combination." }
        return "Click to record a shortcut with ⌘, ⌥ or ⌃."
    }
}
