// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI

enum CaptureCardPasteboard {
    static let captureID = NSPasteboard.PasteboardType("com.bchewy.notchshot.capture-id")
}

@MainActor
struct CaptureCardView: View {
    @Bindable var store: CaptureStore
    let capture: CaptureResult
    let onDragBegan: () -> Void
    let onDragEnded: (Bool) -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 7) {
                appIcon
                VStack(alignment: .leading, spacing: 1) {
                    Text(capture.appName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.9))
                    Text(capture.windowTitle.isEmpty ? "Captured window" : capture.windowTitle)
                        .font(.system(size: 9))
                        .foregroundStyle(Color.white.opacity(0.43))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Button(action: store.dismissPendingCapture) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .frame(width: 20, height: 20)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss capture preview")
            }
            .frame(height: 22)

            ZStack {
                CaptureDragPreview(capture: capture, isEnabled: !store.isCapturing,
                                   onDragBegan: onDragBegan, onDragEnded: onDragEnded)
                if capture.pngData == nil {
                    VStack(spacing: 6) {
                        Image(systemName: "text.alignleft").font(.system(size: 22, weight: .light))
                        Text("App text captured").font(.system(size: 10))
                    }
                    .foregroundStyle(Color.white.opacity(0.45))
                    .allowsHitTesting(false)
                }
            }
            .frame(height: 128)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.white.opacity(0.075), lineWidth: 1))
            .accessibilityLabel("Preview of \(capture.appName). Drag this capture to the notch shelf.")

            HStack(spacing: 6) {
                if store.isCapturing {
                    ProgressView().controlSize(.mini).scaleEffect(0.75)
                    Text("Reading app context…")
                } else {
                    Image(systemName: "hand.draw")
                    Text(store.autoCollectCaptures ? "Moving to shelf…" : "Drag to the notch")
                }
                Spacer(minLength: 0)
                Button("Add to shelf", action: store.acceptPendingCapture)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(store.theme.accent)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(store.theme.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 6))
                    .buttonStyle(.plain)
                    .disabled(store.isCapturing)
                    .opacity(store.isCapturing ? 0.35 : 1)
            }
            .font(.system(size: 9))
            .foregroundStyle(Color.white.opacity(0.45))
            .frame(height: 24)
        }
        .padding(12)
        .frame(width: 268, height: 218)
        .background(Color(red: 0.065, green: 0.078, blue: 0.073), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(store.theme.accent.opacity(0.30), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var appIcon: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: capture.bundleIdentifier) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable().frame(width: 22, height: 22)
        } else {
            Image(systemName: "macwindow")
                .font(.system(size: 16)).frame(width: 22, height: 22)
                .foregroundStyle(store.theme.accent)
        }
    }
}

/// AppKit is limited to the image's native drag session and its typed payload.
@MainActor
private struct CaptureDragPreview: NSViewRepresentable {
    let capture: CaptureResult
    let isEnabled: Bool
    let onDragBegan: () -> Void
    let onDragEnded: (Bool) -> Void

    func makeNSView(context: Context) -> CaptureDragImageView {
        let view = CaptureDragImageView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: CaptureDragImageView, context: Context) {
        view.capture = capture
        view.isDragEnabled = isEnabled
        view.onDragBegan = onDragBegan
        view.onDragEnded = onDragEnded
    }
}

@MainActor
private final class CaptureDragImageView: NSView, NSDraggingSource {
    var capture: CaptureResult? {
        didSet {
            image = capture?.pngData.flatMap { NSImage(data: $0) }
            needsDisplay = true
        }
    }
    var isDragEnabled = true
    var onDragBegan: (() -> Void)?
    var onDragEnded: ((Bool) -> Void)?
    private var image: NSImage?
    private var mouseDownEvent: NSEvent?
    private var isDragging = false

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.45).setFill()
        bounds.fill()
        if let image {
            image.draw(in: fittedRect(for: image), from: .zero, operation: .sourceOver,
                       fraction: 1, respectFlipped: true,
                       hints: [.interpolation: NSNumber(value: NSImageInterpolation.high.rawValue)])
        }
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = isDragEnabled ? event : nil
    }

    override func mouseUp(with event: NSEvent) { mouseDownEvent = nil }

    override func mouseDragged(with event: NSEvent) {
        guard isDragEnabled, !isDragging, let initialEvent = mouseDownEvent, let capture else { return }
        let delta = CGPoint(x: event.locationInWindow.x - initialEvent.locationInWindow.x,
                            y: event.locationInWindow.y - initialEvent.locationInWindow.y)
        guard hypot(delta.x, delta.y) >= 3 else { return }
        let payload = NSPasteboardItem()
        payload.setString(capture.id.uuidString, forType: CaptureCardPasteboard.captureID)
        payload.setString(capture.clipboardText, forType: .string)
        if let png = capture.pngData { payload.setData(png, forType: .png) }
        let item = NSDraggingItem(pasteboardWriter: payload)
        let preview = image ?? NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: "App text")
        item.setDraggingFrame(image.map { fittedRect(for: $0) } ?? bounds, contents: preview)
        isDragging = true
        let session = beginDraggingSession(with: [item], event: initialEvent, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        onDragBegan?()
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        isDragging = false
        mouseDownEvent = nil
        onDragEnded?(operation != [])
    }

    private func fittedRect(for image: NSImage) -> CGRect {
        guard image.size.width > 0, image.size.height > 0 else { return bounds }
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                      width: size.width, height: size.height)
    }
}
