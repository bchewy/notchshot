// SPDX-License-Identifier: MIT
import AppKit
import Carbon.HIToolbox

/// A physical key plus deliberate modifiers. Character labels follow the current keyboard layout.
struct CaptureShortcut: Codable, Equatable, Hashable {
    let keyCode: UInt16
    let carbonModifiers: UInt32

    static let storageKey = "captureShortcut"
    static let defaultShortcut = CaptureShortcut(keyCode: UInt16(kVK_ANSI_2), carbonModifiers: UInt32(cmdKey | shiftKey))!

    init?(keyCode: UInt16, carbonModifiers: UInt32) {
        let normalized = carbonModifiers & UInt32(cmdKey | shiftKey | optionKey | controlKey)
        guard keyCode <= 127,
              !Self.navigationAndModifierKeys.contains(keyCode),
              normalized & UInt32(cmdKey | optionKey | controlKey) != 0 else { return nil }
        self.keyCode = keyCode
        self.carbonModifiers = normalized
    }

    init?(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) {
        var modifiers: UInt32 = 0
        if modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if modifierFlags.contains(.option) { modifiers |= UInt32(optionKey) }
        if modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }
        self.init(keyCode: keyCode, carbonModifiers: modifiers)
    }

    var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonModifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if carbonModifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if carbonModifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbonModifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        return flags
    }

    var displayString: String {
        var label = ""
        if modifierFlags.contains(.control) { label += "⌃" }
        if modifierFlags.contains(.option) { label += "⌥" }
        if modifierFlags.contains(.shift) { label += "⇧" }
        if modifierFlags.contains(.command) { label += "⌘" }
        return label + keyDisplayName
    }

    var keyDisplayName: String {
        if let special = Self.specialKeyNames[keyCode] { return special }
        if let translated = Self.currentLayoutCharacter(for: keyCode) { return translated.uppercased() }
        return Self.fallbackKeyNames[keyCode] ?? "Key \(keyCode)"
    }

    func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.storageKey) }
    }

    static func load(from defaults: UserDefaults) -> CaptureShortcut {
        guard let data = defaults.data(forKey: storageKey),
              let shortcut = try? JSONDecoder().decode(Self.self, from: data) else { return .defaultShortcut }
        return shortcut
    }

    private enum CodingKeys: String, CodingKey { case keyCode, carbonModifiers }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let keyCode = try values.decode(UInt16.self, forKey: .keyCode)
        let modifiers = try values.decode(UInt32.self, forKey: .carbonModifiers)
        guard let shortcut = Self(keyCode: keyCode, carbonModifiers: modifiers) else {
            throw DecodingError.dataCorruptedError(forKey: .keyCode, in: values, debugDescription: "A capture shortcut needs a non-modifier key and Command, Control, or Option.")
        }
        self = shortcut
    }

    private static let navigationAndModifierKeys: Set<UInt16> = [
        kVK_Escape, kVK_Tab, kVK_Command, kVK_RightCommand, kVK_Shift, kVK_RightShift,
        kVK_Option, kVK_RightOption, kVK_Control, kVK_RightControl, kVK_CapsLock, kVK_Function
    ].map(UInt16.init).reduce(into: Set<UInt16>()) { $0.insert($1) }

    private static let specialKeyNames: [UInt16: String] = [
        UInt16(kVK_Return): "↩", UInt16(kVK_Space): "Space", UInt16(kVK_Delete): "⌫",
        UInt16(kVK_ForwardDelete): "⌦", UInt16(kVK_Home): "↖", UInt16(kVK_End): "↘",
        UInt16(kVK_PageUp): "⇞", UInt16(kVK_PageDown): "⇟", UInt16(kVK_LeftArrow): "←",
        UInt16(kVK_RightArrow): "→", UInt16(kVK_UpArrow): "↑", UInt16(kVK_DownArrow): "↓",
        UInt16(kVK_ANSI_KeypadEnter): "⌤", UInt16(kVK_ANSI_KeypadClear): "Clear",
        UInt16(kVK_Help): "Help",
        UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3", UInt16(kVK_F4): "F4",
        UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6", UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8",
        UInt16(kVK_F9): "F9", UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12",
        UInt16(kVK_F13): "F13", UInt16(kVK_F14): "F14", UInt16(kVK_F15): "F15", UInt16(kVK_F16): "F16",
        UInt16(kVK_F17): "F17", UInt16(kVK_F18): "F18", UInt16(kVK_F19): "F19", UInt16(kVK_F20): "F20"
    ]

    private static func currentLayoutCharacter(for keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let rawData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(rawData).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 8)
        let status = UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0,
                                    UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysMask),
                                    &deadKeyState, characters.count, &length, &characters)
        guard status == noErr, length > 0, length <= characters.count else { return nil }
        let label = String(utf16CodeUnits: characters, count: length)
        guard !label.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return label
    }

    // Only used when an input method has no Unicode keyboard-layout data.
    private static let fallbackKeyNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
        20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
        29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J",
        39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 50: "`"
    ]
}
