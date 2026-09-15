// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI

struct ShotHoverAnchorView: NSViewRepresentable {
    let capture: CaptureResult
    let controller: ShotHoverPreviewController
    let isEnabled: Bool
    var isCopyEnabled = true
    var copyLabel = "Copy shot"
    var clickLabel = "Click shot to open"
    let copyShot: () -> Bool
    let onHover: (Bool) -> Void

    func makeNSView(context: Context) -> ShotHoverAnchorNSView {
        ShotHoverAnchorNSView()
    }

    func updateNSView(_ view: ShotHoverAnchorNSView, context: Context) {
        view.configure(capture: capture, controller: controller, isEnabled: isEnabled,
                       isCopyEnabled: isCopyEnabled, copyLabel: copyLabel, clickLabel: clickLabel, copyShot: copyShot, onHover: onHover)
    }

    static func dismantleNSView(_ view: ShotHoverAnchorNSView, coordinator: ()) {
        view.stop()
    }
}

/// Tracks the visible part of a thumbnail while allowing its SwiftUI button to
/// keep all clicks. Per-view ownership prevents a late exit hiding the next shot.
@MainActor
final class ShotHoverAnchorNSView: NSView {
    let owner = UUID()
    private(set) var isPreviewEnabled = false
    private var capture: CaptureResult?
    private weak var controller: ShotHoverPreviewController?
    private var onHover: ((Bool) -> Void)?
    private var copyShot: (() -> Bool)?
    private var isCopyEnabled = true
    private var copyLabel = "Copy shot"
    private var clickLabel = "Click shot to open"
    private var tracking: NSTrackingArea?
    private var hovering = false
    private var hoverFrame: NSRect?
    private var pointerRefresh: DispatchWorkItem?
    private let pointerTargetsWindow: @MainActor (NSWindow, NSPoint) -> Bool

    init(frame: NSRect = .zero,
         pointerTargetsWindow: (@MainActor (NSWindow, NSPoint) -> Bool)? = nil) {
        self.pointerTargetsWindow = pointerTargetsWindow ?? { window, point in
            NSWindow.windowNumber(at: window.convertPoint(toScreen: point), belowWindowWithWindowNumber: 0) == window.windowNumber
        }
        super.init(frame: frame)
        // Modern AppKit views can expose a visibleRect larger than their own
        // bounds. Each tile must own only its own area, never a neighbor's.
        clipsToBounds = true
    }

    required init?(coder: NSCoder) { nil }

    var isPointerInside: Bool {
        guard let window, window.isVisible, window.occlusionState.contains(.visible),
              !isHiddenOrHasHiddenAncestor, !visibleRect.isEmpty else { return false }
        let point = window.mouseLocationOutsideOfEventStream
        return bounds.intersection(visibleRect).contains(convert(point, from: nil)) && pointerTargetsWindow(window, point)
    }

    func configure(capture: CaptureResult, controller: ShotHoverPreviewController,
                   isEnabled: Bool, isCopyEnabled: Bool = true,
                   copyLabel: String = "Copy shot", clickLabel: String = "Click shot to open",
                   copyShot: @escaping () -> Bool, onHover: @escaping (Bool) -> Void) {
        let needsPointerRefresh = isEnabled && (!isPreviewEnabled || self.capture?.id != capture.id)
        if self.capture?.id != capture.id || !isEnabled { stop() }
        self.capture = capture
        self.controller = controller
        self.onHover = onHover
        self.copyShot = copyShot
        self.isCopyEnabled = isCopyEnabled
        self.copyLabel = copyLabel
        self.clickLabel = clickLabel
        isPreviewEnabled = isEnabled
        if hovering {
            controller.updateHints(owner: owner, isCopyEnabled: isCopyEnabled, copyLabel: copyLabel, clickLabel: clickLabel)
        }
        if needsPointerRefresh { schedulePointerRefresh() }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        tracking = area
        addTrackingArea(area)
        if hovering && (!isPointerInside || hoverFrame != convert(bounds, to: nil)) {
            exitHover(deferNotification: true)
        }
        schedulePointerRefresh()
    }

    override func mouseEntered(with event: NSEvent) {
        reconcileHover()
    }

    override func mouseMoved(with event: NSEvent) {
        reconcileHover()
    }

    /// Entry can happen during SwiftUI layout or while previews are disabled.
    /// Reconcile the full visible tile on movement as well, without restarting
    /// the preview's dwell time for every mouse event.
    func reconcileHover() {
        guard isPreviewEnabled, isPointerInside, let capture else {
            if hovering { exitHover() }
            return
        }
        let frame = convert(bounds, to: nil)
        if hovering && hoverFrame != frame { exitHover() }
        guard !hovering else { return }
        hovering = true
        hoverFrame = frame
        onHover?(true)
        controller?.request(capture: capture, anchor: self, isCopyEnabled: isCopyEnabled,
                            copyLabel: copyLabel, clickLabel: clickLabel) { [weak self] in
            guard let self, self.isPreviewEnabled, self.isPointerInside,
                  self.capture?.id == capture.id else { return false }
            return self.copyShot?() == true
        }
    }

    override func mouseExited(with event: NSEvent) { exitHover() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stop() }
        else { schedulePointerRefresh() }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func stop() {
        pointerRefresh?.cancel()
        pointerRefresh = nil
        isPreviewEnabled = false
        hovering = false
        hoverFrame = nil
        controller?.dismiss(owner: owner)
    }

    func previewDidDismiss(recheckPointer: Bool = false) {
        hovering = false
        hoverFrame = nil
        // Dismantling/geometry changes can occur during a SwiftUI update.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.hovering else { return }
            self.onHover?(false)
        }
        if recheckPointer { schedulePointerRefresh() }
    }

    private func schedulePointerRefresh() {
        pointerRefresh?.cancel()
        guard isPreviewEnabled else { return }
        // Keep observable SwiftUI changes outside updateNSView/layout callbacks.
        let refresh = DispatchWorkItem { [weak self] in
            self?.pointerRefresh = nil
            self?.reconcileHover()
        }
        pointerRefresh = refresh
        DispatchQueue.main.async(execute: refresh)
    }

    private func exitHover(deferNotification: Bool = false) {
        hovering = false
        hoverFrame = nil
        controller?.dismiss(owner: owner)
        // Controller dismissal already queues the callback through
        // previewDidDismiss; native layout must not write SwiftUI state here.
        if !deferNotification { onHover?(false) }
    }
}
