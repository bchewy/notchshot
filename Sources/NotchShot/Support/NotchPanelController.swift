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
    private var currentScreen: NSScreen?
    private var collapsedSize: CGSize
    private var screenObserver: NSObjectProtocol?
    private var reduceMotionObserver: NSObjectProtocol?
    private let workspaceNotifications = NSWorkspace.shared.notificationCenter
    private var isExportPresented = false
    private var attentionMonitor: NotchAttentionMonitor?

    var isAnimating: Bool { displayLink != nil }

    init(store: CaptureStore) {
        self.store = store
        panel = NotchPanel(frame: .zero)
        let progress: CGFloat = store.isExpanded ? 1 : 0
        collapsedSize = NotchStyle.collapsedSize(notchSize: CGSize(width: store.notchWidth, height: store.notchHeight))
        let size = store.isExpanded ? NotchStyle.expandedSize(for: store.page) : collapsedSize
        presentation = NotchPresentation(progress: progress, size: size)
        let now = CACurrentMediaTime()
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
            Task { @MainActor in self?.resynchronize(reason: "screen-change") }
        }
        reduceMotionObserver = workspaceNotifications.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
                self?.resynchronize(reason: "reduce-motion")
            }
        }
        observeRequestedPresentation()
        resynchronize(reason: "initial")
    }

    deinit {
        displayLink?.invalidate()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let reduceMotionObserver { workspaceNotifications.removeObserver(reduceMotionObserver) }
    }

    func show() {
        guard !isExportPresented else { return }
        panel.orderFrontRegardless()
        updateAttentionMonitoring()
    }

    private func setExportPresented(_ isPresented: Bool) {
        isExportPresented = isPresented
        if isPresented {
            attentionMonitor?.setWatching(false)
            resynchronize(reason: "export-hide")
            panel.orderOut(nil)
        } else {
            resynchronize(reason: "export-return")
            show()
        }
    }

    private func configureGeometry() -> Bool {
        guard let screen = NotchGeometry.preferredScreen else { return false }
        currentScreen = screen
        let dimensions = NotchGeometry.dimensions(for: screen)
        store.notchWidth = dimensions.width
        store.notchHeight = dimensions.height
        collapsedSize = NotchStyle.collapsedSize(notchSize: dimensions)
        panel.notchAnchor = NotchGeometry.frame(on: screen, size: dimensions)
        return true
    }

    private func observeRequestedPresentation() {
        // This controller creates its root value once, outside a SwiftUI body.
        // An onChange modifier constructed here would retain the initial Bool.
        // Observe the store itself and re-arm after each observed setter ends.
        withObservationTracking {
            _ = store.isExpanded
            _ = store.page
            _ = store.autoCollapseEnabled
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observeRequestedPresentation()
                self.animateToTarget()
            }
        }
    }

    private func animateToTarget() {
        updateAttentionMonitoring()
        guard !isExportPresented else {
            resynchronize(reason: "hidden-state-change")
            return
        }
        guard configureGeometry() else { stopDisplayLink(); return }
        let now = CACurrentMediaTime()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let sample = motion.retarget(to: store.isExpanded ? 1 : 0, at: now,
                                     reduceMotion: reduceMotion)
        let sizeSample = sizeMotion.retarget(to: targetSize, at: now, reduceMotion: reduceMotion)
        apply(sample, sizeSample: sizeSample, at: now, reason: "retarget")
        if !sample.isSettled || !sizeSample.isSettled { startDisplayLink() }
    }

    private func resynchronize(reason: String) {
        stopDisplayLink()
        guard configureGeometry() else { return }
        let now = CACurrentMediaTime()
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
        guard displayLink == nil, let screen = currentScreen else { return }
        let target = NotchDisplayLinkTarget { [weak self] link in
            guard let self else { link.invalidate(); return }
            // Direct native window updates render now. Sampling a future
            // targetTimestamp here could rewind at the next input's real time.
            let timestamp = CACurrentMediaTime()
            self.apply(self.motion.sample(at: timestamp), sizeSample: self.sizeMotion.sample(at: timestamp),
                       at: timestamp, reason: "tick")
        }
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
        guard let screen = currentScreen else { return }
        let size = sizeSample.size
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            presentation.update(progress: sample.progress, size: size)
            panel.setFrame(NotchGeometry.frame(on: screen, size: size), display: false)
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
        logGeometry(sample: sample, sizeSample: sizeSample, at: timestamp, reason: reason, on: screen)
        updateAttentionMonitoring()
    }

    private func updateAttentionMonitoring() {
        attentionMonitor?.setWatching(store.autoCollapseEnabled && store.isExpanded
                                      && !isExportPresented && panel.isVisible)
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
                             at timestamp: TimeInterval, reason: String, on screen: NSScreen) {
        guard let path = ProcessInfo.processInfo.environment["NOTCHSHOT_GEOMETRY_LOG"] else { return }
        let record = "time=\(timestamp) reason=\(reason) expanded=\(store.isExpanded) page=\(store.page) progress=\(sample.progress) velocity=\(sample.velocity) sizeVelocity=\(sizeSample.velocity) settled=\(sample.isSettled && sizeSample.isSettled) screen=\(screen.frame) panel=\(panel.frame) host=\(String(describing: panel.contentView?.frame)) presentation=\(presentation.size)\n"
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
