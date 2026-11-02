import AppKit
import CoreGraphics

/// Posts synthetic mouse / keyboard / scroll events through the HID event tap.
/// All coordinates are CoreGraphics global coordinates (origin at the top-left of the main display).
enum EventSynthesizer {
    private static let source = CGEventSource(stateID: .hidSystemState)
    private static let neverCancel = AtomicFlag()

    /// Current cursor location in CG coordinates.
    static func cursorPosition() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    /// Bounds of the display that contains `point` (or the main display).
    static func displayBounds(containing point: CGPoint) -> CGRect {
        var display: CGDirectDisplayID = 0
        var count: UInt32 = 0
        if CGGetDisplaysWithPoint(point, 1, &display, &count) == .success, count > 0 {
            return CGDisplayBounds(display)
        }
        return CGDisplayBounds(CGMainDisplayID())
    }

    static func randomPoint(in rect: CGRect) -> CGPoint {
        guard rect.width > 0, rect.height > 0 else { return rect.origin }
        return CGPoint(x: CGFloat.random(in: rect.minX..<rect.maxX),
                       y: CGFloat.random(in: rect.minY..<rect.maxY))
    }

    // MARK: Mouse

    static func move(to point: CGPoint) {
        post(CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left))
    }

    private static func types(for button: MouseButton) -> (down: CGEventType, up: CGEventType, drag: CGEventType, cg: CGMouseButton) {
        switch button {
        case .left: return (.leftMouseDown, .leftMouseUp, .leftMouseDragged, .left)
        case .right: return (.rightMouseDown, .rightMouseUp, .rightMouseDragged, .right)
        case .middle: return (.otherMouseDown, .otherMouseUp, .otherMouseDragged, .center)
        }
    }

    /// Performs `count` presses (1 = single, 2 = double, 3 = triple) with the given hold time.
    static func click(button: MouseButton, at point: CGPoint, count: Int = 1,
                      hold: TimeInterval = 0, cancel: AtomicFlag = neverCancel) {
        let t = types(for: button)
        let presses = max(1, min(3, count))
        for i in 1...presses {
            let down = CGEvent(mouseEventSource: source, mouseType: t.down, mouseCursorPosition: point, mouseButton: t.cg)
            down?.setIntegerValueField(.mouseEventClickState, value: Int64(i))
            post(down)
            if hold > 0 { PreciseClock.sleep(seconds: hold, cancel: cancel) }
            let up = CGEvent(mouseEventSource: source, mouseType: t.up, mouseCursorPosition: point, mouseButton: t.cg)
            up?.setIntegerValueField(.mouseEventClickState, value: Int64(i))
            post(up)
            if i < presses { PreciseClock.sleep(seconds: 0.04, cancel: cancel) }
        }
    }

    /// Presses left and right buttons together.
    static func clickBoth(at point: CGPoint, hold: TimeInterval = 0, cancel: AtomicFlag = neverCancel) {
        post(CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left))
        post(CGEvent(mouseEventSource: source, mouseType: .rightMouseDown, mouseCursorPosition: point, mouseButton: .right))
        if hold > 0 { PreciseClock.sleep(seconds: hold, cancel: cancel) }
        post(CGEvent(mouseEventSource: source, mouseType: .rightMouseUp, mouseCursorPosition: point, mouseButton: .right))
        post(CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left))
    }

    /// Drag from `from` to `to` with the given button, interpolating intermediate drag events.
    static func drag(button: MouseButton, from: CGPoint, to: CGPoint, hold: TimeInterval = 0.05,
                     cancel: AtomicFlag = neverCancel) {
        let t = types(for: button)
        move(to: from)
        PreciseClock.sleep(seconds: 0.03, cancel: cancel)
        post(CGEvent(mouseEventSource: source, mouseType: t.down, mouseCursorPosition: from, mouseButton: t.cg))
        PreciseClock.sleep(seconds: max(hold, 0.03), cancel: cancel)
        let distance = hypot(to.x - from.x, to.y - from.y)
        let steps = max(4, min(40, Int(distance / 12)))
        for i in 1...steps {
            if cancel.isSet { break }
            let f = CGFloat(i) / CGFloat(steps)
            let p = CGPoint(x: from.x + (to.x - from.x) * f, y: from.y + (to.y - from.y) * f)
            post(CGEvent(mouseEventSource: source, mouseType: t.drag, mouseCursorPosition: p, mouseButton: t.cg))
            PreciseClock.sleep(seconds: 0.008, cancel: cancel)
        }
        PreciseClock.sleep(seconds: 0.03, cancel: cancel)
        post(CGEvent(mouseEventSource: source, mouseType: t.up, mouseCursorPosition: to, mouseButton: t.cg))
    }

    /// Scrolls by `dy` lines vertically (positive = up) and `dx` lines horizontally (positive = left).
    static func scroll(dx: Int32, dy: Int32, at point: CGPoint? = nil) {
        if let point { move(to: point) }
        let event = CGEvent(scrollWheelEvent2Source: source, units: .line, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0)
        if let point { event?.location = point }
        post(event)
    }

    // MARK: Keyboard

    static func cgFlags(_ modifiers: NSEvent.ModifierFlags) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if modifiers.contains(.function) { flags.insert(.maskSecondaryFn) }
        return flags
    }

    static func keyPress(keyCode: UInt32, modifiers: NSEvent.ModifierFlags, hold: TimeInterval = 0.02,
                         cancel: AtomicFlag = neverCancel) {
        let flags = cgFlags(modifiers)
        let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: true)
        down?.flags = flags
        post(down)
        PreciseClock.sleep(seconds: max(0.005, hold), cancel: cancel)
        let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: false)
        up?.flags = flags
        post(up)
    }

    private static func post(_ event: CGEvent?) {
        event?.post(tap: .cghidEventTap)
    }
}
