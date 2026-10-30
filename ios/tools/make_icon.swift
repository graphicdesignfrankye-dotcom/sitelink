// Genera l'icona 1024x1024 dell'app iPhone (stesso disegno del Mac, quadrato pieno).
// Uso: swift tools/make_icon.swift SiteLink/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import AppKit

func render(px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let t = CGFloat(px), o = (CGFloat(px) - t) / 2, k = t / 160
    let xf = NSAffineTransform()
    xf.translateX(by: o, yBy: CGFloat(px) - o)
    xf.scaleX(by: k, yBy: -k)
    xf.concat()

    NSColor(srgbRed: 0x05/255, green: 0x96/255, blue: 0x69/255, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 160, height: 160), xRadius: 0, yRadius: 0).fill()

    NSColor.white.setFill()
    for dx: CGFloat in [0, 70] {
        let roof = NSBezierPath()
        roof.move(to: NSPoint(x: 20 + dx, y: 88)); roof.line(to: NSPoint(x: 45 + dx, y: 66))
        roof.line(to: NSPoint(x: 70 + dx, y: 88)); roof.close(); roof.fill()
        NSBezierPath(rect: NSRect(x: 26 + dx, y: 88, width: 38, height: 28)).fill()
    }
    let arc = NSBezierPath()
    arc.move(to: NSPoint(x: 45, y: 60))
    arc.curve(to: NSPoint(x: 115, y: 60), controlPoint1: NSPoint(x: 68.33, y: 33.33), controlPoint2: NSPoint(x: 91.67, y: 33.33))
    arc.lineWidth = 8; arc.lineCapStyle = .round
    NSColor(srgbRed: 0x06/255, green: 0x4E/255, blue: 0x3B/255, alpha: 1).setStroke()
    arc.stroke()
    NSColor.white.setFill()
    for x: CGFloat in [45, 115] {
        NSBezierPath(ovalIn: NSRect(x: x - 7, y: 53, width: 14, height: 14)).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
try render(px: 1024).write(to: URL(fileURLWithPath: out))
