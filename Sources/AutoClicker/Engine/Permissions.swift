import AppKit
import ApplicationServices

/// Accessibility (needed to post synthetic events) and Input Monitoring (needed to record keys).
enum Permissions {
    static var accessibilityGranted: Bool { AXIsProcessTrusted() }

    /// Name of the list in System Settings; recent macOS versions renamed Accessibility.
    static let accessibilityListName = "Accessibility (\u{201C}Device Control and Data Access\u{201D} on newer macOS)"

    /// Shows the system prompt that offers to add the app to Privacy & Security → Accessibility.
    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// macOS ties the grant to the app's code signature. An ad-hoc signed build gets a new signature on
    /// every rebuild, so the app stays listed as allowed yet `AXIsProcessTrusted` returns false.
    /// Resetting the entry (what `tccutil reset` does) lets the next prompt register the current build.
    /// Returns an error message, or nil when the reset succeeded.
    @discardableResult
    static func resetAccessibility() -> String? {
        guard let bundleID = Bundle.main.bundleIdentifier else { return "No bundle identifier." }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", bundleID]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return "Could not run tccutil: \(error.localizedDescription)"
        }
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus == 0 { return nil }
        return output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "tccutil exited with status \(process.terminationStatus)." : output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Resets a stale grant, then shows the system prompt again so the current build gets registered.
    /// Returns an error message when the reset failed.
    @discardableResult
    static func resetAndRequestAccessibility() -> String? {
        let error = resetAccessibility()
        requestAccessibility()
        return error
    }

    static var inputMonitoringGranted: Bool { CGPreflightListenEventAccess() }

    @discardableResult
    static func requestInputMonitoring() -> Bool { CGRequestListenEventAccess() }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    private static func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}
