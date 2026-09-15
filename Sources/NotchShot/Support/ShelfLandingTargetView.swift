// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI

/// Measures the visible thumbnail rather than reconstructing SwiftUI padding in
/// the card controller. AppKit supplies bottom-origin screen coordinates.
struct ShelfLandingTargetView: NSViewRepresentable {
    let store: CaptureStore
    let captureID: UUID

    func makeNSView(context: Context) -> ShelfLandingTargetNSView {
        let view = ShelfLandingTargetNSView()
        view.configure(store: store, captureID: captureID)
        return view
    }

    func updateNSView(_ view: ShelfLandingTargetNSView, context: Context) {
        view.configure(store: store, captureID: captureID)
    }

    static func dismantleNSView(_ view: ShelfLandingTargetNSView, coordinator: ()) {
        view.stopReporting()
    }
}

@MainActor
final class ShelfLandingTargetNSView: NSView {
    private weak var store: CaptureStore?
    private var captureID: UUID?
    private let owner = UUID()
    private var observers: [NSObjectProtocol] = []
    private var isReporting = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }

    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { return nil }

    func configure(store: CaptureStore, captureID: UUID) {
        self.store = store
        self.captureID = captureID
        isReporting = true
        needsLayout = true
        reportFrame()
        // SwiftUI can finish positioning ancestors after updateNSView returns.
        DispatchQueue.main.async { [weak self] in self?.reportFrame() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeObservers()
        guard let window else {
            store?.clearShelfLandingFrame(owner: owner)
            return
        }
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reportFrame() }
            })
        }
        reportFrame()
    }

    override func layout() {
        super.layout()
        reportFrame()
    }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
        reportFrame()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        reportFrame()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func stopReporting() {
        isReporting = false
        removeObservers()
        store?.clearShelfLandingFrame(owner: owner)
    }

    private func reportFrame() {
        guard isReporting, let window, let captureID else { return }
        let frame = window.convertToScreen(convert(bounds, to: nil))
        store?.reportShelfLandingFrame(frame, captureID: captureID, owner: owner)
    }

    private func removeObservers() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }
}
