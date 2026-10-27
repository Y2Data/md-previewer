import AppKit

let destination = URL(fileURLWithPath: "ClearMark/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
var images: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let tile = NSBezierPath(roundedRect: NSRect(x: 76, y: 76, width: 872, height: 872), xRadius: 196, yRadius: 196)
        NSGradient(starting: NSColor(srgbRed: 0.27, green: 0.51, blue: 0.40, alpha: 1), ending: NSColor(srgbRed: 0.13, green: 0.32, blue: 0.25, alpha: 1))!.draw(in: tile, angle: -90)
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.2); shadow.shadowBlurRadius = 20; shadow.shadowOffset = NSSize(width: 0, height: -12)
        NSGraphicsContext.saveGraphicsState(); shadow.set()
        let paper = NSBezierPath(roundedRect: NSRect(x: 253, y: 210, width: 518, height: 625), xRadius: 38, yRadius: 38)
        NSColor(srgbRed: 0.96, green: 0.96, blue: 0.90, alpha: 1).setFill(); paper.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor(srgbRed: 0.18, green: 0.40, blue: 0.30, alpha: 1).setStroke()
        let mark = NSBezierPath(); mark.lineWidth = 34; mark.lineCapStyle = .round; mark.lineJoinStyle = .round
        mark.move(to: NSPoint(x: 330, y: 575)); mark.line(to: NSPoint(x: 330, y: 691)); mark.line(to: NSPoint(x: 405, y: 617)); mark.line(to: NSPoint(x: 480, y: 691)); mark.line(to: NSPoint(x: 480, y: 575)); mark.stroke()
        let arrow = NSBezierPath(); arrow.lineWidth = 30; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
        arrow.move(to: NSPoint(x: 628, y: 699)); arrow.line(to: NSPoint(x: 628, y: 575)); arrow.move(to: NSPoint(x: 583, y: 620)); arrow.line(to: NSPoint(x: 628, y: 575)); arrow.line(to: NSPoint(x: 673, y: 620)); arrow.stroke()
        NSColor(srgbRed: 0.69, green: 0.76, blue: 0.65, alpha: 1).setFill()
        for (y, width) in [(470, 366), (404, 366), (338, 240)] { NSBezierPath(roundedRect: NSRect(x: 329, y: y, width: width, height: 16), xRadius: 8, yRadius: 8).fill() }
        image.unlockFocus()
        let png = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        let filename = "icon-\(size)@\(scale)x.png"
        try png.write(to: destination.appendingPathComponent(filename))
        images.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": filename])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: destination.appendingPathComponent("Contents.json"))
try Data("{\"info\":{\"author\":\"xcode\",\"version\":1}}\n".utf8).write(to: destination.deletingLastPathComponent().appendingPathComponent("Contents.json"))
print("Generated ClearMark app icons.")
