import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 512, y: CGFloat(pixels) / 512)
        NSColor(calibratedRed: 0.15, green: 0.20, blue: 0.27, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 24, y: 24, width: 464, height: 464), xRadius: 110, yRadius: 110).fill()
        NSColor(calibratedWhite: 0.98, alpha: 1).setStroke()
        let ring = NSBezierPath(ovalIn: NSRect(x: 116, y: 100, width: 280, height: 280))
        ring.lineWidth = 22; ring.stroke()
        let hands = NSBezierPath()
        hands.lineCapStyle = .round; hands.lineJoinStyle = .round; hands.lineWidth = 21
        hands.move(to: NSPoint(x: 256, y: 333)); hands.line(to: NSPoint(x: 256, y: 240)); hands.line(to: NSPoint(x: 310, y: 208)); hands.stroke()
        let crown = NSBezierPath(); crown.lineCapStyle = .round; crown.lineWidth = 20
        crown.move(to: NSPoint(x: 231, y: 418)); crown.line(to: NSPoint(x: 281, y: 418)); crown.stroke()
        NSColor(calibratedRed: 0.46, green: 0.83, blue: 0.68, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 365, y: 338, width: 58, height: 58)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}

// ICNS embeds PNG representations directly; this avoids invoking an image
// conversion service and keeps packaging usable with only Command Line Tools.
func bigEndian(_ value: Int) -> Data {
    var number = UInt32(value).bigEndian
    return withUnsafeBytes(of: &number) { Data($0) }
}
let representations = [
    ("icp4", "icon_16x16.png"), ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"), ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"), ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png")
]
var body = Data()
for (type, filename) in representations {
    let png = try Data(contentsOf: directory.appendingPathComponent(filename))
    body.append(Data(type.utf8)); body.append(bigEndian(png.count + 8)); body.append(png)
}
var icon = Data("icns".utf8)
icon.append(bigEndian(body.count + 8)); icon.append(body)
try icon.write(to: directory.deletingPathExtension().appendingPathExtension("icns"))
