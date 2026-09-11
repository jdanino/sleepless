import Cocoa

// The icon is a face that fills the frame.
//   Awake  = wide eyes with a pupil. It stares, because the Mac does not sleep.
//   Asleep = two closed-eye curves.
// The drawing makes both the menu-bar template image and the Finder icon.

private let eyeLeft = CGPoint(x: 33, y: 57)
private let eyeRight = CGPoint(x: 67, y: 57)

/// Strokes a shallow curve for a closed eye.
private func closedEye(at point: CGPoint, in ctx: CGContext) {
    ctx.setLineWidth(7)
    ctx.setLineCap(.round)
    ctx.addArc(center: CGPoint(x: point.x, y: point.y + 9), radius: 15,
               startAngle: .pi * 1.18, endAngle: .pi * 1.82, clockwise: false)
    ctx.strokePath()
}

/// Draws the face in a 100 x 100 space.
private func drawFace(stayAwake: Bool, in ctx: CGContext, color: NSColor) {
    ctx.saveGState()
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.setFillColor(color.cgColor)
    ctx.setStrokeColor(color.cgColor)

    // The head fills the frame.
    ctx.fillEllipse(in: CGRect(x: 4, y: 4, width: 92, height: 92))

    // Cut the eyes and the mouth out.
    ctx.setBlendMode(.destinationOut)
    if stayAwake {
        for eye in [eyeLeft, eyeRight] {
            ctx.fillEllipse(in: CGRect(x: eye.x - 16, y: eye.y - 16, width: 32, height: 32))
        }
        ctx.addPath(CGPath(roundedRect: CGRect(x: 37, y: 19, width: 26, height: 9),
                           cornerWidth: 4.5, cornerHeight: 4.5, transform: nil))
    } else {
        for eye in [eyeLeft, eyeRight] { closedEye(at: eye, in: ctx) }
        ctx.addPath(CGPath(roundedRect: CGRect(x: 37, y: 21, width: 26, height: 7),
                           cornerWidth: 3.5, cornerHeight: 3.5, transform: nil))
    }
    ctx.fillPath()

    // Put the pupils back in the open eyes.
    if stayAwake {
        ctx.setBlendMode(.normal)
        for eye in [eyeLeft, eyeRight] {
            ctx.fillEllipse(in: CGRect(x: eye.x - 6.5, y: eye.y - 6.5, width: 13, height: 13))
        }
    }

    ctx.setBlendMode(.normal)
    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

/// A template image for the menu bar. macOS gives it the correct colour.
func statusImage(stayAwake: Bool, size: CGFloat = 18, color: NSColor = .black) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
        guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
        ctx.scaleBy(x: size / 100, y: size / 100)
        drawFace(stayAwake: stayAwake, in: ctx, color: color)
        return true
    }
    image.isTemplate = true
    return image
}

/// A full-colour icon for the Finder: a light face on a dark night tile.
func appIcon(size: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
        guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
        ctx.scaleBy(x: size / 100, y: size / 100)
        ctx.addPath(CGPath(roundedRect: CGRect(x: 5, y: 5, width: 90, height: 90),
                           cornerWidth: 21, cornerHeight: 21, transform: nil))
        ctx.setFillColor(NSColor(red: 0.16, green: 0.18, blue: 0.36, alpha: 1).cgColor)
        ctx.fillPath()
        ctx.translateBy(x: 50, y: 50); ctx.scaleBy(x: 0.72, y: 0.72); ctx.translateBy(x: -50, y: -50)
        drawFace(stayAwake: true, in: ctx, color: NSColor(white: 0.97, alpha: 1))
        return true
    }
}
