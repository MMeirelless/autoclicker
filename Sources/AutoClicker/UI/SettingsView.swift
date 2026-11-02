import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var inputMonitoring = Permissions.inputMonitoringGranted
    @State private var resetError: String?

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        Form {
            Section {
                HotkeyRecorderView(title: "Start / stop clicker", combo: $state.settings.clickerHotkey,
                                   taken: state.assignedHotkeys(excluding: state.settings.clickerHotkey))
                HotkeyRecorderView(title: "Stop all macros", combo: $state.settings.stopAllMacrosHotkey,
                                   taken: state.assignedHotkeys(excluding: state.settings.stopAllMacrosHotkey))
                HotkeyRecorderView(title: "Toggle Dock icon", combo: $state.settings.toggleDockIconHotkey,
                                   taken: state.assignedHotkeys(excluding: state.settings.toggleDockIconHotkey))
                HotkeyRecorderView(title: "Toggle Menu Bar icon", combo: $state.settings.toggleMenuBarIconHotkey,
                                   taken: state.assignedHotkeys(excluding: state.settings.toggleMenuBarIconHotkey))
                if let warning = state.hotkeyWarning {
                    HStack(alignment: .top) {
                        Label(warning, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                        Spacer()
                        Button("Retry") { state.retryHotkeys() }.controlSize(.small)
                    }
                }
            } header: {
                Text("Shortcuts")
            } footer: {
                Text("Shortcuts work system-wide, so you can stop a fast clicker without opening the app. Each macro has its own shortcut, set in the macro editor. Combinations used by macOS are rejected and a free one is suggested.")
            }

            Section("General") {
                Toggle("Launch at login", isOn: $state.settings.launchAtLogin)
                    .onChange(of: state.settings.launchAtLogin) { _, _ in state.applyLaunchAtLogin() }
            }

            Section {
                HStack {
                    StatusDot(color: state.permissionsOK ? .green : .red,
                              text: "Accessibility — " + (state.permissionsOK ? "granted" : "not granted"))
                    Spacer()
                    if !state.permissionsOK {
                        Button("Reset & re-request…") {
                            resetError = Permissions.resetAndRequestAccessibility()
                            if resetError == nil { Permissions.openAccessibilitySettings() }
                        }
                        .help("Use this when AutoClicker is already enabled in the list but still reports the permission as missing (typical after a rebuild).")
                    }
                    Button("Open Settings…") {
                        Permissions.requestAccessibility()
                        Permissions.openAccessibilitySettings()
                    }
                }
                if let resetError {
                    Text("Reset failed: \(resetError)").font(.caption).foregroundStyle(.red)
                }
                HStack {
                    StatusDot(color: inputMonitoring ? .green : .orange,
                              text: "Input Monitoring — " + (inputMonitoring ? "granted" : "needed to record keys"))
                    Spacer()
                    Button("Open Settings…") {
                        Permissions.requestInputMonitoring()
                        Permissions.openInputMonitoringSettings()
                    }
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("The list is called \(Permissions.accessibilityListName). macOS ties the grant to the app's code signature, so an ad-hoc signed build must be re-allowed after every rebuild: use “Reset & re-request”, or remove the app from the list and add it again. Build with `make cert` once to get a stable signature.")
            }

            Section("Data") {
                HStack {
                    Text("Settings and macros are stored in Application Support.")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Store.directory]) }
                }
                Button("Reset clicker settings to defaults", role: .destructive) { state.resetSettings() }
            }

            Section("About") {
                LabeledContent("AutoClicker", value: "Version \(version)")
                Link("Source code on GitHub", destination: URL(string: "https://github.com/MMeirelless/autoclicker")!)
                Button("Quit AutoClicker") { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            inputMonitoring = Permissions.inputMonitoringGranted
        }
    }
}
