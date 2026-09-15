// SPDX-License-Identifier: MIT
import Foundation

/// One cancellable deadline, driven by attention changes rather than pointer motion.
@MainActor
final class NotchIdleTimer {
    typealias Schedule = @MainActor (Duration, @escaping @MainActor () -> Void) -> (() -> Void)

    private let schedule: Schedule
    private let refreshAttention: () -> Void
    private let collapse: () -> Void
    private var cancelDeadline: (() -> Void)?
    private var generation = 0
    private var eligible = false
    private var delay: Duration = .seconds(3)

    init(schedule: @escaping Schedule = NotchIdleTimer.scheduleTask,
         refreshAttention: @escaping () -> Void,
         collapse: @escaping () -> Void) {
        self.schedule = schedule
        self.refreshAttention = refreshAttention
        self.collapse = collapse
    }

    func update(eligible: Bool, delay: Duration, restart: Bool = false) {
        guard restart || self.eligible != eligible || self.delay != delay else { return }
        self.eligible = eligible
        self.delay = delay
        cancel()
        guard eligible else { return }
        let token = generation
        cancelDeadline = schedule(delay) { [weak self] in
            guard let self, self.generation == token, self.eligible else { return }
            // Re-sample the native pointer/focus immediately. A pointer may have
            // returned between the last monitor tick and this deadline.
            self.refreshAttention()
            guard self.generation == token, self.eligible else { return }
            self.cancel()
            self.collapse()
        }
    }

    func stop() {
        eligible = false
        cancel()
    }

    private func cancel() {
        generation &+= 1
        cancelDeadline?()
        cancelDeadline = nil
    }

    static func scheduleTask(_ delay: Duration, action: @escaping @MainActor () -> Void) -> (() -> Void) {
        let task = Task { @MainActor in
            do { try await Task.sleep(for: delay) } catch { return }
            guard !Task.isCancelled else { return }
            action()
        }
        return { task.cancel() }
    }

    deinit { cancelDeadline?() }
}
