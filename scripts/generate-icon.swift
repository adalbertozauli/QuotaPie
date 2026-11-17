import AppKit
import Foundation

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
var icons: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let bounds = NSRect(x: 0, y: 0, width: pixels, height: pixels)
        let p = CGFloat(pixels)
        NSColor(calibratedRed: 0.055, green: 0.13, blue: 0.18, alpha: 1).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: p * 0.055, dy: p * 0.055), xRadius: p * 0.22, yRadius: p * 0.22).fill()
        let center = NSPoint(x: p / 2, y: p / 2)
        let background = NSBezierPath(ovalIn: bounds.insetBy(dx: p * 0.245, dy: p * 0.245))
        background.lineWidth = p * 0.095
        NSColor.white.withAlphaComponent(0.16).setStroke()
        background.stroke()
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: p * 0.255, startAngle: 90, endAngle: 355, clockwise: false)
        arc.lineWidth = p * 0.095
        arc.lineCapStyle = .round
        NSColor(calibratedRed: 0.21, green: 0.88, blue: 0.72, alpha: 1).setStroke()
        arc.stroke()
        let dot = NSBezierPath(ovalIn: NSRect(x: p * 0.445, y: p * 0.445, width: p * 0.11, height: p * 0.11))
        NSColor.white.setFill()
        dot.fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Icon rendering failed") }
        let filename = "icon_\(size)@\(scale)x.png"
        try png.write(to: directory.appendingPathComponent(filename))
        icons.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": filename])
    }
}
let manifest: [String: Any] = ["images": icons, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("Contents.json"))
