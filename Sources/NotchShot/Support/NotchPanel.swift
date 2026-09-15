// SPDX-License-Identifier: GPL-3.0-only
// Adapted from sk-ruban/notchi NotchPanel.swift, e873da231340b3a5094c59ce7cb0ec2809d88ed1.
import AppKit

final class NotchPanel: NSPanel, NSWindowDelegate {
    var onEscape: (() -> Void)?
    var notchAnchor: CGRect? {
        didSet { restoreAnchor() }
    }
    private var isRestoringAnchor = false

    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        level = .mainMenu + 3
        collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Our presentation driver owns motion, including after key-focus release.
        animationBehavior = .none
        isMovable = false
        isExcludedFromWindowsMenu = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        title = "NotchShot"
        delegate = self
    }

    // NSHostingView can resize its window after the state-change callback has
    // returned. Keep anchoring as a window invariant, not a timed correction.
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(anchoredFrame(frameRect), display: flag)
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool, animate animateFlag: Bool) {
        super.setFrame(anchoredFrame(frameRect), display: flag, animate: animateFlag)
    }

    func windowDidResize(_ notification: Notification) { restoreAnchor() }
    func windowDidMove(_ notification: Notification) { restoreAnchor() }

    private func anchoredFrame(_ proposed: CGRect) -> CGRect {
        guard let notchAnchor else { return proposed }
        return NotchGeometry.frame(anchoredTo: notchAnchor, size: proposed.size)
    }

    private func restoreAnchor() {
        guard notchAnchor != nil, !isRestoringAnchor else { return }
        let origin = anchoredFrame(frame).origin
        guard frame.origin != origin else { return }
        isRestoringAnchor = true
        defer { isRestoringAnchor = false }
        super.setFrameOrigin(origin)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
    }
}
