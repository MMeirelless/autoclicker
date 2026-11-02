import AppKit
import Carbon.HIToolbox

/// Global hotkeys via Carbon `RegisterEventHotKey` (works system-wide without an event tap).
final class HotkeyManager {
    static let shared = HotkeyManager()

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var combos: [UInt32: KeyCombo] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?
    private static let signature: OSType = 0x41434C4B // 'ACLK'

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotkeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotkeyID)
            guard status == noErr else { return status }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            if let handler = manager.handlers[hotkeyID.id] {
                DispatchQueue.main.async { handler() }
            }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec,
                            Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }

    /// Registers a global hotkey. Returns an identifier for `unregister`, or nil on failure
    /// (`lastError` then explains why, typically because another app already owns the combination).
    @discardableResult
    func register(_ combo: KeyCombo, handler: @escaping () -> Void) -> UInt32? {
        guard combo.isValidGlobalHotkey else {
            lastError = "\(combo.displayString) needs a modifier key or a function key."
            return nil
        }
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hotkeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, hotkeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            lastError = Self.describe(status, combo: combo)
            return nil
        }
        refs[id] = ref
        handlers[id] = handler
        combos[id] = combo
        lastError = nil
        return id
    }

    /// Why the last `register` call failed.
    private(set) var lastError: String?

    /// Whether macOS would let this app register `combo` right now (true if we already hold it).
    /// Another app holding the same combination (another autoclicker, a second copy of this app…)
    /// makes `RegisterEventHotKey` fail, which the recorder reports instead of silently assigning it.
    func canRegister(_ combo: KeyCombo) -> Bool {
        guard combo.isValidGlobalHotkey else { return false }
        if isRegistered(combo) { return true }
        var ref: EventHotKeyRef?
        let probe = EventHotKeyID(signature: Self.signature, id: 0)
        let status = RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, probe,
                                         GetApplicationEventTarget(), 0, &ref)
        if let ref { UnregisterEventHotKey(ref) }
        return status == noErr
    }

    private static func describe(_ status: OSStatus, combo: KeyCombo) -> String {
        if status == OSStatus(eventHotKeyExistsErr) {
            return "\(combo.displayString) is already used by another app."
        }
        return "\(combo.displayString) could not be registered (error \(status))."
    }

    func unregister(_ id: UInt32) {
        if let ref = refs[id] { UnregisterEventHotKey(ref) }
        refs[id] = nil
        handlers[id] = nil
        combos[id] = nil
    }

    func unregisterAll() {
        for id in Array(refs.keys) { unregister(id) }
    }

    /// Whether this combo is already used by another hotkey registered by this app.
    func isRegistered(_ combo: KeyCombo, excluding: UInt32? = nil) -> Bool {
        combos.contains { $0.key != excluding && $0.value == combo }
    }

    // MARK: Conflict detection

    /// Enabled system-wide symbolic hotkeys (Spotlight, Mission Control, screenshots…), read from Carbon.
    static var systemHotkeys: Set<KeyCombo> = {
        var result = Set<KeyCombo>()
        var array: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&array) == noErr, let list = array?.takeRetainedValue() as? [[String: Any]] else {
            return result
        }
        for entry in list {
            guard let enabled = entry[kHISymbolicHotKeyEnabled] as? Bool, enabled,
                  let code = entry[kHISymbolicHotKeyCode] as? Int,
                  let mods = entry[kHISymbolicHotKeyModifiers] as? Int, code >= 0, code < 0xFFFF else { continue }
            var flags: NSEvent.ModifierFlags = []
            if mods & cmdKey != 0 { flags.insert(.command) }
            if mods & optionKey != 0 { flags.insert(.option) }
            if mods & controlKey != 0 { flags.insert(.control) }
            if mods & shiftKey != 0 { flags.insert(.shift) }
            result.insert(KeyCombo(keyCode: UInt32(code), modifiers: flags))
        }
        // Well-known application-level shortcuts macOS reserves that are not symbolic hotkeys.
        let reserved: [(Int, NSEvent.ModifierFlags)] = [
            (kVK_ANSI_Q, .command), (kVK_ANSI_W, .command), (kVK_ANSI_H, .command), (kVK_ANSI_M, .command),
            (kVK_Tab, .command), (kVK_Space, .command), (kVK_ANSI_Grave, .command),
            (kVK_Escape, [.command, .option]), (kVK_ANSI_Q, [.command, .shift]),
        ]
        for (code, mods) in reserved { result.insert(KeyCombo(keyCode: UInt32(code), modifiers: mods)) }
        return result
    }()

    static func conflictsWithSystem(_ combo: KeyCombo) -> Bool {
        systemHotkeys.contains(combo)
    }

    /// Suggests a free "Control + Number"-style shortcut not used by the system or by `taken`.
    /// With `probe`, combinations currently held by other apps are skipped as well.
    static func suggestFreeCombo(avoiding taken: [KeyCombo], probe: Bool = false) -> KeyCombo? {
        KeyCombo.suggestionPool.first {
            !taken.contains($0) && !conflictsWithSystem($0) && (!probe || shared.canRegister($0))
        }
    }
}
