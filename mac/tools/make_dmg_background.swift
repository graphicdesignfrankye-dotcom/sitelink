// Sfondo della finestra del DMG (660x400 pt): arco tra le due icone, frecce, istruzione.
// Uso: swift tools/make_dmg_background.swift <cartella-output>   -> background.png e background@2x.png
import AppKit

let W: CGFloat = 660, H: CGFloat = 400

func render(scale: CGFloat) -> Data {
    let px = Int(W * scale), py = Int(H * scale)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: py, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)   // punti: il @2x resta 660x400 pt
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    func y(_ v: CGFloat) -> CGFloat { H - v }   // coordinate dall'alto

    NSColor(srgbRed: 0xEC/255, green: 0xFD/255, blue: 0xF5/255, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: W, height: H).fill()

    // Arco tra le due icone (stesso motivo dell'icona dell'app)
    let mint = NSColor(srgbRed: 0xA7/255, green: 0xF3/255, blue: 0xD0/255, alpha: 1)
    let arc = NSBezierPath()
    arc.move(to: NSPoint(x: 170, y: y(100)))
    arc.curve(to: NSPoint(x: 490, y: y(100)),
              controlPoint1: NSPoint(x: 170 + 320 * 0.2, y: y(100 - 80 * 4 / 3 * 0.75 * 2 / 2)),
              controlPoint2: NSPoint(x: 490 - 320 * 0.2, y: y(100 - 80 * 4 / 3 * 0.75 * 2 / 2)))
    arc.lineWidth = 9; arc.lineCapStyle = .round
    mint.setStroke(); arc.stroke()
    NSColor(srgbRed: 0x05/255, green: 0x96/255, blue: 0x69/255, alpha: 1).setFill()
    for x: CGFloat in [170, 490] { NSBezierPath(ovalIn: NSRect(x: x - 9, y: y(100) - 9, width: 18, height: 18)).fill() }

    // Tre chevron tra le icone
    let green = NSColor(srgbRed: 0x05/255, green: 0x96/255, blue: 0x69/255, alpha: 1)
    for (i, alpha) in [0.25, 0.55, 1.0].enumerated() {
        let cx = 306 + CGFloat(i) * 24
        let p = NSBezierPath()
        p.move(to: NSPoint(x: cx, y: y(186))); p.line(to: NSPoint(x: cx + 14, y: y(200))); p.line(to: NSPoint(x: cx, y: y(214)))
        p.lineWidth = 7; p.lineCapStyle = .round; p.lineJoinStyle = .round
        green.withAlphaComponent(CGFloat(alpha)).setStroke(); p.stroke()
    }

    // Istruzione
    let text = "Trascina SiteLink nella cartella Applicazioni" as NSString
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 15, weight: .medium),
        .foregroundColor: NSColor(srgbRed: 0x04/255, green: 0x78/255, blue: 0x57/255, alpha: 1)]
    let sz = text.size(withAttributes: attrs)
    text.draw(at: NSPoint(x: (W - sz.width) / 2, y: y(352)), withAttributes: attrs)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
try render(scale: 1).write(to: URL(fileURLWithPath: dir + "/background.png"))
try render(scale: 2).write(to: URL(fileURLWithPath: dir + "/background@2x.png"))
