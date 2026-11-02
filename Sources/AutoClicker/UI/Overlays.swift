import AppKit

/// Conversions between Cocoa screen coordinates (origin bottom-left of the primary display) and
/// CoreGraphics global coordinates (origin top-left of the primary display).
enum ScreenCoordinates {
    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    static func cgRect(fromCocoa rect: NSRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func cocoaRect(fromCG rect: CGRect) -> NSRect {
        NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func cgPoint(fromCocoa point: NSPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }
}

// MARK: - Interactive selection overlay (area / point)

/// Full-screen, per-display overlay used to drag out a click area or pick a single point.
final class SelectionOverlay {
    enum Mode { case rect, point }

    private static var current: SelectionOverlay?

    private var windows: [NSWindow] = []
    private let mode: Mode
    private let completion: (CGRect?) -> Void
    private var dragStart: NSPoint?
    private var dragCurrent: NSPoint?

    /// Lets the user drag a rectangle. Completion receives the area in CG coordinates (nil if cancelled).
    static func selectArea(completion: @escaping (CGRect?) -> Void) {
        begin(mode: .rect, completion: completion)
    }

    /// Lets the user click a point. Completion receives the point in CG coordinates (nil if cancelled).
    static func pickPoint(completion: @escaping (CGPoint?) -> Void) {
        begin(mode: .point) { rect in completion(rect?.origin) }
    }

    private static func begin(mode: Mode, completion: @escaping (CGRect?) -> Void) {
        current?.finish(nil)
        let overlay = SelectionOverlay(mode: mode, completion: completion)
        current = overlay
        overlay.show()
    }

    private init(mode: Mode, completion: @escaping (CGRect?) -> Void) {
        self.mode = mode
        self.completion = completion
    }

    private func show() {
        for screen in NSScreen.screens {
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = false
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.overlay = self
            window.contentView = view
            windows.append(window)
        }
        NSApp.activate()
        windows.forEach { $0.makeKeyAndOrderFront(nil) }
        windows.first?.makeFirstResponder(windows.first?.contentView)
        NSCursor.crosshair.push()
    }

    fileprivate func mouseDown(at screenPoint: NSPoint) {
        dragStart = screenPoint
        dragCurrent = screenPoint
        if mode == .point {
            finish(CGRect(origin: ScreenCoordinates.cgPoint(fromCocoa: screenPoint), size: .zero))
            return
        }
        redraw()
    }

    fileprivate func mouseDragged(to screenPoint: NSPoint) {
        guard mode == .rect else { return }
        dragCurrent = screenPoint
        redraw()
    }

    fileprivate func mouseUp(at screenPoint: NSPoint) {
        guard mode == .rect, let start = dragStart else { return }
        let rect = NSRect(x: min(start.x, screenPoint.x), y: min(start.y, screenPoint.y),
                          width: abs(screenPoint.x - start.x), height: abs(screenPoint.y - start.y))
        if rect.width < 4 || rect.height < 4 {
            dragStart = nil
            dragCurrent = nil
            redraw()
            return
        }
        finish(ScreenCoordinates.cgRect(fromCocoa: rect))
    }

    fileprivate func cancel() { finish(nil) }

    fileprivate var currentCocoaRect: NSRect? {
        guard let s = dragStart, let c = dragCurrent, mode == .rect else { return nil }
        return NSRect(x: min(s.x, c.x), y: min(s.y, c.y), width: abs(c.x - s.x), height: abs(c.y - s.y))
    }

    fileprivate var instructions: String {
        switch mode {
        case .rect: return "Drag to select the click area  ·  Esc to cancel"
        case .point: return "Click to choose the point  ·  Esc to cancel"
        }
    }

    private func redraw() {
        windows.forEach { $0.contentView?.needsDisplay = true }
    }

    private func finish(_ result: CGRect?) {
        NSCursor.pop()
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        if SelectionOverlay.current === self { SelectionOverlay.current = nil }
        completion(result)
    }
}

private final class SelectionView: NSView {
    weak var overlay: SelectionOverlay?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) { overlay?.mouseDown(at: NSEvent.mouseLocation) }
    override func mouseDragged(with event: NSEvent) { overlay?.mouseDragged(to: NSEvent.mouseLocation) }
    override func mouseUp(with event: NSEvent) { overlay?.mouseUp(at: NSEvent.mouseLocation) }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { overlay?.cancel() } // Esc
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let overlay, let window else { return }
        NSColor.black.withAlphaComponent(0.25).setFill()
        bounds.fill()

        if let screenRect = overlay.currentCocoaRect {
            let local = window.convertFromScreen(screenRect)
            NSColor.clear.setFill()
            local.fill(using: .copy)
            IconRenderer.activeColor.withAlphaComponent(0.15).setFill()
            local.fill()
            IconRenderer.activeColor.setStroke()
            let path = NSBezierPath(rect: local)
            path.lineWidth = 2
            path.stroke()

            let size = "\(Int(screenRect.width)) × \(Int(screenRect.height))"
            draw(label: size, at: NSPoint(x: local.minX, y: local.maxY + 6))
        }

        // Instructions at the top-centre of each screen.
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: NSColor.white,
        ]
        let text = NSAttributedString(string: overlay.instructions, attributes: attrs)
        let textSize = text.size()
        let box = NSRect(x: (bounds.width - textSize.width) / 2 - 14, y: bounds.height - 70,
                         width: textSize.width + 28, height: textSize.height + 14)
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8).fill()
        text.draw(at: NSPoint(x: box.minX + 14, y: box.minY + 7))
    }

    private func draw(label: String, at point: NSPoint) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white,
        ]
        let text = NSAttributedString(string: label, attributes: attrs)
        let size = text.size()
        let box = NSRect(x: point.x, y: point.y, width: size.width + 12, height: size.height + 6)
        IconRenderer.activeColor.setFill()
        NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
        text.draw(at: NSPoint(x: box.minX + 6, y: box.minY + 3))
    }
}

// MARK: - Passive outline shown while the clicker runs inside an area

final class AreaOverlayWindow {
    private var window: NSWindow?

    func show(area: CGRect) {
        let frame = ScreenCoordinates.cocoaRect(fromCG: area).insetBy(dx: -3, dy: -3)
        if window == nil {
            let w = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.level = .floating
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.isReleasedWhenClosed = false
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            w.contentView = OutlineView(frame: NSRect(origin: .zero, size: frame.size))
            window = w
        }
        window?.setFrame(frame, display: true)
        window?.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }
}

private final class OutlineView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 2, dy: 2)
        IconRenderer.activeColor.withAlphaComponent(0.06).setFill()
        rect.fill()
        IconRenderer.activeColor.setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 2
        path.setLineDash([8, 5], count: 2, phase: 0)
        path.stroke()
    }
}
