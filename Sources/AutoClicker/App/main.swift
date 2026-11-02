import AppKit

// Classic AppKit entry point: the whole UI lives in a menu-bar popover (or a window when the
// menu-bar icon is hidden), so no SwiftUI scene is needed.

// Only one copy may run: two instances (e.g. build/ and /Applications) would fight over the global
// shortcuts and confuse the Accessibility grant, which is tied to one code signature.
if let other = SingleInstance.otherRunningCopy() {
    SingleInstance.handOff(to: other)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
