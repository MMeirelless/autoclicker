import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) static var shared: AppDelegate!

    let state = AppState()

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var mainWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    static let uiSize = NSSize(width: 500, height: 640)

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        setupStatusItem()

        popover.contentSize = Self.uiSize
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: rootView())

        applyIconSettings()
        let iconKeys: AnyPublisher<[String], Never> = state.$settings
            .map { [$0.iconVisibility.rawValue, $0.iconStyle.rawValue] }
            .eraseToAnyPublisher()
        iconKeys
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.applyIconSettings() }
            .store(in: &cancellables)

        state.start()

        if !state.settings.iconVisibility.showsMenuBar {
            showMainWindow()
        } else if ProcessInfo.processInfo.environment["AUTOCLICKER_OPEN_WINDOW"] != nil {
            showMainWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showUI()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func application(_ application: NSApplication, open urls: [URL]) {
        state.handleIncoming(urls: urls)
        showUI()
    }

    func applicationWillTerminate(_ notification: Notification) {
        state.shutdown()
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = IconRenderer.statusIcon(active: false)
            button.toolTip = "AutoClicker"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            showStatusMenu()
        } else {
            togglePopover()
        }
    }

    private func showStatusMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open AutoClicker", action: #selector(menuOpen), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let clickerItem = NSMenuItem(title: state.clicker.isActive ? "Stop Clicker" : "Start Clicker",
                                     action: #selector(menuToggleClicker), keyEquivalent: "")
        clickerItem.target = self
        menu.addItem(clickerItem)
        let stopMacros = NSMenuItem(title: "Stop All Macros", action: #selector(menuStopMacros), keyEquivalent: "")
        stopMacros.target = self
        stopMacros.isEnabled = !state.macroPlayer.runningIDs.isEmpty || !state.macroPlayer.scheduled.isEmpty
        menu.addItem(stopMacros)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit AutoClicker", action: #selector(menuQuit), keyEquivalent: "q").target = self

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func menuOpen() { showUI() }
    @objc private func menuToggleClicker() { state.toggleClicker() }
    @objc private func menuStopMacros() { state.macroPlayer.stopAll() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    /// Updates the menu-bar icon colour: gray when idle, turquoise while the clicker runs.
    func updateStatusIcon(active: Bool) {
        statusItem.button?.image = IconRenderer.statusIcon(active: active)
    }

    // MARK: - Presenting the UI

    /// True when the menu-bar button is actually on a screen. macOS can keep an item "visible" yet
    /// park it off-screen when the menu bar is full; anchoring a popover to it would be useless.
    var statusItemIsOnScreen: Bool {
        guard statusItem.isVisible, let frame = statusItem.button?.window?.frame else { return false }
        return NSScreen.screens.contains { $0.frame.intersects(frame) }
    }

    func showUI() {
        if statusItemIsOnScreen { showPopover() } else { showMainWindow() }
    }

    func togglePopover() {
        if popover.isShown { popover.performClose(nil) } else { showPopover() }
    }

    func showPopover() {
        guard statusItemIsOnScreen, let button = statusItem.button else { showMainWindow(); return }
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func closePopover() {
        if popover.isShown { popover.performClose(nil) }
    }

    /// Hides whichever UI is showing (used before full-screen overlays such as area selection).
    func hideUI() {
        closePopover()
        mainWindow?.orderOut(nil)
    }

    func showMainWindow() {
        if mainWindow == nil {
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.uiSize),
                                  styleMask: [.titled, .closable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.title = "AutoClicker"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: rootView())
            window.center()
            mainWindow = window
        }
        NSApp.activate()
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    /// The main UI with every engine injected as an environment object.
    private func rootView() -> some View {
        MainView()
            .environmentObject(state)
            .environmentObject(state.clicker)
            .environmentObject(state.macroPlayer)
            .environmentObject(state.recorder)
    }

    // MARK: - Icon settings

    func applyIconSettings() {
        let visibility = state.settings.iconVisibility
        NSApp.setActivationPolicy(visibility.showsDock ? .regular : .accessory)
        statusItem.isVisible = visibility.showsMenuBar
        NSApp.applicationIconImage = IconRenderer.appIcon(style: state.settings.iconStyle, size: 512)
        if !visibility.showsMenuBar { closePopover() }
    }
}
