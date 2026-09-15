// SPDX-License-Identifier: MIT
import AppKit
import ApplicationServices

/// Recognizes a clean overlap of the physical left and right Shift keys.
/// Flags are snapshots, not toggles: duplicate events cannot synthesize a press.
struct BothShiftChordDetector {
    enum ShiftKey: UInt16, Hashable {
        case left = 56
        case right = 60
    }

    // Device-specific bits in Apple's IOKit/hidsystem/IOLLEvent.h. Keep these
    // bits: deviceIndependentFlagsMask deliberately discards the distinction.
    private static let leftShiftMask: UInt = 0x00000002
    private static let rightShiftMask: UInt = 0x00000004
    private static let otherModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .function]

    private var pressedKeys: Set<ShiftKey> = []
    private var awaitingAllReleased: Bool

    init(shiftIsDown: Bool = false) {
        awaitingAllReleased = shiftIsDown
    }

    /// Keyboard or mouse activity cancels the current chord. Only a subsequent
    /// Shift flagsChanged reporting both keys up may rearm an interrupted chord.
    /// Mouse events sometimes lack device flags, so they must never clear this
    /// latch or erase an already observed held Shift key.
    mutating func cancel(shiftIsDown: Bool) {
        awaitingAllReleased = awaitingAllReleased || shiftIsDown || !pressedKeys.isEmpty
        pressedKeys.removeAll()
    }

    mutating func shiftChanged(
        key: ShiftKey,
        flags: NSEvent.ModifierFlags,
        hasPressedMouseButtons: Bool = false
    ) -> Bool {
        var currentKeys: Set<ShiftKey> = []
        if flags.rawValue & Self.leftShiftMask != 0 { currentKeys.insert(.left) }
        if flags.rawValue & Self.rightShiftMask != 0 { currentKeys.insert(.right) }
        let shiftIsDown = flags.contains(.shift)

        // If a synthetic/remote event supplies only the aggregate Shift flag,
        // there is no reliable evidence that both physical keys are down.
        guard shiftIsDown == !currentKeys.isEmpty else {
            cancel(shiftIsDown: shiftIsDown || !currentKeys.isEmpty)
            return false
        }

        if currentKeys.isEmpty {
            pressedKeys.removeAll()
            awaitingAllReleased = false
            return false
        }

        guard !hasPressedMouseButtons, flags.intersection(Self.otherModifiers).isEmpty else {
            cancel(shiftIsDown: true)
            return false
        }
        guard !awaitingAllReleased else { return false }

        let previousKeys = pressedKeys
        pressedKeys = currentKeys
        guard currentKeys != previousKeys else { return false }

        // Both physical presses must be observed. Reject missing/out-of-order
        // snapshots instead of guessing whether an event was a press or release.
        guard currentKeys.symmetricDifference(previousKeys) == Set([key]) else {
            cancel(shiftIsDown: true)
            return false
        }
        guard currentKeys.contains(key), currentKeys.count == 2 else { return false }

        awaitingAllReleased = true
        return true
    }
}

/// Passive observation only: local events are returned unchanged, global events
/// cannot be consumed, and ordinary key characters/key codes are never read.
@MainActor
final class BothShiftShortcutService {
    var onTrigger: (() -> Void)?
    private(set) var isMonitoring = false

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var detector = BothShiftChordDetector()

    @discardableResult
    func start() -> Bool {
        guard AXIsProcessTrusted() else {
            stop()
            return false
        }
        if isMonitoring { return true }

        detector = BothShiftChordDetector(shiftIsDown: NSEvent.modifierFlags.contains(.shift))
        let mask: NSEvent.EventTypeMask = [
            .flagsChanged, .keyDown, .keyUp,
            .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .leftMouseUp, .rightMouseUp, .otherMouseUp,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .mouseMoved, .scrollWheel
        ]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event
        }

        guard globalMonitor != nil, localMonitor != nil else {
            stop()
            return false
        }
        isMonitoring = true
        return true
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        isMonitoring = false
        detector = BothShiftChordDetector()
    }

    private func handle(_ event: NSEvent) {
        guard event.type == .flagsChanged,
              let key = BothShiftChordDetector.ShiftKey(rawValue: event.keyCode) else {
            detector.cancel(shiftIsDown: event.modifierFlags.contains(.shift))
            return
        }

        // Caps Lock's persistent state is allowed; toggling it is a non-Shift
        // flagsChanged above, which interrupts an in-progress chord.
        if detector.shiftChanged(key: key, flags: event.modifierFlags, hasPressedMouseButtons: NSEvent.pressedMouseButtons != 0) {
            onTrigger?()
        }
    }
}
