// SPDX-License-Identifier: MIT
import Foundation

/// AX and Vision perform blocking work away from the main actor. Detached tasks
/// do not inherit cancellation, so explicitly connect them to their caller.
enum CaptureWorker {
    static func run<Value: Sendable>(
        onCancel: @escaping @Sendable () -> Void = {},
        operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let value = try operation()
            try Task.checkCancellation()
            return value
        }
        return try await withTaskCancellationHandler {
            do {
                let value = try await worker.value
                try Task.checkCancellation()
                return value
            } catch {
                // Frameworks may report their own cancellation error. Preserve
                // the caller's cancellation instead of treating it as a failure.
                try Task.checkCancellation()
                throw error
            }
        } onCancel: {
            worker.cancel()
            onCancel()
        }
    }
}
