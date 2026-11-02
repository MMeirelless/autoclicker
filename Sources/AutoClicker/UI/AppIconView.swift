import SwiftUI

struct AppIconView: View {
    @EnvironmentObject var state: AppState

    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 12)]

    var body: some View {
        Form {
            Section("Icon style") {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(AppIconStyle.allCases) { style in
                        VStack(spacing: 6) {
                            Image(nsImage: IconRenderer.appIcon(style: style, size: 128))
                                .resizable()
                                .frame(width: 64, height: 64)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(state.settings.iconStyle == style ? Color.accentColor : .clear, lineWidth: 3)
                                )
                            Text(style.label).font(.caption)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { state.settings.iconStyle = style }
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Picker("Show the icon in", selection: $state.settings.iconVisibility) {
                    ForEach(IconVisibility.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.radioGroup)
                if state.settings.iconVisibility == .hidden {
                    Label("With both icons hidden, reopen the app from Finder, Spotlight, or with the shortcuts below.",
                          systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.orange)
                }
            } header: {
                Text("Visibility")
            } footer: {
                Text("The app hides automatically when you click outside its window so it doesn't get in your way.")
            }

            Section("Shortcuts") {
                HotkeyRecorderView(title: "Toggle Dock icon", combo: $state.settings.toggleDockIconHotkey,
                                   taken: state.assignedHotkeys(excluding: state.settings.toggleDockIconHotkey))
                HotkeyRecorderView(title: "Toggle Menu Bar icon", combo: $state.settings.toggleMenuBarIconHotkey,
                                   taken: state.assignedHotkeys(excluding: state.settings.toggleMenuBarIconHotkey))
            }

            Section("Renaming the app") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("The name is changed at the system level:")
                    Text("1. Quit AutoClicker.\n2. In Finder, select AutoClicker.app and press Return (or File → Get Info → Name & Extension).\n3. Type the new name and press Return.")
                    Text("Some system utilities and process monitors may still show the original name — they use the app's internal name rather than the display name.")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }
        }
        .formStyle(.grouped)
    }
}
