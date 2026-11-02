import AppKit

// Classic AppKit entry point: the whole UI lives in a menu-bar popover (or a window when the
// menu-bar icon is hidden), so no SwiftUI scene is needed.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
