// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI

/// A passive child window lets previews extend beyond the small notch without
/// resizing it, taking keyboard focus, or covering a thumbnail's hit target.
@MainActor
final class ShotHoverPreviewController {
    private var pending: Task<Void, Never>?
    private var owner: UUID?
    private var panel: ShotHoverPreviewPanel?
    private weak var activeAnchor: ShotHoverAnchorNSView?
    private var observers: [NSObjectProtocol] = []
    private let store: CaptureStore?
    private let hoverCopy: HoverCopyShortcutService
    private let previewDelay: Duration
    private var activeCapture: CaptureResult?
    private var activeCopyAction: (() -> Bool)?
    private var isCopyEnabled = true
    private var copyLabel = "Copy shot"
    private var clickLabel = "Click shot to open"

    init(store: CaptureStore? = nil, hoverCopy: HoverCopyShortcutService? = nil,
         previewDelay: Duration = .milliseconds(120)) {
        self.store = store
        self.hoverCopy = hoverCopy ?? HoverCopyShortcutService()
        self.previewDelay = previewDelay
    }

    func request(capture: CaptureResult, anchor: ShotHoverAnchorNSView,
                 isCopyEnabled: Bool = true,
                 copyLabel: String = "Copy shot", clickLabel: String = "Click shot to open",
                 copyShot: @escaping () -> Bool) {
        dismiss()
        guard let parent = anchor.window else { return }
        owner = anchor.owner
        activeAnchor = anchor
        activeCapture = capture
        activeCopyAction = copyShot
        self.isCopyEnabled = isCopyEnabled
        self.copyLabel = copyLabel
        self.clickLabel = clickLabel
        let originalWindowFrame = parent.frame
        let originalAnchorFrame = anchor.convert(anchor.bounds, to: nil)
        // Begin at pointer entry, so Cmd-C works before the preview delay.
        // Empty selection mode can still preview without taking Copy away.
        configureCopyShortcut()
        observeInvalidation(of: parent)
        pending = Task { @MainActor [weak self, weak anchor] in
            do { try await Task.sleep(for: self?.previewDelay ?? .milliseconds(120)) } catch { return }
            guard let self, let anchor, self.owner == anchor.owner else { return }
            guard anchor.isPreviewEnabled, anchor.isPointerInside,
                  let window = anchor.window, window.isVisible,
                  window.frame == originalWindowFrame,
                  anchor.convert(anchor.bounds, to: nil) == originalAnchorFrame else {
                self.dismiss(owner: anchor.owner, recheckPointer: true)
                return
            }
            self.present(capture: capture, anchor: anchor, parent: window)
        }
    }

    func updateHints(owner: UUID, isCopyEnabled: Bool, copyLabel: String, clickLabel: String) {
        guard self.owner == owner else { return }
        let availabilityChanged = self.isCopyEnabled != isCopyEnabled
        guard availabilityChanged || self.copyLabel != copyLabel || self.clickLabel != clickLabel else { return }
        self.isCopyEnabled = isCopyEnabled
        self.copyLabel = copyLabel
        self.clickLabel = clickLabel
        if availabilityChanged { configureCopyShortcut() }
        if let capture = activeCapture, let host = panel?.contentView as? NSHostingView<ThemedShotHoverPreview> {
            host.rootView = previewView(for: capture)
        }
    }

    private func configureCopyShortcut() {
        hoverCopy.stop()
        guard isCopyEnabled, let anchor = activeAnchor, let parent = anchor.window,
              let capture = activeCapture, let copyShot = activeCopyAction else { return }
        let originalWindowFrame = parent.frame
        let originalAnchorFrame = anchor.convert(anchor.bounds, to: nil)
        // The validity check runs again at key delivery, covering teardown and
        // geometry races even while the passive preview has not yet appeared.
        hoverCopy.begin(owner: anchor.owner, captureID: capture.id, isValid: { [weak anchor, weak parent] in
            guard let anchor, let parent else { return false }
            return anchor.isPreviewEnabled && anchor.isPointerInside && parent.isVisible &&
                anchor.window === parent && parent.frame == originalWindowFrame &&
                anchor.convert(anchor.bounds, to: nil) == originalAnchorFrame
        }, copy: copyShot)
    }

    func dismiss(owner: UUID? = nil, recheckPointer: Bool = false) {
        if let owner, self.owner != owner { return }
        pending?.cancel()
        pending = nil
        hoverCopy.stop()
        self.owner = nil
        activeAnchor?.previewDidDismiss(recheckPointer: recheckPointer)
        activeAnchor = nil
        activeCapture = nil
        activeCopyAction = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        if let panel {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
            panel.close()
        }
        panel = nil
    }

    private func present(capture: CaptureResult, anchor: NSView, parent: NSWindow) {
        guard let screen = parent.screen else { return }
        let thumbnail = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let frame = Self.previewFrame(thumbnail: thumbnail, shelf: parent.frame,
                                      screen: screen.visibleFrame, size: ShotHoverPreviewView.size)
        let panel = ShotHoverPreviewPanel(contentRect: frame)
        let host = NSHostingView(rootView: previewView(for: capture))
        host.sizingOptions = []
        panel.contentView = host
        panel.setFrame(frame, display: false)
        self.panel = panel
        let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = reducedMotion ? 1 : 0
        parent.addChildWindow(panel, ordered: .above)
        panel.orderFrontRegardless()
        if !reducedMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                panel.animator().alphaValue = 1
            }
        }
    }

    private func previewView(for capture: CaptureResult) -> ThemedShotHoverPreview {
        ThemedShotHoverPreview(store: store, capture: capture, canCopy: hoverCopy.isRegistered,
                              copyLabel: copyLabel, clickLabel: clickLabel)
    }

    private func observeInvalidation(of parent: NSWindow) {
        // Observe immediately on entry, including during the preview delay, so
        // resizing or hiding the shelf cannot leave Command-C registered.
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification,
                     NSWindow.willCloseNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: parent, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.dismiss(recheckPointer: name != NSWindow.willCloseNotification)
                }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                                object: parent, queue: .main) { [weak self, weak parent] _ in
            MainActor.assumeIsolated {
                if parent?.isVisible != true || parent?.occlusionState.contains(.visible) != true {
                    self?.dismiss()
                }
            }
        })
    }

    static func previewFrame(thumbnail: CGRect, shelf: CGRect, screen: CGRect, size: CGSize) -> CGRect {
        let inset = screen.insetBy(dx: 8, dy: 8)
        let fitted = CGSize(width: min(size.width, inset.width), height: min(size.height, inset.height))
        return CGRect(x: min(max(thumbnail.midX - fitted.width / 2, inset.minX), inset.maxX - fitted.width),
                      y: min(max(shelf.minY - fitted.height - 8, inset.minY), inset.maxY - fitted.height),
                      width: fitted.width, height: fitted.height)
    }
}

/// This separate hosting tree observes the selected theme while its preview is visible.
@MainActor
private struct ThemedShotHoverPreview: View {
    let store: CaptureStore?
    let capture: CaptureResult
    let canCopy: Bool
    let copyLabel: String
    let clickLabel: String

    var body: some View {
        ShotHoverPreviewView(capture: capture, canCopy: canCopy,
                             copyLabel: copyLabel, clickLabel: clickLabel)
            .environment(\.notchTheme, store?.theme ?? .mint)
    }
}

final class ShotHoverPreviewPanel: NSPanel {
    init(contentRect: CGRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        level = .mainMenu + 4
        collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]
        title = "Shot hover preview"
        isExcludedFromWindowsMenu = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
