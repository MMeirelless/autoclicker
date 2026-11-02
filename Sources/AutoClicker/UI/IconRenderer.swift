import AppKit

/// Draws the menu-bar status icon and the selectable app icons at runtime.
enum IconRenderer {
    static let activeColor = NSColor(calibratedRed: 0.10, green: 0.78, blue: 0.72, alpha: 1) // turquoise

    /// Menu-bar icon. Gray template when idle; turquoise when the clicker is running.
    static func statusIcon(active: Bool) -> NSImage? {
        let base = NSImage(systemSymbolName: "cursorarrow.click.2", accessibilityDescription: "AutoClicker")
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        guard let symbol = base?.withSymbolConfiguration(config) else { return base }
        if active {
            let colored = symbol.withSymbolConfiguration(.init(paletteColors: [activeColor])) ?? symbol
            colored.isTemplate = false
            return colored
        }
        symbol.isTemplate = true
        return symbol
    }

    private static func gradient(for style: AppIconStyle) -> (NSColor, NSColor) {
        switch style {
        case .teal:
            return (NSColor(calibratedRed: 0.05, green: 0.70, blue: 0.68, alpha: 1),
                    NSColor(calibratedRed: 0.02, green: 0.42, blue: 0.52, alpha: 1))
        case .graphite:
            return (NSColor(calibratedWhite: 0.45, alpha: 1), NSColor(calibratedWhite: 0.15, alpha: 1))
        case .sunset:
            return (NSColor(calibratedRed: 0.99, green: 0.60, blue: 0.25, alpha: 1),
                    NSColor(calibratedRed: 0.85, green: 0.20, blue: 0.40, alpha: 1))
        case .ocean:
            return (NSColor(calibratedRed: 0.25, green: 0.60, blue: 1.0, alpha: 1),
                    NSColor(calibratedRed: 0.10, green: 0.20, blue: 0.65, alpha: 1))
        case .grape:
            return (NSColor(calibratedRed: 0.70, green: 0.40, blue: 0.95, alpha: 1),
                    NSColor(calibratedRed: 0.35, green: 0.10, blue: 0.60, alpha: 1))
        case .mono:
            return (NSColor(calibratedWhite: 0.98, alpha: 1), NSColor(calibratedWhite: 0.80, alpha: 1))
        }
    }

    /// Renders a full app icon (rounded square, click waves, cursor arrow) in the given style.
    static func appIcon(style: AppIconStyle, size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        let s = size
        let inset = s * 0.06
        let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: s * 0.22, yRadius: s * 0.22)
        let (c1, c2) = gradient(for: style)
        NSGradient(colors: [c1, c2])?.draw(in: path, angle: -70)

        let foreground: NSColor = style == .mono ? NSColor(calibratedWhite: 0.12, alpha: 1) : .white

        foreground.withAlphaComponent(0.9).setStroke()
        for (i, radius) in [0.16, 0.24, 0.32].enumerated() {
            let r = s * CGFloat(radius)
            let center = NSPoint(x: s * 0.40, y: s * 0.62)
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: r, startAngle: 20, endAngle: 160)
            arc.lineWidth = s * (0.045 - CGFloat(i) * 0.008)
            arc.lineCapStyle = .round
            arc.stroke()
        }

        let arrow = NSBezierPath()
        let ox = s * 0.40, oy = s * 0.62
        arrow.move(to: NSPoint(x: ox, y: oy))
        arrow.line(to: NSPoint(x: ox, y: oy - s * 0.40))
        arrow.line(to: NSPoint(x: ox + s * 0.10, y: oy - s * 0.31))
        arrow.line(to: NSPoint(x: ox + s * 0.17, y: oy - s * 0.46))
        arrow.line(to: NSPoint(x: ox + s * 0.235, y: oy - s * 0.43))
        arrow.line(to: NSPoint(x: ox + s * 0.165, y: oy - s * 0.28))
        arrow.line(to: NSPoint(x: ox + s * 0.29, y: oy - s * 0.28))
        arrow.close()
        arrow.lineJoinStyle = .round
        foreground.setFill()
        arrow.fill()
        NSColor(calibratedWhite: 0.1, alpha: 0.35).setStroke()
        arrow.lineWidth = s * 0.02
        arrow.stroke()
        image.unlockFocus()
        return image
    }
}
