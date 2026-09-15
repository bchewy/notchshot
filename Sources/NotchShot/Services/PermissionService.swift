// SPDX-License-Identifier: MIT
import AppKit
import ApplicationServices
import CoreGraphics

struct PermissionStatus: Sendable {
    let accessibility: Bool
    let screenRecording: Bool
}

@MainActor
enum PermissionService {
    /// Preflight checks never display a permission prompt.
    static func status() -> PermissionStatus {
        PermissionStatus(
            accessibility: AXIsProcessTrusted(),
            screenRecording: CGPreflightScreenCaptureAccess()
        )
    }

    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        openAccessibilitySettings()
    }

    static func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
        openScreenRecordingSettings()
    }

    static func openAccessibilitySettings() {
        openSettings("Privacy_Accessibility")
    }

    static func openScreenRecordingSettings() {
        openSettings("Privacy_ScreenCapture")
    }

    private static func openSettings(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }
}
