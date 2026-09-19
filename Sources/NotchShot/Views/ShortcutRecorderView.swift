// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI

/// SwiftUI owns the saved shortcut. This native button owns keyboard focus only
/// during an explicitly requested recording session.
struct ShortcutRecorderView: NSViewRepresentable {
    @Environment(\.notchTheme) private var theme
    let shortcut: CaptureShortcut
    @Binding var isRecording: Bool
    @Binding var validationMessage: String?
    let onRecord: (CaptureShortcut) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        ShortcutRecorderButton(frame: .zero)
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.onRecordingChange = { isRecording = $0 }
        button.onValidationChange = { validationMessage = $0 }
        button.onRecord = onRecord
        button.accentColor = theme.nsAccent
        button.setShortcut(shortcut)
        if !isRecording { button.endRecording(notify: false) }
    }

    static func dismantleNSView(_ button: ShortcutRecorderButton, coordinator: ()) {
        let wasRecording = button.isRecording
        let onRecordingChange = button.onRecordingChange
        button.endRecording(notify: false)
        button.onRecordingChange = nil
        button.onValidationChange = nil
        button.onRecord = nil
        // Dismantling may run during a SwiftUI update. Restore global shortcuts
        // on the next main turn without mutating a binding inside that update.
        if wasRecording {
            DispatchQueue.main.async { onRecordingChange?(false) }
        }
    }
}

final class ShortcutRecorderButton: NSButton {
    private(set) var isRecording = false
    var accentColor = NotchTheme.mint.nsAccent {
        didSet { updateAppearance() }
    }
    var onRecordingChange: ((Bool) -> Void)?
    var onValidationChange: ((String?) -> Void)?
    var onRecord: ((CaptureShortcut) -> Void)?

    private var shortcut = CaptureShortcut.defaultShortcut
    private var mouseMonitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setButtonType(.momentaryPushIn)
        isBordered = false
        focusRingType = .exterior
        font = .monospacedSystemFont(ofSize: 13, weight: .semibold)
        contentTintColor = .white
        alignment = .center
        target = self
        action = #selector(toggleRecording)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.borderWidth = 1
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("ShortcutRecorderButton is created programmatically")
    }

    deinit {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        NotificationCenter.default.removeObserver(self)
    }

    override var acceptsFirstResponder: Bool { true }
    override var needsPanelToBecomeKey: Bool { true }
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 32)
    }

    func setShortcut(_ value: CaptureShortcut) {
        shortcut = value
        updateAppearance()
    }

    @objc private func toggleRecording() {
        if isRecording { endRecording() } else { beginRecording() }
    }

    func beginRecording() {
        guard !isRecording, isEnabled, let window else { return }
        // A nonactivating notch panel does not take keyboard focus on its own.
        window.makeKey()
        guard window.makeFirstResponder(self) else { return }
        isRecording = true
        onValidationChange?(nil)
        updateAppearance()
        onRecordingChange?(true)

        NotificationCenter.default.addObserver(
            self, selector: #selector(windowResignedKey),
            name: NSWindow.didResignKeyNotification, object: window
        )
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self, self.isRecording else { return event }
            if event.window !== self.window || !self.bounds.contains(self.convert(event.locationInWindow, from: nil)) {
                self.endRecording()
            }
            return event
        }
    }

    func endRecording(notify: Bool = true, relinquishFocus: Bool = true) {
        guard isRecording else { return }
        isRecording = false
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        updateAppearance()
        if notify { onRecordingChange?(false) }
        if relinquishFocus, window?.firstResponder === self {
            window?.makeFirstResponder(nil)
        }
    }

    @objc private func windowResignedKey() { endRecording() }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { endRecording(relinquishFocus: false) }
        return accepted
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window { endRecording() }
        super.viewWillMove(toWindow: newWindow)
    }

    override func keyDown(with event: NSEvent) {
        if !handleRecordingKey(event) { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Consume Command combinations before they can reach app menus or
        // SwiftUI keyboard shortcuts. The saved global hotkey is suspended by
        // the owner while the recording binding is true.
        if handleRecordingKey(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    @discardableResult
    private func handleRecordingKey(_ event: NSEvent) -> Bool {
        guard isRecording, event.type == .keyDown else { return false }
        guard !event.isARepeat else { return true }
        switch event.keyCode {
        case 53: // Escape cancels without collapsing the containing panel.
            onValidationChange?(nil)
            endRecording()
        case 48: // Tab cancels and continues ordinary keyboard navigation.
            let moveBackward = event.modifierFlags.contains(.shift)
            onValidationChange?(nil)
            endRecording(relinquishFocus: false)
            if moveBackward { window?.selectPreviousKeyView(self) }
            else { window?.selectNextKeyView(self) }
        default:
            guard let candidate = CaptureShortcut(keyCode: event.keyCode, modifierFlags: event.modifierFlags) else {
                onValidationChange?("Include ⌘, ⌥ or ⌃ with a key. Esc cancels.")
                return true
            }
            onValidationChange?(nil)
            onRecord?(candidate)
            endRecording()
        }
        return true
    }

    private func updateAppearance() {
        title = isRecording ? "Press keys…" : shortcut.displayString
        layer?.backgroundColor = NSColor.white.withAlphaComponent(isRecording ? 0.1 : 0.055).cgColor
        layer?.borderColor = isRecording
            ? accentColor.withAlphaComponent(0.85).cgColor
            : NSColor.white.withAlphaComponent(0.13).cgColor
        setAccessibilityLabel(isRecording ? "Recording capture shortcut" : "Change capture shortcut")
        setAccessibilityValue(isRecording ? "Waiting for shortcut keys" : shortcut.displayString)
        setAccessibilityHelp("Click to record a keyboard shortcut with Command, Option, or Control. Escape cancels.")
        toolTip = isRecording ? "Press shortcut keys, or Escape to cancel." : "Click to change the capture shortcut."
        needsDisplay = true
    }
}
