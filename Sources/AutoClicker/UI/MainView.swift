import SwiftUI

enum MainTab: String, CaseIterable, Identifiable {
    case clicker, macros, appIcon, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .clicker: return "Clicker"
        case .macros: return "Macros"
        case .appIcon: return "App Icon"
        case .settings: return "Settings"
        }
    }
    var symbol: String {
        switch self {
        case .clicker: return "cursorarrow.click.2"
        case .macros: return "list.bullet.rectangle"
        case .appIcon: return "app.badge"
        case .settings: return "gearshape"
        }
    }
}

struct MainView: View {
    @EnvironmentObject var state: AppState
    @State private var tab: MainTab = .clicker

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(MainTab.allCases) { t in
                    Text(t.title).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            Group {
                switch tab {
                case .clicker: ClickerView()
                case .macros: MacroListView()
                case .appIcon: AppIconView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !state.permissionsOK {
                Divider()
                PermissionBanner()
            }
        }
        .frame(width: AppDelegate.uiSize.width, height: AppDelegate.uiSize.height)
    }
}

/// Shown at the bottom of the UI until Accessibility is granted.
struct PermissionBanner: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility permission required").font(.callout.bold())
                Text("System Settings → Privacy & Security → Accessibility → add AutoClicker. If it is already listed but not working, remove it and add it again.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Grant…") {
                Permissions.requestAccessibility()
                Permissions.openAccessibilitySettings()
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.08))
    }
}
