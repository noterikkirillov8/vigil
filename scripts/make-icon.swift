#!/usr/bin/env swift
// Draws Vigil's app icon (graphite body, lit violet crescent, dark night strip) into Vigil/Resources/Assets.xcassets/AppIcon.appiconset.
// Run: swift scripts/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let set = root.appendingPathComponent("Vigil/Resources/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
try #"{"info":{"author":"xcode","version":1}}"#.write(to: set.deletingLastPathComponent().appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let k = CGFloat(px) / 1024
    func hex(_ v: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
    // Hardware style: a graphite body, one wide-type glyph, one lit element in the accent (the load strip).
    let tile = NSRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
    hex(0x1B1C1F).setFill()
    NSBezierPath(roundedRect: tile, xRadius: 185 * k, yRadius: 185 * k).fill()
    hex(0x2C2D31).setStroke()
    let edge = NSBezierPath(roundedRect: tile.insetBy(dx: 3 * k, dy: 3 * k), xRadius: 182 * k, yRadius: 182 * k)
    edge.lineWidth = 6 * k; edge.stroke()
    // one lit element: the violet crescent; under it the night strip, all dark
    hex(0x9D8CFF).setFill()
    NSBezierPath(ovalIn: NSRect(x: 330 * k, y: 400 * k, width: 364 * k, height: 364 * k)).fill()
    hex(0x1B1C1F).setFill()   // the body colour cuts the crescent
    NSBezierPath(ovalIn: NSRect(x: 420 * k, y: 450 * k, width: 330 * k, height: 330 * k)).fill()
    let segW = 41 * k, gap = 12 * k, left = (1024 * k - (12 * segW + 11 * gap)) / 2
    for i in 0..<12 {
        let r = NSRect(x: left + CGFloat(i) * (segW + gap), y: 262 * k, width: segW, height: 78 * k)
        hex(0x2C2D31).setFill()
        NSBezierPath(roundedRect: r, xRadius: 8 * k, yRadius: 8 * k).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [String] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try render(size * scale).write(to: set.appendingPathComponent(name))
        images.append(#"{"filename":"\#(name)","idiom":"mac","scale":"\#(scale)x","size":"\#(size)x\#(size)"}"#)
    }
}
try #"{"images":[\#(images.joined(separator: ","))],"info":{"author":"xcode","version":1}}"#
    .write(to: set.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
