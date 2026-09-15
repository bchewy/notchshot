// SPDX-License-Identifier: MIT
import AppKit

/// Observes the small native boundary SwiftUI cannot reliably describe: the
/// pointer over a resizing window, real keyboard ownership, and native menus.
/// It never reads key contents or requires a global keyboard event tap.
@MainActor
final class NotchAttentionMonitor {
    struct Snapshot: Equatable {
        var pointerInside = false
        var keyboardFocused = false
        var menuTracking = false
        var mouseButtonDown = false
        var surfaceVisible = false
    }

    enum ResponderKind {
        case none, control, editableText, selectedText
    }

    private weak var panel: NSWindow?
    private let onSnapshot: (Snapshot) -> Void
    private let onActivity: () -> Void
    private let mouseLocation: () -> NSPoint
    private let pressedMouseButtons: () -> Int
    private var timer: Timer?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var trackingMenus: Set<ObjectIdentifier> = []
    private weak var keyboardInteractionWindow: NSWindow?
    private var pointerDismissedKeyboardFocus = false
    private var generation = 0
    private(set) var isWatching = false
    private(set) var lastSnapshot = Snapshot()

    init(panel: NSWindow,
         mouseLocation: @escaping () -> NSPoint = { NSEvent.mouseLocation },
         pressedMouseButtons: @escaping () -> Int = { NSEvent.pressedMouseButtons },
         onSnapshot: @escaping (Snapshot) -> Void,
         onActivity: @escaping () -> Void) {
        self.panel = panel
        self.mouseLocation = mouseLocation
        self.pressedMouseButtons = pressedMouseButtons
        self.onSnapshot = onSnapshot
        self.onActivity = onActivity
    }

    deinit {
        timer?.invalidate()
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func setWatching(_ watching: Bool) {
        guard watching != isWatching else { return }
        generation += 1
        isWatching = watching
        if watching {
            installMonitors()
            refresh()
        } else {
            timer?.invalidate()
            timer = nil
            if let localMonitor { NSEvent.removeMonitor(localMonitor) }
            if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
            localMonitor = nil
            globalMonitor = nil
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            trackingMenus.removeAll()
            keyboardInteractionWindow = nil
            pointerDismissedKeyboardFocus = false
            publish(Snapshot())
        }
    }

    /// Also called immediately before the store's deadline and after frame
    /// changes. Sampling is not activity: animation ticks cannot extend a timer.
    func refresh() {
        guard isWatching else { return }
        guard let panel, Self.isRendered(panel) else {
            setWatching(false)
            return
        }
        let windows = interactiveWindows(root: panel)
        let pointer = mouseLocation()
        let keyWindow = windows.first(where: \.isKeyWindow)
        let responder = keyWindow.map { responderKind(in: $0) } ?? .none
        let keyboardFocused = !pointerDismissedKeyboardFocus && Self.hasMeaningfulKeyboardFocus(
            windowIsKey: keyWindow != nil,
            responder: responder,
            keyboardInteractionOwned: keyWindow != nil && keyboardInteractionWindow === keyWindow
        )
        publish(Snapshot(
            pointerInside: windows.contains { $0.frame.insetBy(dx: -4, dy: -4).contains(pointer) },
            keyboardFocused: keyboardFocused,
            menuTracking: !trackingMenus.isEmpty,
            mouseButtonDown: pressedMouseButtons() != 0,
            surfaceVisible: true
        ))
    }

    /// A nonactivating panel can remain key after its recorder has relinquished
    /// first responder. That alone does not mean the user is still working in it.
    static func hasMeaningfulKeyboardFocus(windowIsKey: Bool, responder: ResponderKind,
                                          keyboardInteractionOwned: Bool) -> Bool {
        guard windowIsKey else { return false }
        switch responder {
        case .editableText, .selectedText: return true
        case .control: return keyboardInteractionOwned
        case .none: return false
        }
    }

    private func publish(_ snapshot: Snapshot) {
        guard snapshot != lastSnapshot else { return }
        lastSnapshot = snapshot
        onSnapshot(snapshot)
    }

    private func installMonitors() {
        let token = generation
        let mouseEvents: NSEvent.EventTypeMask = [
            .mouseMoved, .mouseEntered, .mouseExited, .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel
        ]
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: mouseEvents.union([.keyDown, .keyUp, .flagsChanged])
        ) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handle(event, isLocal: true, generation: token)
            }
            return event
        }
        // Mouse-only global monitoring works without Accessibility permission.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handle(event, isLocal: false, generation: token)
            }
        }

        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                     NSWindow.didMoveNotification, NSWindow.didResizeNotification,
                     NSWindow.didChangeOcclusionStateNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notice in
                MainActor.assumeIsolated {
                    guard let self, self.isWatching, self.generation == token,
                          let window = notice.object as? NSWindow, self.belongsToPanel(window) else { return }
                    if name == NSWindow.didResignKeyNotification {
                        self.keyboardInteractionWindow = nil
                    } else if name == NSWindow.didBecomeKeyNotification {
                        self.pointerDismissedKeyboardFocus = false
                    }
                    self.refresh()
                }
            })
        }
        for name in [NSMenu.didBeginTrackingNotification, NSMenu.didEndTrackingNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notice in
                MainActor.assumeIsolated {
                    guard let self, self.isWatching, self.generation == token,
                          let menu = notice.object as? NSMenu else { return }
                    if name == NSMenu.didBeginTrackingNotification {
                        self.trackingMenus.insert(ObjectIdentifier(menu))
                        self.onActivity()
                    } else {
                        self.trackingMenus.remove(ObjectIdentifier(menu))
                    }
                    self.refresh()
                }
            })
        }
        let timer = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.generation == token else { return }
                self.refresh()
            }
        }
        timer.tolerance = 0.025
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func handle(_ event: NSEvent, isLocal: Bool, generation token: Int) {
        guard isWatching, generation == token else { return }
        let belongs = isLocal && event.window.map(belongsToPanel) == true
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            keyboardInteractionWindow = nil
            pointerDismissedKeyboardFocus = !belongs
        case .keyDown:
            if belongs {
                keyboardInteractionWindow = event.window
                pointerDismissedKeyboardFocus = false
            }
        default: break
        }
        if belongs { onActivity() }
        refresh()
        // Local monitors run before dispatch; the control can change first
        // responder (or release a shortcut recorder) while handling this event.
        if isLocal && event.type != .mouseMoved && event.type != .mouseEntered && event.type != .mouseExited {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isWatching, self.generation == token else { return }
                self.refresh()
            }
        }
    }

    private func responderKind(in window: NSWindow) -> ResponderKind {
        guard let responder = window.firstResponder, responder !== window else { return .none }
        if let text = responder as? NSTextView {
            if text.isEditable { return .editableText }
            if text.isSelectable, text.selectedRanges.contains(where: { $0.rangeValue.length > 0 }) {
                return .selectedText
            }
        }
        if let field = responder as? NSTextField, field.isEditable { return .editableText }
        return .control
    }

    private static func isRendered(_ window: NSWindow) -> Bool {
        window.isVisible && !window.isMiniaturized && window.alphaValue > 0
    }

    private func interactiveWindows(root: NSWindow) -> [NSWindow] {
        guard Self.isRendered(root), !root.ignoresMouseEvents else { return [] }
        return [root] + (root.childWindows ?? []).flatMap { interactiveWindows(root: $0) }
    }

    private func belongsToPanel(_ window: NSWindow) -> Bool {
        guard let panel, Self.isRendered(window), !window.ignoresMouseEvents else { return false }
        var candidate: NSWindow? = window
        while let current = candidate {
            if current === panel { return true }
            candidate = current.parent
        }
        return false
    }
}
