import AppKit
import Combine
import ServiceManagement

private struct MacroHotkeyKey: Equatable {
    let id: UUID
    let hotkey: KeyCombo?
}

/// Root model object: settings, macros, engines, hotkeys and persistence.
final class AppState: ObservableObject {
    @Published var settings: AppSettings {
        didSet { scheduleSave() }
    }
    @Published var macros: [Macro] {
        didSet { scheduleSave() }
    }
    @Published private(set) var permissionsOK = Permissions.accessibilityGranted
    @Published var hotkeyWarning: String?

    let clicker = ClickerEngine()
    let macroPlayer = MacroPlayer()
    let recorder = MacroRecorder()

    private var cancellables = Set<AnyCancellable>()
    private var saveWork: DispatchWorkItem?
    private var permissionTimer: Timer?
    private var settingsHotkeyIDs: [UInt32] = []
    private var macroHotkeyIDs: [UUID: UInt32] = [:]
    private var areaOverlay: AreaOverlayWindow?

    init() {
        settings = Store.load(AppSettings.self, from: Store.settingsURL) ?? AppSettings()
        macros = Store.load([Macro].self, from: Store.macrosURL) ?? []
    }

    // MARK: Lifecycle

    /// Wires engines, hotkeys and observers. Called once from the app delegate.
    func start() {
        clicker.configProvider = { [unowned self] in self.settings.clicker }
        clicker.onActiveChanged = { active in AppDelegate.shared?.updateStatusIcon(active: active) }
        clicker.onAreaOverlayChanged = { [weak self] rect in self?.showAreaOverlay(rect) }
        macroPlayer.macroProvider = { [unowned self] id in self.macros.first { $0.id == id } }

        registerSettingsHotkeys()
        registerMacroHotkeys()
        clicker.scheduleDailyRepeat(settings.clicker.timers)
        macroPlayer.syncDailyTimers(macros)

        let settingsHotkeys: AnyPublisher<[KeyCombo?], Never> = $settings
            .map { s -> [KeyCombo?] in [s.clickerHotkey, s.stopAllMacrosHotkey, s.toggleDockIconHotkey, s.toggleMenuBarIconHotkey] }
            .eraseToAnyPublisher()
        settingsHotkeys
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.registerSettingsHotkeys() }
            .store(in: &cancellables)

        let timers: AnyPublisher<TimerConfig, Never> = $settings.map { $0.clicker.timers }.eraseToAnyPublisher()
        timers
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] timers in self?.clicker.scheduleDailyRepeat(timers) }
            .store(in: &cancellables)

        let macroHotkeys: AnyPublisher<[MacroHotkeyKey], Never> = $macros
            .map { list -> [MacroHotkeyKey] in list.map { MacroHotkeyKey(id: $0.id, hotkey: $0.hotkey) } }
            .eraseToAnyPublisher()
        macroHotkeys
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.registerMacroHotkeys() }
            .store(in: &cancellables)

        $macros
            .dropFirst()
            .sink { [weak self] macros in self?.macroPlayer.syncDailyTimers(macros) }
            .store(in: &cancellables)

        // Forward engine changes so views observing only AppState refresh too.
        clicker.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        macroPlayer.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        recorder.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)

        startPermissionPolling()
        applyLaunchAtLogin()
    }

    func shutdown() {
        clicker.stop()
        macroPlayer.stopAll()
        recorder.cancel()
        saveNow()
    }

    // MARK: Clicker helpers

    func toggleClicker() {
        if case .waiting = clicker.status {
            clicker.startNow()
        } else {
            clicker.toggle()
        }
    }

    private func showAreaOverlay(_ rect: CGRect?) {
        if let rect {
            if areaOverlay == nil { areaOverlay = AreaOverlayWindow() }
            areaOverlay?.show(area: rect)
        } else {
            areaOverlay?.hide()
        }
    }

    // MARK: Macros

    func upsert(_ macro: Macro) {
        var m = macro
        m.modifiedAt = Date()
        if let index = macros.firstIndex(where: { $0.id == m.id }) {
            macros[index] = m
        } else {
            macros.append(m)
        }
    }

    func delete(_ id: UUID) {
        macroPlayer.stop(id)
        macros.removeAll { $0.id == id }
    }

    func duplicate(_ macro: Macro) -> Macro {
        let copy = macro.duplicated()
        macros.append(copy)
        return copy
    }

    /// Handles `autoclicker://` links and `.autoclickermacro` files opened with the app.
    func handleIncoming(urls: [URL]) {
        for url in urls {
            if let macro = MacroSharing.decode(url: url) {
                importShared(macro)
            }
        }
    }

    func importShared(_ incoming: Macro) {
        var macro = incoming
        macro.id = UUID()
        macro.hotkey = nil
        macro.createdAt = Date()
        macro.modifiedAt = Date()
        if macros.contains(where: { $0.name == macro.name }) { macro.name += " (imported)" }
        macros.append(macro)
    }

    // MARK: Hotkeys

    private func registerSettingsHotkeys() {
        settingsHotkeyIDs.forEach { HotkeyManager.shared.unregister($0) }
        settingsHotkeyIDs = []
        var failures: [String] = []

        func reg(_ combo: KeyCombo?, _ label: String, _ action: @escaping () -> Void) {
            guard let combo else { return }
            if let id = HotkeyManager.shared.register(combo, handler: action) {
                settingsHotkeyIDs.append(id)
            } else {
                failures.append("\(label) (\(combo.displayString))")
            }
        }

        reg(settings.clickerHotkey, "Clicker") { [weak self] in self?.toggleClicker() }
        reg(settings.stopAllMacrosHotkey, "Stop all macros") { [weak self] in
            self?.macroPlayer.stopAll()
            self?.recorder.stopIfRecording()
        }
        reg(settings.toggleDockIconHotkey, "Toggle Dock icon") { [weak self] in
            guard let self else { return }
            let v = self.settings.iconVisibility
            self.settings.iconVisibility = .from(dock: !v.showsDock, menuBar: v.showsMenuBar)
        }
        reg(settings.toggleMenuBarIconHotkey, "Toggle Menu Bar icon") { [weak self] in
            guard let self else { return }
            let v = self.settings.iconVisibility
            self.settings.iconVisibility = .from(dock: v.showsDock, menuBar: !v.showsMenuBar)
        }
        hotkeyWarning = failures.isEmpty ? nil : "Could not register: " + failures.joined(separator: ", ")
    }

    private func registerMacroHotkeys() {
        macroHotkeyIDs.values.forEach { HotkeyManager.shared.unregister($0) }
        macroHotkeyIDs = [:]
        for macro in macros {
            guard let combo = macro.hotkey else { continue }
            let id = macro.id
            if let hk = HotkeyManager.shared.register(combo, handler: { [weak self] in
                guard let self, let current = self.macros.first(where: { $0.id == id }) else { return }
                self.macroPlayer.toggle(current)
            }) {
                macroHotkeyIDs[id] = hk
            }
        }
    }

    /// Every shortcut currently assigned in the app (for conflict checks when recording a new one).
    func assignedHotkeys(excluding: KeyCombo? = nil) -> [KeyCombo] {
        var list = [settings.clickerHotkey, settings.stopAllMacrosHotkey,
                    settings.toggleDockIconHotkey, settings.toggleMenuBarIconHotkey].compactMap { $0 }
        list += macros.compactMap(\.hotkey)
        if let excluding { list.removeAll { $0 == excluding } }
        return list
    }

    // MARK: Permissions

    private func startPermissionPolling() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            let ok = Permissions.accessibilityGranted
            if ok != self.permissionsOK { self.permissionsOK = ok }
        }
    }

    // MARK: Launch at login

    func applyLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if settings.launchAtLogin {
                if service.status != .enabled { try service.register() }
            } else if service.status == .enabled {
                try service.unregister()
            }
        } catch {
            NSLog("AutoClicker: launch at login change failed: \(error)")
        }
    }

    // MARK: Persistence

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func saveNow() {
        saveWork?.cancel()
        Store.save(settings, to: Store.settingsURL)
        Store.save(macros, to: Store.macrosURL)
    }

    func resetSettings() {
        settings = AppSettings()
    }
}
