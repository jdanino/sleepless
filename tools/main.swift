import Cocoa

// Usage:
//   icontool sheet   <out.png>     — a preview of both states, true size and large
//   icontool iconset <out.iconset> — the PNG set for iconutil

func writePNG(_ image: NSImage, to path: String) {
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

/// Draws the true 18 pt image at 2x, then makes it big with hard pixels.
/// Thus you see exactly what the menu bar shows.
func drawMagnified(stayAwake: Bool, color: NSColor, at point: NSPoint, box: CGFloat) {
    let small = statusImage(stayAwake: stayAwake, size: 18, color: color)
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 36, pixelsHigh: 36,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    small.draw(in: NSRect(x: 0, y: 0, width: 36, height: 36))
    NSGraphicsContext.restoreGraphicsState()
    bitmap.draw(in: NSRect(x: point.x, y: point.y, width: box, height: box),
                from: .zero, operation: .sourceOver, fraction: 1,
                respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none.rawValue])
}

let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "sheet"
let out = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "icons.png"

if mode == "docs" {
    // A picture for the README: the two states, drawn with the same code the
    // app uses. It is a rendering, not a photograph of a screen.
    let W: CGFloat = 1200, H: CGFloat = 420
    let sheet = NSImage(size: NSSize(width: W, height: H))
    sheet.lockFocus()
    NSColor.white.setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()

    let panels: [(bg: NSColor, fg: NSColor, stayAwake: Bool, title: String, line: String)] = [
        (NSColor(white: 0.11, alpha: 1), .white, true,
         "Stay Awake", "Your Mac will stay awake when closed"),
        (NSColor(white: 0.96, alpha: 1), NSColor(white: 0.08, alpha: 1), false,
         "Normal", "Your Mac will go to sleep when closed"),
    ]

    for (i, p) in panels.enumerated() {
        let x = 30 + CGFloat(i) * (W / 2 - 15)
        let rect = NSRect(x: x, y: 30, width: W / 2 - 45, height: H - 60)
        let path = NSBezierPath(roundedRect: rect, xRadius: 22, yRadius: 22)
        p.bg.setFill(); path.fill()

        // A strip that suggests the menu bar, with the icon at its true size.
        let barY = rect.maxY - 86
        statusImage(stayAwake: p.stayAwake, size: 22, color: p.fg)
            .draw(at: NSPoint(x: rect.minX + 44, y: barY), from: .zero,
                  operation: .sourceOver, fraction: 1)

        // The same icon, large, so the two states are easy to compare.
        statusImage(stayAwake: p.stayAwake, size: 150, color: p.fg)
            .draw(at: NSPoint(x: rect.midX - 75, y: rect.minY + 110), from: .zero,
                  operation: .sourceOver, fraction: 1)

        (p.title as NSString).draw(
            at: NSPoint(x: rect.minX + 82, y: barY - 1),
            withAttributes: [.font: NSFont.systemFont(ofSize: 19, weight: .semibold),
                             .foregroundColor: p.fg])
        let line = NSMutableParagraphStyle(); line.alignment = .center
        (p.line as NSString).draw(
            in: NSRect(x: rect.minX + 20, y: rect.minY + 52, width: rect.width - 40, height: 30),
            withAttributes: [.font: NSFont.systemFont(ofSize: 20),
                             .foregroundColor: p.fg.withAlphaComponent(0.75),
                             .paragraphStyle: line])
    }
    sheet.unlockFocus()
    writePNG(sheet, to: out)
    print("written \(out)")
    exit(0)
}

if mode == "iconset" {
    try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
    for (size, scale) in [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)] {
        let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
        writePNG(appIcon(size: CGFloat(size * scale)), to: out + "/" + name)
    }
} else {
    let states: [(String, Bool)] = [("stayAwake — the Mac stays stayAwake", true), ("asleep — the Mac may sleep", false)]
    let cell: CGFloat = 200
    let w = cell * 2, h: CGFloat = 300
    let sheet = NSImage(size: NSSize(width: w, height: h))
    sheet.lockFocus()
    NSColor.white.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
    NSColor(white: 0.13, alpha: 1).setFill(); NSRect(x: 0, y: 150, width: w, height: 150).fill()
    for (i, state) in states.enumerated() {
        let x = CGFloat(i) * cell + 40
        drawMagnified(stayAwake: state.1, color: .white, at: NSPoint(x: x, y: 232), box: 56)
        statusImage(stayAwake: state.1, size: 56, color: .white)
            .draw(at: NSPoint(x: x, y: 166), from: .zero, operation: .sourceOver, fraction: 1)
        drawMagnified(stayAwake: state.1, color: .black, at: NSPoint(x: x, y: 82), box: 56)
        statusImage(stayAwake: state.1, size: 56, color: .black)
            .draw(at: NSPoint(x: x, y: 20), from: .zero, operation: .sourceOver, fraction: 1)
        (state.0 as NSString).draw(at: NSPoint(x: CGFloat(i) * cell + 10, y: 2),
            withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.black])
    }
    sheet.unlockFocus()
    writePNG(sheet, to: out)
}
print("written \(out)")
