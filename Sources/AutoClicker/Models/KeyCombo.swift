import AppKit
import Carbon.HIToolbox

/// A keyboard shortcut: a virtual key code plus modifier flags. Codable so it can be persisted
/// and embedded in shared macros.
struct KeyCombo: Codable, Equatable, Hashable {
    var keyCode: UInt32
    /// Raw `NSEvent.ModifierFlags` restricted to the device-independent mask.
    var modifiers: UInt

    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection([.command, .option, .control, .shift, .function]).rawValue
    }

    var modifierFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    /// Modifier mask in the format expected by Carbon's `RegisterEventHotKey`.
    var carbonModifiers: UInt32 {
        var mods: UInt32 = 0
        let f = modifierFlags
        if f.contains(.command) { mods |= UInt32(cmdKey) }
        if f.contains(.option) { mods |= UInt32(optionKey) }
        if f.contains(.control) { mods |= UInt32(controlKey) }
        if f.contains(.shift) { mods |= UInt32(shiftKey) }
        return mods
    }

    /// Whether this combination can be registered as a global hotkey. macOS requires at least one
    /// modifier unless the key is a function key.
    var isValidGlobalHotkey: Bool {
        if KeyCodeNames.isFunctionKey(keyCode) { return true }
        return !modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
    }

    /// Display string such as "⌃⇧K".
    var displayString: String {
        var s = ""
        let f = modifierFlags
        if f.contains(.control) { s += "⌃" }
        if f.contains(.option) { s += "⌥" }
        if f.contains(.shift) { s += "⇧" }
        if f.contains(.command) { s += "⌘" }
        s += KeyCodeNames.name(for: keyCode)
        return s
    }

    // Defaults mirroring TapBot's recommended "Control + Number" combos.
    static let defaultClicker = KeyCombo(keyCode: UInt32(kVK_ANSI_1), modifiers: [.control])
    static let defaultStopAllMacros = KeyCombo(keyCode: UInt32(kVK_ANSI_0), modifiers: [.control])
    static let defaultToggleDockIcon = KeyCombo(keyCode: UInt32(kVK_ANSI_D), modifiers: [.control, .option])
    static let defaultToggleMenuBarIcon = KeyCombo(keyCode: UInt32(kVK_ANSI_M), modifiers: [.control, .option])

    /// Control+2 … Control+9 followed by Control+Option+Number — combinations that are
    /// usually free on macOS. Used to auto-suggest a shortcut when the requested one is taken.
    static let suggestionPool: [KeyCombo] = {
        let digits: [Int] = [kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        var pool = digits.map { KeyCombo(keyCode: UInt32($0), modifiers: [.control]) }
        pool += digits.map { KeyCombo(keyCode: UInt32($0), modifiers: [.control, .option]) }
        pool += digits.map { KeyCombo(keyCode: UInt32($0), modifiers: [.control, .shift]) }
        return pool
    }()
}

/// Human readable names for virtual key codes.
enum KeyCodeNames {
    private static let special: [UInt32: String] = [
        UInt32(kVK_Return): "↩", UInt32(kVK_Tab): "⇥", UInt32(kVK_Space): "Space", UInt32(kVK_Delete): "⌫",
        UInt32(kVK_Escape): "⎋", UInt32(kVK_ForwardDelete): "⌦", UInt32(kVK_Home): "↖", UInt32(kVK_End): "↘",
        UInt32(kVK_PageUp): "⇞", UInt32(kVK_PageDown): "⇟", UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→",
        UInt32(kVK_DownArrow): "↓", UInt32(kVK_UpArrow): "↑", UInt32(kVK_Help): "Help", UInt32(kVK_ANSI_KeypadClear): "⌧",
        UInt32(kVK_ANSI_KeypadEnter): "⌤", UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
        UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6", UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8",
        UInt32(kVK_F9): "F9", UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
        UInt32(kVK_F13): "F13", UInt32(kVK_F14): "F14", UInt32(kVK_F15): "F15", UInt32(kVK_F16): "F16",
        UInt32(kVK_F17): "F17", UInt32(kVK_F18): "F18", UInt32(kVK_F19): "F19", UInt32(kVK_F20): "F20",
        UInt32(kVK_ANSI_Keypad0): "Pad 0", UInt32(kVK_ANSI_Keypad1): "Pad 1", UInt32(kVK_ANSI_Keypad2): "Pad 2",
        UInt32(kVK_ANSI_Keypad3): "Pad 3", UInt32(kVK_ANSI_Keypad4): "Pad 4", UInt32(kVK_ANSI_Keypad5): "Pad 5",
        UInt32(kVK_ANSI_Keypad6): "Pad 6", UInt32(kVK_ANSI_Keypad7): "Pad 7", UInt32(kVK_ANSI_Keypad8): "Pad 8",
        UInt32(kVK_ANSI_Keypad9): "Pad 9", UInt32(kVK_ANSI_KeypadDecimal): "Pad .", UInt32(kVK_ANSI_KeypadMultiply): "Pad *",
        UInt32(kVK_ANSI_KeypadPlus): "Pad +", UInt32(kVK_ANSI_KeypadDivide): "Pad /", UInt32(kVK_ANSI_KeypadMinus): "Pad -",
        UInt32(kVK_ANSI_KeypadEquals): "Pad =",
    ]

    static func isFunctionKey(_ keyCode: UInt32) -> Bool {
        let fkeys: Set<Int> = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                               kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
        return fkeys.contains(Int(keyCode))
    }

    static func name(for keyCode: UInt32) -> String {
        if let s = special[keyCode] { return s }
        if let translated = translate(keyCode), !translated.isEmpty { return translated.uppercased() }
        return "Key \(keyCode)"
    }

    /// Uses the current keyboard layout to translate a key code to its unmodified character.
    private static func translate(_ keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = unsafeBitCast(layoutPtr, to: CFData.self) as Data
        return data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) -> String? in
            guard let base = buf.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeyState: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(base, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                                        UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysBit),
                                        &deadKeyState, chars.count, &length, &chars)
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: length)
        }
    }
}
