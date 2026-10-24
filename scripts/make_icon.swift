// Draws the Dictate app icon (1024x1024 PNG) with AppKit: blue-to-teal rounded square, white microphone, sound arcs.
//   swiftc -O scripts/make_icon.swift -o /tmp/make_icon && /tmp/make_icon out.png
import AppKit

let out = CommandLine.arguments.dropFirst().first ?? "icon_1024.png"
let S: CGFloat = 1024

let img = NSImage(size: NSSize(width: S, height: S), flipped: false) { rect in
    // macOS icon grid: the artwork sits inside an 824 px rounded square with a soft shadow.
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.shadowBlurRadius = 28
    shadow.set()
    NSColor(calibratedRed: 0.10, green: 0.25, blue: 0.55, alpha: 1).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(colors: [NSColor(calibratedRed: 0.13, green: 0.30, blue: 0.78, alpha: 1),
                        NSColor(calibratedRed: 0.05, green: 0.62, blue: 0.70, alpha: 1)])!.draw(in: body, angle: -55)
    // soft top highlight
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.20), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: 100, y: 520, width: 824, height: 404), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    let cx = S / 2
    NSColor.white.setFill(); NSColor.white.setStroke()

    // microphone capsule
    let capsule = NSBezierPath(roundedRect: NSRect(x: cx - 88, y: 430, width: 176, height: 290), xRadius: 88, yRadius: 88)
    capsule.fill()
    // cradle arc under the capsule
    let cradle = NSBezierPath()
    cradle.lineWidth = 38; cradle.lineCapStyle = .round
    cradle.appendArc(withCenter: NSPoint(x: cx, y: 520), radius: 150, startAngle: 180, endAngle: 360, clockwise: false)
    cradle.stroke()
    // stem and base
    let stem = NSBezierPath(); stem.lineWidth = 38; stem.lineCapStyle = .round
    stem.move(to: NSPoint(x: cx, y: 370)); stem.line(to: NSPoint(x: cx, y: 300)); stem.stroke()
    let base = NSBezierPath(); base.lineWidth = 38; base.lineCapStyle = .round
    base.move(to: NSPoint(x: cx - 80, y: 300)); base.line(to: NSPoint(x: cx + 80, y: 300)); base.stroke()

    // sound arcs left and right of the capsule
    for (r, a) in [(CGFloat(190), 0.95), (CGFloat(250), 0.75)] as [(CGFloat, Double)] {
        NSColor.white.withAlphaComponent(a).setStroke()
        for side in [-1.0, 1.0] {
            let arc = NSBezierPath(); arc.lineWidth = 26; arc.lineCapStyle = .round
            let start: CGFloat = side < 0 ? 150 : -30, end: CGFloat = side < 0 ? 210 : 30
            arc.appendArc(withCenter: NSPoint(x: cx, y: 575), radius: r + 60, startAngle: start, endAngle: end, clockwise: false)
            arc.stroke()
        }
    }
    return true
}

guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { print("render failed"); exit(1) }
try png.write(to: URL(fileURLWithPath: out))
print("wrote \(out) \(rep.pixelsWide)x\(rep.pixelsHigh)")
