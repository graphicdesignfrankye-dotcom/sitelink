// Genera AppIcon.icns: due case unite da un arco su sfondo verde.
// Uso: swift tools/make_icon.swift   (poi iconutil, vedi make-icon.sh)
import AppKit

func render(px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let t = CGFloat(px) * 824 / 1024, o = (CGFloat(px) - t) / 2, k = t / 160
    let xf = NSAffineTransform()
    xf.translateX(by: o, yBy: CGFloat(px) - o)
    xf.scaleX(by: k, yBy: -k)
    xf.concat()

    NSColor(srgbRed: 0x05/255, green: 0x96/255, blue: 0x69/255, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 160, height: 160), xRadius: 36, yRadius: 36).fill()

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

let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
let sizes: [(String, Int)] = [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
    ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512),
    ("512x512", 512), ("512x512@2x", 1024)]
for (name, px) in sizes { try render(px: px).write(to: URL(fileURLWithPath: "\(dir)/icon_\(name).png")) }
