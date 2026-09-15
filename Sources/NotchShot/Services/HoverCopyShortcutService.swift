// SPDX-License-Identifier: MIT
import AppKit
import Carbon.HIToolbox

@MainActor
protocol HoverCopyShortcutBinding: AnyObject {
    var onCapture: (() -> Void)? { get set }
    func register(shortcut: CaptureShortcut) -> GlobalShortcutService.RegistrationResult
    func unregister()
}

extension GlobalShortcutService: HoverCopyShortcutBinding {}

/// Exclusively owns Command-C only while one saved thumbnail is under the
/// pointer. Carbon consumes that one combination without activating our panel
/// or also sending Copy to the user's active app; no typing is observed.
@MainActor
final class HoverCopyShortcutService {
    static let shortcut = CaptureShortcut(keyCode: UInt16(kVK_ANSI_C), modifierFlags: [.command])!

    private let binding: any HoverCopyShortcutBinding
    private var generation: UUID?
    private var isValid: (() -> Bool)?
    private var copy: (() -> Bool)?
    private(set) var owner: UUID?
    private(set) var captureID: UUID?
    private(set) var isRegistered = false

    init(binding: (any HoverCopyShortcutBinding)? = nil) {
        self.binding = binding ?? GlobalShortcutService()
    }

    @discardableResult
    func begin(owner: UUID, captureID: UUID, isValid: @escaping () -> Bool,
               copy: @escaping () -> Bool) -> Bool {
        // Register each owner afresh. The native registration ID and this token
        // both reject a queued key press after the pointer switches shots.
        stop()
        guard isValid() else { return false }
        let generation = UUID()
        self.generation = generation
        self.owner = owner
        self.captureID = captureID
        self.isValid = isValid
        self.copy = copy
        binding.onCapture = { [weak self] in self?.handleCopy(generation: generation) }
        guard binding.register(shortcut: Self.shortcut).isSuccess else {
            stop()
            return false
        }
        isRegistered = true
        return true
    }

    func stop(owner: UUID? = nil) {
        if let owner, self.owner != owner { return }
        generation = nil
        self.owner = nil
        captureID = nil
        isValid = nil
        copy = nil
        isRegistered = false
        binding.onCapture = nil
        binding.unregister()
    }

    private func handleCopy(generation: UUID) {
        guard self.generation == generation, isRegistered else { return }
        guard isValid?() == true, copy?() == true else {
            stop()
            return
        }
    }
}
