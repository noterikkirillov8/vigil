import AppKit

/// The menu bar mark: a small square body with a crescent inside. Idle it is an outline with the crescent
/// drawn; during a session the body is filled and the crescent is cut out of it. Template image, crisp at 1x and 2x.
enum StatusImage {
    static func make(_ mark: StatusMark) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 16), flipped: false) { rect in
            let body = NSRect(x: 2, y: 1.5, width: 14, height: 13)
            let moon = NSBezierPath(ovalIn: NSRect(x: 4.6, y: 3.9, width: 8.4, height: 8.4))
            moon.append(NSBezierPath(ovalIn: NSRect(x: 7.6, y: 5.2, width: 7, height: 7)))
            moon.windingRule = .evenOdd
            NSColor.black.setFill(); NSColor.black.setStroke()
            let square = NSBezierPath(roundedRect: body, xRadius: 3.5, yRadius: 3.5)
            if mark != .idle {
                square.append(moon)
                square.windingRule = .evenOdd
                NSGraphicsContext.saveGraphicsState()
                if mark == .lidWarning {
                    let clip = NSBezierPath(rect: rect)
                    clip.appendOval(in: NSRect(x: 10.5, y: -1, width: 8, height: 8))
                    clip.windingRule = .evenOdd
                    clip.addClip()
                }
                square.fill()
                NSGraphicsContext.restoreGraphicsState()
                if mark == .lidWarning {
                    let ring = NSBezierPath(ovalIn: NSRect(x: 12.5, y: 1, width: 4, height: 4))
                    ring.lineWidth = 1.25
                    ring.stroke()
                }
            } else {
                square.lineWidth = 1.4
                square.stroke()
                moon.fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    static func title(_ text: String) -> NSAttributedString {
        NSAttributedString(string: " " + text, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)])
    }
}
