import Foundation

/// Where the app icon is shown.
enum IconVisibility: String, Codable, CaseIterable, Identifiable {
    case both, dockOnly, menuBarOnly, hidden
    var id: String { rawValue }
    var label: String {
        switch self {
        case .both: return "Dock and Menu Bar"
        case .dockOnly: return "Dock only"
        case .menuBarOnly: return "Menu Bar only"
        case .hidden: return "Hidden"
        }
    }
    var showsDock: Bool { self == .both || self == .dockOnly }
    var showsMenuBar: Bool { self == .both || self == .menuBarOnly }

    static func from(dock: Bool, menuBar: Bool) -> IconVisibility {
        switch (dock, menuBar) {
        case (true, true): return .both
        case (true, false): return .dockOnly
        case (false, true): return .menuBarOnly
        case (false, false): return .hidden
        }
    }
}

/// Built-in app icon styles (rendered at runtime by `IconRenderer`).
enum AppIconStyle: String, Codable, CaseIterable, Identifiable {
    case teal, graphite, sunset, ocean, grape, mono
    var id: String { rawValue }
    var label: String {
        switch self {
        case .teal: return "Classic Teal"
        case .graphite: return "Graphite"
        case .sunset: return "Sunset"
        case .ocean: return "Ocean"
        case .grape: return "Grape"
        case .mono: return "Mono"
        }
    }
}

struct AppSettings: Codable, Equatable {
    var clicker: ClickerConfig = ClickerConfig()

    var clickerHotkey: KeyCombo? = .defaultClicker
    var stopAllMacrosHotkey: KeyCombo? = .defaultStopAllMacros
    var toggleDockIconHotkey: KeyCombo? = .defaultToggleDockIcon
    var toggleMenuBarIconHotkey: KeyCombo? = .defaultToggleMenuBarIcon

    var iconVisibility: IconVisibility = .menuBarOnly
    var iconStyle: AppIconStyle = .teal

    var launchAtLogin: Bool = false
    /// Play a short sound when the clicker starts/stops.
    var soundFeedback: Bool = false
}
