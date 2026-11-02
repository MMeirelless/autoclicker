import AppKit

/// Keeps a single running copy of the app, whichever bundle path it was launched from.
enum SingleInstance {
    /// Distributed notification asking the running copy to show its UI.
    static let showUINotification = Notification.Name("com.mmeirelless.autoclicker.showUI")

    static func otherRunningCopy() -> NSRunningApplication? {
        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }
        let me = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first { $0.processIdentifier != me && !$0.isTerminated }
    }

    /// Activates the existing copy and asks it to open its window or popover.
    static func handOff(to other: NSRunningApplication) {
        other.activate()
        DistributedNotificationCenter.default().postNotificationName(
            showUINotification, object: nil, userInfo: nil, deliverImmediately: true)
    }

    /// Called by the running copy so that launching the app again simply brings it forward.
    static func observeHandOff(_ handler: @escaping () -> Void) {
        DistributedNotificationCenter.default().addObserver(
            forName: showUINotification, object: nil, queue: .main) { _ in handler() }
    }
}
