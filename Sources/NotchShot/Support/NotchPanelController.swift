// SPDX-License-Identifier: MIT
import SwiftUI
import QuartzCore
import Observation

@MainActor
final class NotchPanelController {
    private let store: CaptureStore
    private let panel: NotchPanel
    let presentation: NotchPresentation
    private var motion: NotchMotion
    private var sizeMotion: NotchSizeMotion
    private var displayLink: CADisplayLink?
    private var currentDisplay: NotchDisplay?
    private let displays: @MainActor () -> [NotchDisplay]
    private let preferredDisplayID: @MainActor () -> CGDirectDisplayID?
    private let mouseLocation: @MainActor () -> CGPoint
    private let pressedMouseButtons: @MainActor () -> Int
    private let clock: @MainActor () -> TimeInterval
    private let motionClock: @MainActor () -> TimeInterval
    private let shouldReduceMotion: @MainActor () -> Bool
    private var screenFollowPolicy = NotchScreenFollowPolicy()
    private var screenFollowTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var screensSleeping = false
    private var wantsVisible = false
    private var collapsedSize: CGSize
    private var screenObserver: NSObjectProtocol?
    private var reduceMotionObserver: NSObjectProtocol?
    private let workspaceNotifications = NSWorkspace.shared.notificationCenter
    private var isExportPresented = false
    private var attentionMonitor: NotchAttentionMonitor?

    var isAnimating: Bool { displayLink != nil }
    var activeDisplayID: CGDirectDisplayID? { currentDisplay?.id }
    var compactLandingFrame: CGRect? {
        currentDisplay.map { NotchGeometry.frame(anchoredTo: $0.notchRect, size: CGSize(width: 28, height: 18)) }
    }

    init(store: CaptureStore,
         displays: @escaping @MainActor () -> [NotchDisplay] = { NotchPanelController.connectedDisplays() },
         preferredDisplayID: @escaping @MainActor () -> CGDirectDisplayID? = {
             NotchGeometry.preferredScreen.flatMap { NotchPanelController.displayID($0) }
         },
         mouseLocation: @escaping @MainActor () -> CGPoint = { NSEvent.mouseLocation },
         pressedMouseButtons: @escaping @MainActor () -> Int = { NSEvent.pressedMouseButtons },
         clock: @escaping @MainActor () -> TimeInterval = { CACurrentMediaTime() },
         motionClock: @escaping @MainActor () -> TimeInterval = { CACurrentMediaTime() },
         shouldReduceMotion: @escaping @MainActor () -> Bool = {
             NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
         }) {
        self.store = store
        self.displays = displays
        self.preferredDisplayID = preferredDisplayID
        self.mouseLocation = mouseLocation
        self.pressedMouseButtons = pressedMouseButtons
        self.clock = clock
        self.motionClock = motionClock
        self.shouldReduceMotion = shouldReduceMotion
        panel = NotchPanel(frame: .zero)
        let progress: CGFloat = store.isExpanded ? 1 : 0
        collapsedSize = NotchStyle.collapsedSize(notchSize: CGSize(width: store.notchWidth, height: store.notchHeight))
        let size = store.isExpanded ? NotchStyle.expandedSize(for: store.page) : collapsedSize
        presentation = NotchPresentation(progress: progress, size: size)
        let now = motionClock()
        motion = NotchMotion(progress: progress, at: now)
        sizeMotion = NotchSizeMotion(size: size, minimum: collapsedSize,
                                    maximum: Self.maximumSize(for: collapsedSize), at: now)
        let root = NotchRootView(store: store, presentation: presentation)
        let host = ShotDropHostingView(rootView: root)
        host.configureDropTarget(store: store)
        host.sizingOptions = []
        panel.contentView = host
        panel.onEscape = { [weak store] in store?.collapse() }
        attentionMonitor = NotchAttentionMonitor(panel: panel) { [weak store] snapshot in
            store?.updateNotchAttention(pointerInside: snapshot.pointerInside,
                                       keyboardFocused: snapshot.keyboardFocused,
                                       menuTracking: snapshot.menuTracking,
                                       mouseButtonDown: snapshot.mouseButtonDown,
                                       surfaceVisible: snapshot.surfaceVisible)
        } onActivity: { [weak store] in
            store?.noteNotchActivity()
        }
        store.onRefreshNotchAttention = { [weak self] in
            self?.attentionMonitor?.refresh()
        }
        store.onExportPresentationChange = { [weak self] isPresented in
            self?.setExportPresented(isPresented)
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.screenFollowPolicy.reset()
                self?.refreshScreenPlacement()
            }
        }
        reduceMotionObserver = workspaceNotifications.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.shouldReduceMotion() else { return }
                self.resynchronize(reason: "reduce-motion")
            }
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            workspaceObservers.append(workspaceNotifications.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.screensSleeping = true
                    self?.screenFollowPolicy.reset()
                    self?.stopScreenFollowTimer()
                    self?.updateAttentionMonitoring()
                }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            workspaceObservers.append(workspaceNotifications.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.screensSleeping = false
                    self?.screenFollowPolicy.reset()
                    self?.refreshScreenPlacement()
                }
            })
        }
        observeRequestedPresentation()
        resynchronize(reason: "initial")
    }

    deinit {
        displayLink?.invalidate()
        screenFollowTimer?.invalidate()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let reduceMotionObserver { workspaceNotifications.removeObserver(reduceMotionObserver) }
        workspaceObservers.forEach(workspaceNotifications.removeObserver)
    }

    func show() {
        wantsVisible = true
        guard !isExportPresented, currentDisplay != nil else { return }
        panel.orderFrontRegardless()
        updateAttentionMonitoring()
        refreshScreenPlacement()
    }

    private func setExportPresented(_ isPresented: Bool) {
        isExportPresented = isPresented
        if isPresented {
            screenFollowPolicy.reset()
            stopScreenFollowTimer()
            attentionMonitor?.setWatching(false)
            resynchronize(reason: "export-hide")
            panel.orderOut(nil)
        } else {
            resynchronize(reason: "export-return")
            show()
        }
    }

    private func configureGeometry() -> Bool {
        let available = displays()
        guard let display = available.first(where: { $0.id == currentDisplay?.id })
                ?? available.first(where: { $0.id == preferredDisplayID() }) ?? available.first else {
            currentDisplay = nil
            panel.notchAnchor = nil
            return false
        }
        currentDisplay = display
        let dimensions = display.notchRect.size
        store.notchWidth = dimensions.width
        store.notchHeight = dimensions.height
        collapsedSize = NotchStyle.collapsedSize(notchSize: dimensions)
        panel.notchAnchor = display.notchRect
        return true
    }

    private static func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    private static func connectedDisplays() -> [NotchDisplay] {
        NSScreen.screens.compactMap { screen in
            guard let id = displayID(screen) else { return nil }
            return NotchDisplay(id: id, frame: screen.frame,
                                notchRect: NotchGeometry.frame(on: screen, size: NotchGeometry.dimensions(for: screen)))
        }
    }

    /// Samples public pointer/display geometry. No key monitoring or extra
    /// capture permission is needed, and normal following never opens the shelf.
    func refreshScreenPlacement() {
        let available = displays()
        let pointer = mouseLocation()
        attentionMonitor?.refresh()
        let blocked = store.shouldDeferScreenMove || isExportPresented || screensSleeping || isAnimating
            || pressedMouseButtons() != 0
            || (panel.isVisible && panel.frame.insetBy(dx: -4, dy: -4).contains(pointer))
        let id = screenFollowPolicy.destination(displays: available, preferredID: preferredDisplayID(),
                                                currentID: currentDisplay?.id, pointer: pointer,
                                                enabled: store.followActiveScreen, blocked: blocked, now: clock())
        guard let target = available.first(where: { $0.id == id }) else {
            currentDisplay = nil
            panel.notchAnchor = nil
            stopDisplayLink()
            stopScreenFollowTimer()
            attentionMonitor?.setWatching(false)
            panel.orderOut(nil)
            return
        }
        if currentDisplay != target {
            let changesScreen = currentDisplay?.id != target.id
            let fade = changesScreen && panel.isVisible && !shouldReduceMotion()
            currentDisplay = target
            if fade { panel.alphaValue = 0 }
            // Re-anchor the same panel without sweeping across desktop content.
            resynchronize(reason: "display-placement")
            if wantsVisible && !isExportPresented { panel.orderFrontRegardless() }
            if fade {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.14
                    panel.animator().alphaValue = 1
                }
            } else { panel.alphaValue = 1 }
        }
        updateAttentionMonitoring()
        updateScreenFollowTimer()
    }

    private var needsScreenTracking: Bool {
        let available = displays()
        let home = available.first(where: { $0.id == preferredDisplayID() }) ?? available.first
        return available.count > 1 && (store.followActiveScreen || currentDisplay?.id != home?.id)
    }

    private func updateScreenFollowTimer() {
        guard needsScreenTracking, wantsVisible, panel.isVisible, !isExportPresented, !screensSleeping else {
            stopScreenFollowTimer()
            return
        }
        guard screenFollowTimer == nil else { return }
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshScreenPlacement() }
        }
        timer.tolerance = 0.025
        RunLoop.main.add(timer, forMode: .common)
        screenFollowTimer = timer
    }

    private func stopScreenFollowTimer() {
        screenFollowTimer?.invalidate()
        screenFollowTimer = nil
    }

    private func observeRequestedPresentation() {
        // This controller creates its root value once, outside a SwiftUI body.
        // An onChange modifier constructed here would retain the initial Bool.
        // Observe the store itself and re-arm after each observed setter ends.
        withObservationTracking {
            _ = store.isExpanded
            _ = store.page
            _ = store.autoCollapseEnabled
            _ = store.followActiveScreen
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observeRequestedPresentation()
                self.animateToTarget()
                self.refreshScreenPlacement()
            }
        }
    }

    private func animateToTarget() {
        updateAttentionMonitoring()
        guard !isExportPresented else {
            resynchronize(reason: "hidden-state-change")
            return
        }
        let previousDisplay = currentDisplay
        guard configureGeometry() else { stopDisplayLink(); return }
        if previousDisplay != currentDisplay {
            // A store observation can arrive before the screen-change notice.
            // Rebuild spring bounds along with the new display's notch size.
            resynchronize(reason: "presentation-display-change")
            refreshScreenPlacement()
            return
        }
        let now = motionClock()
        let reduceMotion = shouldReduceMotion()
        let sample = motion.retarget(to: store.isExpanded ? 1 : 0, at: now,
                                     reduceMotion: reduceMotion)
        let sizeSample = sizeMotion.retarget(to: targetSize, at: now, reduceMotion: reduceMotion)
        apply(sample, sizeSample: sizeSample, at: now, reason: "retarget")
        if !sample.isSettled || !sizeSample.isSettled { startDisplayLink() }
    }

    private func resynchronize(reason: String) {
        stopDisplayLink()
        guard configureGeometry() else { return }
        let now = motionClock()
        motion.reset(to: store.isExpanded ? 1 : 0, at: now)
        sizeMotion = NotchSizeMotion(size: targetSize, minimum: collapsedSize,
                                    maximum: Self.maximumSize(for: collapsedSize), at: now)
        apply(motion.sample(at: now), sizeSample: sizeMotion.sample(at: now), at: now, reason: reason)
    }

    private var targetSize: CGSize {
        store.isExpanded ? NotchStyle.expandedSize(for: store.page) : collapsedSize
    }

    private static func maximumSize(for collapsedSize: CGSize) -> CGSize {
        CGSize(width: max(collapsedSize.width, NotchStyle.expandedWidth),
               height: max(collapsedSize.height, NotchStyle.expandedHeight))
    }

    private func startDisplayLink() {
        guard displayLink == nil, let currentDisplay,
              let screen = NSScreen.screens.first(where: { Self.displayID($0) == currentDisplay.id })
                ?? panel.screen ?? NotchGeometry.preferredScreen else { return }
        let target = NotchDisplayLinkTarget { [weak self] link in
            guard let self else { link.invalidate(); return }
            // Direct native window updates render now. Sampling a future
            // targetTimestamp here could rewind at the next input's real time.
            let timestamp = self.motionClock()
            self.apply(self.motion.sample(at: timestamp), sizeSample: self.sizeMotion.sample(at: timestamp),
                       at: timestamp, reason: "tick")
        }
        // Recreated after each re-anchor, so this is the notch's active display.
        // A screen link also settles motion while AppKit hides the panel.
        let link = screen.displayLink(target: target, selector: #selector(NotchDisplayLinkTarget.tick(_:)))
        displayLink = link
        link.add(to: .main, forMode: .common)
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func apply(_ sample: NotchMotion.Sample, sizeSample: NotchSizeMotion.Sample,
                       at timestamp: TimeInterval, reason: String) {
        guard let display = currentDisplay else { return }
        let size = sizeSample.size
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            presentation.update(progress: sample.progress, size: size)
            panel.setFrame(NotchGeometry.frame(anchoredTo: display.notchRect, size: size), display: false)
            // AppKit rounds window edges to backing pixels. Give SwiftUI that
            // exact viewport so native and drawn bounds move together.
            presentation.update(progress: sample.progress, size: panel.frame.size)
            panel.contentView?.layoutSubtreeIfNeeded()
            panel.displayIfNeeded()
        }
        if sample.isSettled && sizeSample.isSettled {
            stopDisplayLink()
            releaseCollapsedKeyFocus()
        }
        logGeometry(sample: sample, sizeSample: sizeSample, at: timestamp, reason: reason, on: display)
        updateAttentionMonitoring()
    }

    private func updateAttentionMonitoring() {
        attentionMonitor?.setWatching((store.autoCollapseEnabled && store.isExpanded || needsScreenTracking)
                                      && !isExportPresented && !screensSleeping && panel.isVisible)
        attentionMonitor?.refresh()
    }

    private func releaseCollapsedKeyFocus() {
        if !store.isExpanded, panel.isKeyWindow, !isExportPresented {
            // Ordering out lets AppKit release key focus; ordering front does not
            // make the collapsed nonactivating panel key again. Do this only
            // after reaching the collapsed endpoint, never during the motion.
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
    }

    private func logGeometry(sample: NotchMotion.Sample, sizeSample: NotchSizeMotion.Sample,
                             at timestamp: TimeInterval, reason: String, on display: NotchDisplay) {
        guard let path = ProcessInfo.processInfo.environment["NOTCHSHOT_GEOMETRY_LOG"] else { return }
        let record = "time=\(timestamp) reason=\(reason) expanded=\(store.isExpanded) page=\(store.page) progress=\(sample.progress) velocity=\(sample.velocity) sizeVelocity=\(sizeSample.velocity) settled=\(sample.isSettled && sizeSample.isSettled) screen=\(display.frame) displayID=\(display.id) panel=\(panel.frame) host=\(String(describing: panel.contentView?.frame)) presentation=\(presentation.size)\n"
        // Opt-in local diagnostics contain geometry only, never capture content.
        let url = URL(fileURLWithPath: path)
        if let file = try? FileHandle(forWritingTo: url) {
            defer { try? file.close() }
            _ = try? file.seekToEnd()
            try? file.write(contentsOf: Data(record.utf8))
        } else {
            try? Data(record.utf8).write(to: url)
        }
    }
}

/// CADisplayLink retains its target; this wrapper's callback captures the
/// controller weakly so an interrupted animation cannot retain the controller.
@MainActor
private final class NotchDisplayLinkTarget: NSObject {
    private let callback: (CADisplayLink) -> Void

    init(callback: @escaping (CADisplayLink) -> Void) {
        self.callback = callback
    }

    @objc func tick(_ link: CADisplayLink) { callback(link) }
}
