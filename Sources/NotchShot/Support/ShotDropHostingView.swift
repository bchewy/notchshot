// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI

/// The panel itself remains a drop destination even when its SwiftUI content
/// is collapsed to the thin strip. Controls retain normal hit testing.
@MainActor
final class ShotDropHostingView<Content: View>: NSHostingView<Content> {
    weak var captureStore: CaptureStore?

    func configureDropTarget(store: CaptureStore) {
        captureStore = store
        registerForDraggedTypes([CaptureCardPasteboard.captureID] + CaptureImportService.readableTypes)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDrag(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDrag(sender)
    }

    private func updateDrag(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let store = captureStore, store.canReceiveDrop(sender.draggingPasteboard) else { return [] }
        store.isDropTargeted = true
        store.showShelf()
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        captureStore?.isDropTargeted = false
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        captureStore?.canReceiveDrop(sender.draggingPasteboard) ?? false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        captureStore?.receiveDrop(sender.draggingPasteboard) ?? false
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        captureStore?.isDropTargeted = false
    }
}
