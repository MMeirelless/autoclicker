import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var inputMonitoring = Permissions.inputMonitoringGranted

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
                    Label(warning, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
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
                    Button("Open Settings…") {
                        Permissions.requestAccessibility()
                        Permissions.openAccessibilitySettings()
                    }
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
                Text("If the clicker is listed in Accessibility but still doesn't work, remove it from the list and add it again. Each rebuild of an ad-hoc signed app may require re-granting.")
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
