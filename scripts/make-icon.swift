// Renders the AutoClicker app icon into an .iconset directory.
// Usage: swift scripts/make-icon.swift build/AppIcon.iconset
import AppKit

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write("usage: make-icon.swift <output.iconset>\n".data(using: .utf8)!)
    exit(1)
}
let outDir = URL(fileURLWithPath: args[1])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func render(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let s = size
    let inset = s * 0.06
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = NSBezierPath(roundedRect: rect, xRadius: s * 0.22, yRadius: s * 0.22)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.05, green: 0.70, blue: 0.68, alpha: 1),
        NSColor(calibratedRed: 0.02, green: 0.42, blue: 0.52, alpha: 1),
    ])!
    gradient.draw(in: path, angle: -70)

    // Click "waves" above the arrow tip.
    NSColor.white.withAlphaComponent(0.9).setStroke()
    for (i, radius) in [0.16, 0.24, 0.32].enumerated() {
        let r = s * CGFloat(radius)
        let center = NSPoint(x: s * 0.40, y: s * 0.62)
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: r, startAngle: 20, endAngle: 160)
        arc.lineWidth = s * (0.045 - CGFloat(i) * 0.008)
        arc.lineCapStyle = .round
        arc.stroke()
    }

    // Cursor arrow.
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
    NSColor.white.setFill()
    arrow.fill()
    NSColor(calibratedWhite: 0.1, alpha: 0.35).setStroke()
    arrow.lineWidth = s * 0.02
    arrow.stroke()
    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, pixels: Int, name: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: outDir.appendingPathComponent(name))
}

for base in [16, 32, 128, 256, 512] {
    let img = render(size: CGFloat(base * 2))
    writePNG(img, pixels: base, name: "icon_\(base)x\(base).png")
    writePNG(img, pixels: base * 2, name: "icon_\(base)x\(base)@2x.png")
}
print("Wrote iconset to \(outDir.path)")
