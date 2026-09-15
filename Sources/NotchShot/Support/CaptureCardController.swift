// SPDX-License-Identifier: MIT
import AppKit
import QuartzCore
import SwiftUI

/// Owns the temporary capture window. The store owns pending/saved capture data.
@MainActor
final class CaptureCardController {
    var onDragBegan: (() -> Void)?

    private let store: CaptureStore
    private let presentsWindow: Bool
    private let reduceMotion: () -> Bool
    private let panel = CaptureCardPanel()
    private let canvas = CaptureCardTransitionView()
    private var host: NSHostingView<CaptureCardView>?
    private var captureID: UUID?
    private var displayLink: CADisplayLink?
    private var animationRevision = 0
    private var isDragging = false
    private var isHandingOff = false
    private var previewFrame = CGRect.zero
    private var phase = "idle"
    private let cardSize = CGSize(width: 268, height: 218)

    var isAnimating: Bool { displayLink != nil }

    init(store: CaptureStore, presentsWindow: Bool = true,
         reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }) {
        self.store = store
        self.presentsWindow = presentsWindow
        self.reduceMotion = reduceMotion
        panel.onEscape = { [weak store] in store?.dismissPendingCapture() }
    }

    deinit { displayLink?.invalidate() }

    func present(_ capture: CaptureResult) {
        let isNewCapture = captureID != capture.id
        if isNewCapture { cancelAnimation() }
        captureID = capture.id
        let view = CaptureCardView(
            store: store, capture: capture,
            onDragBegan: { [weak self] in self?.beginDrag(for: capture.id) },
            onDragEnded: { [weak self] accepted in self?.endDrag(for: capture.id, accepted: accepted) }
        )
        if let host { host.rootView = view }
        else {
            let host = NSHostingView(rootView: view)
            host.sizingOptions = []
            self.host = host
        }
        // AX enrichment must never replay, move, or interrupt the screenshot's
        // entrance/flight. The live card picks up that data when it is revealed.
        guard isNewCapture else { return }
        guard let host else { return }
        let screens = NSScreen.screens
        let mainTop = screens.first?.frame.maxY ?? 0
        let fallback = screens.firstIndex { $0 == NotchGeometry.preferredScreen } ?? 0
        let screenIndex = CaptureCardGeometry.screenIndex(forCGFrame: capture.sourceWindowFrame,
                                                         screens: screens.map(\.frame),
                                                         mainDisplayTop: mainTop, fallbackIndex: fallback)
        guard let index = screenIndex else {
            store.acceptPendingCapture()
            return
        }
        let screen = screens[index]
        previewFrame = CaptureCardGeometry.previewFrame(size: cardSize,
                                                        sourceCGFrame: capture.sourceWindowFrame,
                                                        visibleFrame: screen.visibleFrame, mainDisplayTop: mainTop)
        panel.alphaValue = 1
        panel.ignoresMouseEvents = false
        panel.setFrame(previewFrame, display: false)
        panel.contentView = host
        host.frame = CGRect(origin: .zero, size: cardSize)
        host.layoutSubtreeIfNeeded()
        canvas.cardImage = CaptureCardTransitionView.snapshot(of: host, size: cardSize)
        canvas.screenshot = capture.pngData.flatMap(NSImage.init(data:))
        if reduceMotion() {
            showLivePreview()
            if presentsWindow { panel.orderFrontRegardless() }
            return
        }

        var sourceFrame: CGRect?
        if canvas.screenshot != nil, let source = capture.sourceWindowFrame,
           source.width > 0, source.height > 0, source.width.isFinite, source.height.isFinite,
           source.minX.isFinite, source.minY.isFinite {
            let converted = CaptureCardGeometry.appKitFrame(fromCGFrame: source, mainDisplayTop: mainTop)
            // Avoid an enormous or entirely off-screen transition window.
            if converted.intersects(screen.frame), converted.width <= screen.frame.width * 2,
               converted.height <= screen.frame.height * 2 { sourceFrame = converted }
        }
        let destination = previewFrame
        phase = "entrance"
        animate(duration: CaptureCardMotion.entranceDuration, style: .entrance,
                sample: { CaptureCardMotion.entrance(from: sourceFrame, to: destination, progress: $0) }) { [weak self] in
            self?.showLivePreview()
        }
        if presentsWindow { panel.orderFrontRegardless() }
    }

    func dismiss() {
        // The store relinquishes its pending card at arrival; keep its raster
        // for the short overlap while SwiftUI reveals the saved thumbnail.
        if isHandingOff { captureID = nil; return }
        cancelAnimation()
        captureID = nil
        isDragging = false
        phase = "idle"
        panel.orderOut(nil)
        panel.alphaValue = 1
        panel.ignoresMouseEvents = false
    }

    /// The shelf has opened and measured its actual incoming thumbnail before
    /// calling this. Travel and scale into that slot, staying visible to arrival.
    func landInShelf(completion: @escaping () -> Void) {
        guard let id = captureID, !isDragging else { return }
        cancelAnimation()
        let compactDestination = NotchGeometry.preferredScreen.map {
            NotchGeometry.frame(on: $0, size: CGSize(width: 28, height: 18))
        }
        let target = store.shelfLandingFrame ?? (!store.openShelfAfterCapture ? compactDestination : nil)
        guard !reduceMotion(), let destination = target,
              !destination.isEmpty, destination.width.isFinite, destination.height.isFinite else {
            // Missing/offline display geometry must not strand a pending shot.
            dismiss()
            completion()
            return
        }
        if let host, panel.contentView === host {
            canvas.cardImage = CaptureCardTransitionView.snapshot(of: host, size: cardSize)
        }
        let initial = panel.frame
        phase = "flight"
        animate(duration: CaptureCardMotion.flightDuration, style: .landing,
                sample: { CaptureCardMotion.flight(from: initial, to: destination, progress: $0) }) { [weak self] in
            guard let self, self.captureID == id else { return }
            self.trace("arrived")
            self.isHandingOff = true
            completion()
            self.isHandingOff = false
            guard self.captureID == nil || self.captureID == id else { return }
            self.captureID = nil
            self.phase = "handoff"
            self.animate(duration: 0.14, style: .landing, sample: { progress in
                .init(frame: destination, alpha: 1 - progress, visualProgress: 1)
            }) { [weak self] in self?.dismiss() }
        }
    }

    private func showLivePreview() {
        guard captureID != nil, let host else { return }
        panel.contentView = host
        panel.setFrame(previewFrame, display: true)
        host.frame = CGRect(origin: .zero, size: cardSize)
        panel.alphaValue = 1
        panel.ignoresMouseEvents = false
        phase = "preview"
        trace(phase)
    }

    private func beginDrag(for id: UUID) {
        guard captureID == id else { return }
        cancelAnimation()
        isDragging = true
        onDragBegan?()
        store.beginCardDrag()
        panel.orderOut(nil)
    }

    private func endDrag(for id: UUID, accepted: Bool) {
        isDragging = false
        store.endCardDrag(accepted: accepted)
        guard captureID == id, store.pendingCapture?.id == id else { return }
        showLivePreview()
        if presentsWindow { panel.orderFrontRegardless() }
    }

    private func cancelAnimation() {
        animationRevision += 1
        displayLink?.invalidate()
        displayLink = nil
    }

    private func animate(duration: TimeInterval, style: CaptureCardTransitionView.Style,
                         sample: @escaping (CGFloat) -> CaptureCardMotion.Sample,
                         completion: @escaping () -> Void) {
        cancelAnimation()
        canvas.style = style
        panel.contentView = canvas
        panel.ignoresMouseEvents = true
        apply(sample(0))
        guard let screen = panel.screen ?? NotchGeometry.preferredScreen else {
            apply(sample(1))
            completion()
            return
        }
        let revision = animationRevision
        let started = CACurrentMediaTime()
        let target = CaptureCardDisplayLinkTarget { [weak self] link in
            guard let self, self.animationRevision == revision else { link.invalidate(); return }
            let progress = self.reduceMotion() ? 1 : min(1, max(0, (CACurrentMediaTime() - started) / duration))
            self.apply(sample(CGFloat(progress)))
            self.trace(self.phase)
            if progress >= 1 {
                self.cancelAnimation()
                completion()
            }
        }
        let link = screen.displayLink(target: target, selector: #selector(CaptureCardDisplayLinkTarget.tick(_:)))
        displayLink = link
        link.add(to: .main, forMode: .common)
    }

    private func apply(_ sample: CaptureCardMotion.Sample) {
        panel.setFrame(sample.frame, display: true)
        panel.alphaValue = sample.alpha
        canvas.progress = sample.visualProgress
        canvas.flash = sample.flash
    }

    /// Optional local geometry-only evidence. Never records pixels or app text.
    private func trace(_ phase: String) {
        guard let path = ProcessInfo.processInfo.environment["NOTCHSHOT_CARD_GEOMETRY_LOG"] else { return }
        let frame = panel.frame
        let line = "\(CACurrentMediaTime()) \(phase) \(frame.minX) \(frame.minY) \(frame.width) \(frame.height) \(panel.alphaValue)\n"
        guard let data = line.data(using: .utf8) else { return }
        let url = URL(fileURLWithPath: path)
        if let file = try? FileHandle(forWritingTo: url) {
            _ = try? file.seekToEnd(); try? file.write(contentsOf: data); try? file.close()
        } else { try? data.write(to: url) }
    }
}

@MainActor
private final class CaptureCardDisplayLinkTarget: NSObject {
    private let callback: (CADisplayLink) -> Void
    init(callback: @escaping (CADisplayLink) -> Void) { self.callback = callback }
    @objc func tick(_ link: CADisplayLink) { callback(link) }
}

@MainActor
private final class CaptureCardPanel: NSPanel {
    var onEscape: (() -> Void)?
    init() {
        super.init(contentRect: CGRect(x: 0, y: 0, width: 268, height: 218),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .mainMenu + 4
        animationBehavior = .none
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]
        title = "NotchShot capture preview"
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
    }
}
