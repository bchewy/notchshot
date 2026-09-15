// SPDX-License-Identifier: MIT
import Foundation

/// Serial work keeps large images and full-text formatting off the UI executor.
/// Superseded selections are cancelled before queued work starts or is published.
actor CaptureBatchPreparer {
    func prepare(captures: [CaptureResult], style: BatchContextStyle) -> CaptureBatch? {
        guard !Task.isCancelled else { return nil }
        let unavailable = CaptureClipboardService.unavailableImageIDs(in: captures)
        guard !Task.isCancelled else { return nil }
        let batch = CaptureBatch(captures: captures, contextStyle: style, unavailableImageIDs: unavailable)
        return Task.isCancelled ? nil : batch
    }
}
