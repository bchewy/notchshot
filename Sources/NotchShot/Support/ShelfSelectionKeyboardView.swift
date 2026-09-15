// SPDX-License-Identifier: MIT
import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Adds selection commands only to this panel's responder scope. Hover copying
/// still uses its existing short-lived global shortcut while another app is active.
struct ShelfSelectionKeyboardView: NSViewRepresentable {
    let store: CaptureStore

    func makeNSView(context: Context) -> ShelfSelectionKeyboardNSView { ShelfSelectionKeyboardNSView() }
    func updateNSView(_ view: ShelfSelectionKeyboardNSView, context: Context) { view.store = store }
    static func dismantleNSView(_ view: ShelfSelectionKeyboardNSView, coordinator: ()) { view.stop() }
}

@MainActor
final class ShelfSelectionKeyboardNSView: NSView {
    weak var store: CaptureStore?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stop()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.handle(event) == true }
            return consumed ? nil : event
        }
    }

    func handle(_ event: NSEvent) -> Bool {
        guard let window, event.window === window, window.isKeyWindow,
              let store, store.isExpanded, store.page == .shelf, store.isSelectingShots,
              !store.isRecordingShortcut,
              !(window.firstResponder is NSTextView), !(window.firstResponder is NSTextField),
              event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command else { return false }
        switch Int(event.keyCode) {
        case kVK_ANSI_C:
            guard store.selectedShotCount > 0 else { return false }
            if !event.isARepeat { return store.copyShelfSelection() }
            return true
        case kVK_ANSI_A:
            if !event.isARepeat { store.selectAllShelfShots() }
            return true
        default: return false
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
}
