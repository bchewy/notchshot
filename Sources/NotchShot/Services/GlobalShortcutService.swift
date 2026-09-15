// SPDX-License-Identifier: MIT
import AppKit
import Carbon.HIToolbox

/// Carbon registers one chosen combination, without observing general keyboard input.
@MainActor
final class GlobalShortcutService {
    enum RegistrationResult: Equatable {
        case success
        case failure(OSStatus)

        var isSuccess: Bool { self == .success }

        var diagnostic: String? {
            switch self {
            case .success: return nil
            case .failure(let status) where status == OSStatus(eventHotKeyExistsErr):
                return "That shortcut is already in use. Try another combination."
            case .failure(let status):
                return "macOS could not register that shortcut (\(status)). Try another combination."
            }
        }
    }

    private final class HandlerContext {
        weak var service: GlobalShortcutService?
        var identifier: UInt32?
        init(service: GlobalShortcutService) { self.service = service }
    }

    /// Opaque Carbon resources may be transferred to main for destruction, but
    /// never inspected or released on the originating background thread.
    private struct NativeCleanup: @unchecked Sendable {
        let hotKey: EventHotKeyRef?
        let handler: EventHandlerRef?
        let context: HandlerContext?

        func perform() {
            precondition(Thread.isMainThread)
            if let hotKey { UnregisterEventHotKey(hotKey) }
            if let handler { RemoveEventHandler(handler) }
            withExtendedLifetime(context) {}
        }
    }

    static let signature: OSType = 0x4E534854
    private static var nextIdentifier: UInt32 = 1

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var handlerContext: HandlerContext?
    private(set) var registeredShortcut: CaptureShortcut?
    private(set) var registrationID: UInt32?
    var onCapture: (() -> Void)?

    /// Register the replacement first: a conflict never removes a working shortcut.
    func register(shortcut: CaptureShortcut = .defaultShortcut) -> RegistrationResult {
        if registeredShortcut == shortcut, hotKey != nil { return .success }
        let handlerResult = installHandlerIfNeeded()
        guard handlerResult.isSuccess else { return handlerResult }

        let identifier = Self.nextIdentifier
        Self.nextIdentifier &+= 1
        if Self.nextIdentifier == 0 { Self.nextIdentifier = 1 }
        var candidate: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.carbonModifiers,
                                        EventHotKeyID(signature: Self.signature, id: identifier),
                                        GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &candidate)
        guard status == noErr, let candidate else {
            if let candidate { UnregisterEventHotKey(candidate) }
            if hotKey == nil { removeHandler() }
            return .failure(status == noErr ? OSStatus(paramErr) : status)
        }

        let previous = hotKey
        hotKey = candidate
        registeredShortcut = shortcut
        registrationID = identifier
        handlerContext?.identifier = identifier
        if let previous { UnregisterEventHotKey(previous) }
        return .success
    }

    func unregister() {
        // Invalidate first so a callback already queued on MainActor cannot capture later.
        registrationID = nil
        registeredShortcut = nil
        handlerContext?.identifier = nil
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        removeHandler()
    }

    /// Both native dispatch and deferred delivery validate the current registration.
    func handleHotKey(signature: OSType, identifier: UInt32) {
        guard signature == Self.signature, identifier == registrationID, hotKey != nil else { return }
        onCapture?()
    }

    private func installHandlerIfNeeded() -> RegistrationResult {
        guard handler == nil else { return .success }
        let context = HandlerContext(service: self)
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        var candidate: EventHandlerRef?
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, rawContext in
            guard let event, let rawContext else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let parameterStatus = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                                    EventParamType(typeEventHotKeyID), nil,
                                                    MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard parameterStatus == noErr else { return parameterStatus }
            let context = Unmanaged<HandlerContext>.fromOpaque(rawContext).takeUnretainedValue()
            guard identifier.signature == 0x4E534854, identifier.id == context.identifier else {
                return OSStatus(eventNotHandledErr)
            }
            Task { @MainActor [weak service = context.service] in
                service?.handleHotKey(signature: identifier.signature, identifier: identifier.id)
            }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(context).toOpaque(), &candidate)
        guard status == noErr, let candidate else {
            if let candidate { RemoveEventHandler(candidate) }
            return .failure(status == noErr ? OSStatus(paramErr) : status)
        }
        handler = candidate
        handlerContext = context
        return .success
    }

    private func removeHandler() {
        if let handler { RemoveEventHandler(handler) }
        handler = nil
        handlerContext = nil
    }

    deinit {
        // Carbon registration is main-thread-only. Keep the callback context alive until
        // the native handler is removed, even if the final owner releases off-main.
        let cleanup = NativeCleanup(hotKey: hotKey, handler: handler, context: handlerContext)
        if Thread.isMainThread { cleanup.perform() }
        else { DispatchQueue.main.async { cleanup.perform() } }
    }
}
