// Builds AppIcon.icns from Resources/AppIcon.png, a 1024px master with transparent
// corners drawn on the macOS icon grid (824px plate inset 100px). The master is cropped
// and re-masked from Resources/AppIcon-simple-source.png (the simplified illustration in use);
// Resources/AppIcon-source.png is the original, more detailed illustration.
// Usage: swift Scripts/MakeIcon.swift <output>.iconset  (writes <output>.icns beside it)
import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let masterURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("Resources/AppIcon.png")
guard let master = NSImage(contentsOf: masterURL)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
      master.width == 1024, master.height == 1024 else {
    fatalError("Resources/AppIcon.png must be a 1024x1024 PNG")
}
try? FileManager.default.removeItem(at: directory)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

func png(_ pixels: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let context = NSGraphicsContext.current!.cgContext
    context.interpolationQuality = .high
    context.draw(master, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let data = pixels == 1024 ? try Data(contentsOf: masterURL) : png(pixels)
        try data.write(to: directory.appendingPathComponent("icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"))
    }
}

// iconutil ships with macOS (not Xcode) and writes each size in the format Finder expects.
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", directory.path, "-o", directory.deletingPathExtension().appendingPathExtension("icns").path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }

// macOS 26 draws icns-only apps inside a grey plate at small sizes. Resources/AppIcon.icon
// (Icon Composer format, art = the illustration's plate area unmasked) compiles to Assets.car,
// which the system masks itself. actool ships with Xcode; without it the app falls back to the icns.
// Writes <output>.assets/Assets.car beside the iconset.
let assets = directory.deletingPathExtension().appendingPathExtension("assets")
try? FileManager.default.removeItem(at: assets)
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
let actool = Process()
actool.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
actool.arguments = ["actool", masterURL.deletingLastPathComponent().appendingPathComponent("AppIcon.icon").path,
    "--compile", assets.path, "--platform", "macosx", "--minimum-deployment-target", "14.0",
    "--app-icon", "AppIcon", "--output-partial-info-plist", assets.appendingPathComponent("partial.plist").path]
actool.standardOutput = FileHandle.nullDevice
if (try? actool.run()) != nil { actool.waitUntilExit() }
if actool.terminationStatus != 0 || !FileManager.default.fileExists(atPath: assets.appendingPathComponent("Assets.car").path) {
    FileHandle.standardError.write("warning: actool unavailable or failed; app will use AppIcon.icns only\n".data(using: .utf8)!)
}
