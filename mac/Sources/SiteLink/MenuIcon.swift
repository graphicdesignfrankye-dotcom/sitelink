import AppKit

/// Icona della barra dei menu: due case unite da un arco, monocromatica (template).
/// Connesso: arco pieno. Parziale: arco attenuato. Disconnesso: arco a puntini. Sconosciuto: solo case.
enum MenuIcon {
    static func image(for state: LinkState) -> NSImage {
        let size = NSSize(width: 22, height: 18)
        let img = NSImage(size: size, flipped: true) { _ in
            let s: CGFloat = 0.169
            let xf = NSAffineTransform()
            xf.translateX(by: (size.width - 130 * s) / 2 - 15 * s, yBy: (size.height - 105 * s) / 2 - 30 * s)
            xf.scaleX(by: s, yBy: s)
            xf.concat()

            NSColor.black.setFill()
            for dx: CGFloat in [0, 70] {
                let roof = NSBezierPath()
                roof.move(to: NSPoint(x: 20 + dx, y: 88)); roof.line(to: NSPoint(x: 45 + dx, y: 66))
                roof.line(to: NSPoint(x: 70 + dx, y: 88)); roof.close(); roof.fill()
                NSBezierPath(rect: NSRect(x: 26 + dx, y: 88, width: 38, height: 28)).fill()
            }
            guard state != .unknown else { return true }

            let arc = NSBezierPath()
            arc.move(to: NSPoint(x: 45, y: 60))
            arc.curve(to: NSPoint(x: 115, y: 60), controlPoint1: NSPoint(x: 68.33, y: 33.33), controlPoint2: NSPoint(x: 91.67, y: 33.33))
            arc.lineWidth = 9
            arc.lineCapStyle = .round
            if state == .off { arc.setLineDash([0.5, 17], count: 2, phase: 0) }
            NSColor.black.withAlphaComponent(state == .partial ? 0.5 : 1).setStroke()
            arc.stroke()
            if state != .off {
                for x: CGFloat in [45, 115] {
                    NSColor.black.withAlphaComponent(state == .partial ? 0.5 : 1).setFill()
                    NSBezierPath(ovalIn: NSRect(x: x - 7, y: 53, width: 14, height: 14)).fill()
                }
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}
