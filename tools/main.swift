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
func drawMagnified(awake: Bool, color: NSColor, at point: NSPoint, box: CGFloat) {
    let small = statusImage(awake: awake, size: 18, color: color)
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

if mode == "iconset" {
    try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
    for (size, scale) in [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)] {
        let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
        writePNG(appIcon(size: CGFloat(size * scale)), to: out + "/" + name)
    }
} else {
    let states: [(String, Bool)] = [("awake — the Mac stays awake", true), ("asleep — the Mac may sleep", false)]
    let cell: CGFloat = 200
    let w = cell * 2, h: CGFloat = 300
    let sheet = NSImage(size: NSSize(width: w, height: h))
    sheet.lockFocus()
    NSColor.white.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
    NSColor(white: 0.13, alpha: 1).setFill(); NSRect(x: 0, y: 150, width: w, height: 150).fill()
    for (i, state) in states.enumerated() {
        let x = CGFloat(i) * cell + 40
        drawMagnified(awake: state.1, color: .white, at: NSPoint(x: x, y: 232), box: 56)
        statusImage(awake: state.1, size: 56, color: .white)
            .draw(at: NSPoint(x: x, y: 166), from: .zero, operation: .sourceOver, fraction: 1)
        drawMagnified(awake: state.1, color: .black, at: NSPoint(x: x, y: 82), box: 56)
        statusImage(awake: state.1, size: 56, color: .black)
            .draw(at: NSPoint(x: x, y: 20), from: .zero, operation: .sourceOver, fraction: 1)
        (state.0 as NSString).draw(at: NSPoint(x: CGFloat(i) * cell + 10, y: 2),
            withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.black])
    }
    sheet.unlockFocus()
    writePNG(sheet, to: out)
}
print("written \(out)")
