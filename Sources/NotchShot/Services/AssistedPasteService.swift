// SPDX-License-Identifier: MIT
import AppKit
import ApplicationServices

enum AssistedPasteResult: Equatable {
    /// The paste key events were delivered. Their recipient decides what it accepts.
    case eventsSent
    case cancelled(String)
    case unavailable(String)
    /// Assistance could not be armed after a copy, or the sequence stopped and
    /// the original clipboard could not be put back. Shown as an error.
    case failed(String)
}

@MainActor
protocol AssistedPasteServing: AnyObject {
    var onResult: ((AssistedPasteResult) -> Void)? { get set }
    @discardableResult func arm(capture: CaptureResult, clipboard: NSPasteboard) -> Bool
    @discardableResult func arm(batch: CaptureBatch, clipboard: NSPasteboard) -> Bool
    func cancel()
    func stop()
}

extension AssistedPasteServing {
    // Older/specialized adapters can opt out of batch assistance while retaining
    // the complete rich batch on the clipboard for ordinary paste.
    @discardableResult
    func arm(batch: CaptureBatch, clipboard: NSPasteboard) -> Bool { false }
}

// The native identity contains immutable AX object references. Those references
// may be compared across queues; AppKit application state stays on the main actor.
struct AssistedPasteTarget: Equatable, @unchecked Sendable {
    let processIdentifier: pid_t
    let focusIdentity: AnyHashable
}

enum AssistedPasteEvent {
    case paste(isRepeat: Bool)
    case keyDown
    case pointerDown
    case unavailable
}

/// This boundary lets tests exercise sequencing without a global event tap,
/// Accessibility access, real keyboard events, or the user's clipboard.
@MainActor
protocol AssistedPasteEnvironment: AnyObject {
    var onEvent: ((AssistedPasteEvent) -> Bool)? { get set }
    var isAccessibilityTrusted: Bool { get }
    var frontmostProcessIdentifier: pid_t? { get }
    func startMonitoring() -> Bool
    func stopMonitoring()
    func currentTarget() async -> AssistedPasteTarget?
    func postPaste(to target: AssistedPasteTarget) -> Bool
    func postFallbackPaste(to processIdentifier: pid_t) -> Bool
}

/// One explicitly armed paste, with separate image and context clipboard stages.
/// It never sends Return, and never writes over another app's clipboard change.
@MainActor
final class AssistedPasteService: AssistedPasteServing {
    var onResult: ((AssistedPasteResult) -> Void)?
    var isArmed: Bool { phase == .armed }
    var isPasting: Bool { phase == .preparing || phase == .imageSent || phase == .textSent }

    private enum Phase { case idle, armed, preparing, imageSent, textSent }
    private let environment: any AssistedPasteEnvironment
    private let imageDelay: Duration
    private let restoreDelay: Duration
    private let armTimeout: Duration
    private let pollInterval: Duration
    private let sleep: (Duration) async throws -> Void
    private let now: () -> Date
    private let startPolling: Bool
    private var phase: Phase = .idle
    private var generation = UUID()
    private var clipboard: NSPasteboard?
    private var ownedChangeCount: Int?
    private var didStageClipboard = false
    private var originalRepresentations: [(NSPasteboard.PasteboardType, Data)] = []
    private var imageStages: [[(NSPasteboard.PasteboardType, Data)]] = []
    private var successfulImagePosts = 0
    private var context = ""
    private var target: AssistedPasteTarget?
    private var preparingPID: pid_t?
    private var expiresAt = Date.distantPast
    private var sequenceTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    private var isHandlingEvent = false

    init(
        environment: (any AssistedPasteEnvironment)? = nil,
        imageDelay: Duration = .milliseconds(600),
        restoreDelay: Duration = .milliseconds(650),
        armTimeout: Duration = .seconds(120),
        pollInterval: Duration = .milliseconds(250),
        sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        now: @escaping () -> Date = Date.init,
        startPolling: Bool = true
    ) {
        self.environment = environment ?? NativeAssistedPasteEnvironment()
        self.imageDelay = imageDelay
        self.restoreDelay = restoreDelay
        self.armTimeout = armTimeout
        self.pollInterval = pollInterval
        self.sleep = sleep
        self.now = now
        self.startPolling = startPolling
        self.environment.onEvent = { [weak self] event in self?.handle(event) ?? false }
    }

    @discardableResult
    func arm(capture: CaptureResult, clipboard: NSPasteboard) -> Bool {
        cancel()
        // Production never takes over a named/private pasteboard. Tests explicitly
        // supply their own environment and use an isolated pasteboard instead.
        guard !(environment is NativeAssistedPasteEnvironment) || clipboard.name == .general else { return false }
        guard environment.isAccessibilityTrusted else {
            onResult?(.unavailable("Enable Accessibility to paste the image and text together."))
            return false
        }
        let initialChangeCount = clipboard.changeCount
        guard let png = capture.pngData,
              png.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]),
              let bitmap = NSBitmapImageRep(data: png), bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0,
              let item = clipboard.pasteboardItems?.first,
              clipboard.pasteboardItems?.count == 1,
              item.data(forType: .png) == png,
              item.string(forType: .string) == capture.contextText else { return false }

        let representations = item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        guard clipboard.changeCount == initialChangeCount else { return false }
        var imageRepresentations: [(NSPasteboard.PasteboardType, Data)] = [(.png, png)]
        if let tiff = item.data(forType: .tiff) ?? NSImage(data: png)?.tiffRepresentation {
            imageRepresentations.append((.tiff, tiff))
        }
        return armPrepared(clipboard: clipboard, initialChangeCount: initialChangeCount,
                           originals: representations, images: [imageRepresentations], context: capture.contextText)
    }

    @discardableResult
    func arm(batch: CaptureBatch, clipboard: NSPasteboard) -> Bool {
        cancel()
        guard !(environment is NativeAssistedPasteEnvironment) || clipboard.name == .general else { return false }
        guard environment.isAccessibilityTrusted else {
            onResult?(.unavailable("Enable Accessibility to paste the images and text together."))
            return false
        }
        let initialChangeCount = clipboard.changeCount
        guard clipboard.pasteboardItems?.count == 1,
              let item = clipboard.pasteboardItems?.first,
              CaptureClipboardService.matchesBatchIdentity(item: item, batch: batch) else { return false }
        let images = CaptureClipboardService.validImagePNGs(for: batch)
        // Text-only batches already paste in a single ordinary Command-V.
        guard !images.isEmpty else { return false }
        let representations = item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        guard clipboard.changeCount == initialChangeCount else { return false }
        // Keep the original compressed PNGs. Producing a TIFF for every shot can
        // multiply memory use for a full shelf of high-resolution screenshots.
        return armPrepared(clipboard: clipboard, initialChangeCount: initialChangeCount,
                           originals: representations, images: images.map { [(.png, $0)] }, context: batch.contextText)
    }

    private func armPrepared(
        clipboard: NSPasteboard, initialChangeCount: Int,
        originals: [(NSPasteboard.PasteboardType, Data)],
        images: [[(NSPasteboard.PasteboardType, Data)]], context: String
    ) -> Bool {
        guard clipboard.changeCount == initialChangeCount else { return false }
        self.clipboard = clipboard
        ownedChangeCount = initialChangeCount
        originalRepresentations = originals
        imageStages = images
        successfulImagePosts = 0
        self.context = context
        let components = armTimeout.components
        expiresAt = now().addingTimeInterval(Double(components.seconds) + Double(components.attoseconds) / 1e18)
        phase = .armed
        generation = UUID()
        guard environment.startMonitoring() else {
            finish(restoringClipboard: false)
            onResult?(.failed("Paste assistance is unavailable. The rich shot is still on the clipboard."))
            return false
        }
        if startPolling { beginPolling(generation: generation) }
        return true
    }

    func cancel() { finish(restoringClipboard: isPasting) }
    func stop() { cancel() }

    private var ownsClipboard: Bool {
        guard let clipboard, let ownedChangeCount else { return false }
        return clipboard.changeCount == ownedChangeCount
    }

    private func handle(_ event: AssistedPasteEvent) -> Bool {
        let previouslyHandlingEvent = isHandlingEvent
        isHandlingEvent = true
        defer { isHandlingEvent = previouslyHandlingEvent }
        guard phase != .idle else { return false }
        guard environment.isAccessibilityTrusted, ownsClipboard else {
            abort("Paste assistance stopped because access or the clipboard changed.")
            return false
        }
        switch event {
        case .unavailable:
            abort("Paste assistance stopped. Copy the shot again to retry.")
        case .keyDown, .pointerDown:
            if isPasting { abort("Paste assistance stopped because you started another action.") }
        case .paste(let isRepeat):
            // A second physical paste is never swallowed or queued for later.
            guard phase == .armed, !isRepeat else {
                abort("Paste assistance stopped because you started another paste.")
                return false
            }
            guard now() < expiresAt, let pid = environment.frontmostProcessIdentifier else {
                abort("Paste assistance stopped because the destination is unavailable.")
                return false
            }
            preparingPID = pid
            phase = .preparing
            // The event-tap callback performs no Accessibility queries, clipboard
            // writes or generated key posting. It only reserves this one gesture.
            beginSequence(generation: generation)
            return true
        }
        return false
    }

    private func beginSequence(generation current: UUID) {
        sequenceTask = Task { [weak self] in
            guard let self else { return }
            do {
                await Task.yield()
                guard self.isCurrent(current, phase: .preparing) else { return }
                guard self.destinationProcessIsUnchanged else {
                    self.abort("Paste assistance stopped because the destination or clipboard changed.")
                    return
                }
                let resolvedTarget = await self.environment.currentTarget()
                guard self.isCurrent(current, phase: .preparing) else { return }
                guard self.destinationProcessIsUnchanged else {
                    self.abort("Paste assistance stopped because the destination or clipboard changed.")
                    return
                }
                guard let target = resolvedTarget, target.processIdentifier == self.preparingPID else {
                    self.replayRegularPaste("This destination used a regular paste instead.")
                    return
                }
                self.target = target
                for (index, representations) in self.imageStages.enumerated() {
                    if index > 0 {
                        try await self.sleep(self.imageDelay)
                        guard await self.checkDestination(current: current, target: target) else { return }
                    }
                    guard self.destinationProcessIsUnchanged, self.write(representations) else {
                        if self.successfulImagePosts == 0 {
                            self.replayRegularPaste("Could not prepare the screenshot. Used a regular paste instead.")
                        } else {
                            self.abort("Paste assistance stopped before the next screenshot could be prepared.")
                        }
                        return
                    }
                    self.phase = .imageSent
                    guard self.environment.postPaste(to: target) else {
                        if self.successfulImagePosts == 0 {
                            self.replayRegularPaste("Could not send the screenshot paste. The rich shot is still on the clipboard.")
                        } else {
                            // Replaying the complete rich batch here could paste
                            // images the destination has already received twice.
                            self.abort("Paste assistance stopped before the next screenshot could be sent.")
                        }
                        return
                    }
                    self.successfulImagePosts += 1
                }
                try await self.sleep(self.imageDelay)
                guard await self.checkDestination(current: current, target: target) else { return }
                guard let data = self.context.data(using: .utf8), self.write([(.string, data)]) else {
                    self.abort("Could not prepare the capture text for pasting.")
                    return
                }
                guard self.destinationProcessIsUnchanged,
                      self.environment.postPaste(to: target) else {
                    self.abort("Text paste stopped because the destination is unavailable.")
                    return
                }
                self.phase = .textSent
                self.onResult?(.eventsSent)
                try await self.sleep(self.restoreDelay)
                guard !Task.isCancelled, self.generation == current, self.phase == .textSent else { return }
                self.finish(restoringClipboard: true)
            } catch {
                guard self.generation == current else { return }
                self.finish(restoringClipboard: true)
            }
        }
    }

    /// Re-query the same app, window and editable control before every later
    /// image and the context. Cancellation/ownership checks bracket the async AX
    /// lookup so a delayed result cannot revive an abandoned paste sequence.
    private func checkDestination(current: UUID, target: AssistedPasteTarget) async -> Bool {
        guard isCurrent(current, phase: .imageSent) else { return false }
        guard destinationProcessIsUnchanged else {
            abort("Paste assistance stopped because the destination or clipboard changed.")
            return false
        }
        let latestTarget = await environment.currentTarget()
        guard isCurrent(current, phase: .imageSent) else { return false }
        guard destinationProcessIsUnchanged, latestTarget == target else {
            abort("Paste assistance stopped because the focused field changed.")
            return false
        }
        return true
    }

    private func isCurrent(_ current: UUID, phase expected: Phase) -> Bool {
        !Task.isCancelled && generation == current && phase == expected
    }

    private var destinationProcessIsUnchanged: Bool {
        guard environment.isAccessibilityTrusted, ownsClipboard, let preparingPID else { return false }
        return environment.frontmostProcessIdentifier == preparingPID
    }

    private func replayRegularPaste(_ message: String) {
        guard successfulImagePosts == 0, destinationProcessIsUnchanged, let pid = preparingPID, let clipboard else {
            abort("Paste assistance stopped because the destination or clipboard changed.")
            return
        }
        if didStageClipboard, !write(originalRepresentations) {
            finish(restoringClipboard: false)
            onResult?(.failed("Could not restore the rich shot. Copy the shot again to retry."))
            return
        }
        let token = ownedChangeCount
        finish(restoringClipboard: false)
        guard clipboard.changeCount == token, environment.isAccessibilityTrusted,
              environment.frontmostProcessIdentifier == pid,
              environment.postFallbackPaste(to: pid) else {
            onResult?(.cancelled("Paste assistance stopped. Press Command-V again to paste the rich shot."))
            return
        }
        onResult?(.cancelled(message))
    }

    private func beginPolling(generation current: UUID) {
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do { try await self.sleep(self.pollInterval) } catch { return }
                guard !Task.isCancelled, self.generation == current, self.phase != .idle else { return }
                guard self.environment.isAccessibilityTrusted, self.ownsClipboard else {
                    self.abort("Paste assistance stopped because access or the clipboard changed.")
                    return
                }
                if self.phase == .armed, self.now() >= self.expiresAt {
                    self.finish(restoringClipboard: false)
                    return
                }
                if self.phase == .preparing || self.phase == .imageSent, !self.destinationProcessIsUnchanged {
                    self.abort("Text paste stopped because the destination changed.")
                    return
                }
            }
        }
    }

    /// Keep the ownership token returned by our clear operation. Reading a newer
    /// changeCount after writing could accidentally adopt another app's copy.
    private func write(_ representations: [(NSPasteboard.PasteboardType, Data)]) -> Bool {
        guard ownsClipboard, let clipboard else { return false }
        let item = NSPasteboardItem()
        for (type, data) in representations { item.setData(data, forType: type) }
        didStageClipboard = true
        let token = clipboard.clearContents()
        ownedChangeCount = token
        guard clipboard.changeCount == token else { return false }
        let success = clipboard.writeObjects([item])
        return success && clipboard.changeCount == token
    }

    private func abort(_ message: String) {
        finish(restoringClipboard: true)
        onResult?(.cancelled(message))
    }

    private func finish(restoringClipboard: Bool) {
        generation = UUID()
        sequenceTask?.cancel()
        pollingTask?.cancel()
        sequenceTask = nil
        pollingTask = nil
        environment.stopMonitoring()
        if restoringClipboard, didStageClipboard, !originalRepresentations.isEmpty, ownsClipboard {
            if isHandlingEvent, let clipboard, let ownedChangeCount {
                // Cancellation invalidates the sequence immediately, but copying
                // potentially large rich formats must wait until the tap returns.
                let representations = originalRepresentations
                Task { @MainActor in
                    await Task.yield()
                    guard clipboard.changeCount == ownedChangeCount else { return }
                    let item = NSPasteboardItem()
                    for (type, data) in representations { item.setData(data, forType: type) }
                    let token = clipboard.clearContents()
                    guard clipboard.changeCount == token else { return }
                    _ = clipboard.writeObjects([item])
                }
            } else {
                _ = write(originalRepresentations)
            }
        }
        phase = .idle
        clipboard = nil
        ownedChangeCount = nil
        didStageClipboard = false
        originalRepresentations.removeAll()
        imageStages.removeAll()
        successfulImagePosts = 0
        context = ""
        target = nil
        preparingPID = nil
    }
}

/// Main-run-loop event tap, installed only for one pending assisted paste.
/// Only Command-V is interpreted; other keys are opaque cancellation signals.
@MainActor
private final class NativeAssistedPasteEnvironment: AssistedPasteEnvironment {
    var onEvent: ((AssistedPasteEvent) -> Bool)?
    var isAccessibilityTrusted: Bool { AXIsProcessTrusted() && CGPreflightPostEventAccess() }
    var frontmostProcessIdentifier: pid_t? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              !app.isTerminated else { return nil }
        return app.processIdentifier
    }
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private static let eventTag: Int64 = 0x4E53485041535445 // NSHPASTE

    func startMonitoring() -> Bool {
        stopMonitoring()
        guard isAccessibilityTrusted else { return false }
        let types: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: { _, type, event, info in
                guard let info else { return Unmanaged.passUnretained(event) }
                return MainActor.assumeIsolated {
                    let environment = Unmanaged<NativeAssistedPasteEnvironment>.fromOpaque(info).takeUnretainedValue()
                    return environment.receive(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
                }
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()
        ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else { return false }
        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return CGEvent.tapIsEnabled(tap: tap)
    }

    func stopMonitoring() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false); CFMachPortInvalidate(eventTap) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        eventTap = nil
        runLoopSource = nil
    }

    func currentTarget() async -> AssistedPasteTarget? {
        guard isAccessibilityTrusted, let pid = frontmostProcessIdentifier else { return nil }
        let target = await Task.detached(priority: .userInitiated) { Self.resolveTarget(pid: pid) }.value
        guard frontmostProcessIdentifier == pid else { return nil }
        return target
    }

    private nonisolated static func resolveTarget(pid: pid_t) -> AssistedPasteTarget? {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.04)
        guard let element = axElement(application, kAXFocusedUIElementAttribute),
              let window = axElement(element, kAXWindowAttribute) ?? axElement(application, kAXFocusedWindowAttribute),
              isEditable(element), !isSecure(element) else { return nil }
        return AssistedPasteTarget(
            processIdentifier: pid,
            focusIdentity: AnyHashable(AXFocusIdentity(element: element, window: window))
        )
    }

    func postPaste(to target: AssistedPasteTarget) -> Bool {
        postFallbackPaste(to: target.processIdentifier)
    }

    func postFallbackPaste(to processIdentifier: pid_t) -> Bool {
        guard isAccessibilityTrusted,
              frontmostProcessIdentifier == processIdentifier,
              let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return false }
        for event in [down, up] {
            event.flags = .maskCommand
            event.setIntegerValueField(.eventSourceUserData, value: Self.eventTag)
            event.postToPid(processIdentifier)
        }
        return true
    }

    private func receive(type: CGEventType, event: CGEvent) -> Bool {
        guard event.getIntegerValueField(.eventSourceUserData) != Self.eventTag else { return false }
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            _ = onEvent?(.unavailable)
            return false
        case .keyDown:
            let modifiers: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl, .maskSecondaryFn]
            if event.getIntegerValueField(.keyboardEventKeycode) == 9,
               event.flags.intersection(modifiers) == .maskCommand {
                return onEvent?(.paste(isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)) ?? false
            }
            _ = onEvent?(.keyDown)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            _ = onEvent?(.pointerDown)
        default: break
        }
        return false
    }

    private nonisolated static func axElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let result = value as! AXUIElement
        AXUIElementSetMessagingTimeout(result, 0.04)
        return result
    }

    private nonisolated static func isSecure(_ element: AXUIElement) -> Bool {
        var subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        if subrole as? String == kAXSecureTextFieldSubrole { return true }
        var protected: CFTypeRef?
        AXUIElementCopyAttributeValue(element, "AXProtectedContent" as CFString, &protected)
        return protected as? Bool == true
    }

    private nonisolated static func isEditable(_ element: AXUIElement) -> Bool {
        var editable: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXEditable" as CFString, &editable) == .success,
           let editable = editable as? Bool { return editable }
        var role: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
              let role = role as? String else { return false }
        if [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role) { return true }
        var valueIsSettable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &valueIsSettable) == .success
            && valueIsSettable.boolValue
    }
}

private struct AXFocusIdentity: Hashable {
    let element: AXUIElement
    let window: AXUIElement
    static func == (lhs: Self, rhs: Self) -> Bool {
        CFEqual(lhs.element, rhs.element) && CFEqual(lhs.window, rhs.window)
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(CFHash(element))
        hasher.combine(CFHash(window))
    }
}
