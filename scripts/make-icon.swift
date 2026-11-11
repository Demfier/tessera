// Renders Resources/AppIcon.icns: a squircle holding a snapped three-tile layout.
// Usage: swift scripts/make-icon.swift <output.icns>
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.icns")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(getpid()).iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(pixels) / 1024 // design on a 1024 grid

    // Apple's icon grid: 824pt body centred in 1024 with a soft drop shadow.
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 24 * s
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSGradient(starting: NSColor(srgbRed: 0.16, green: 0.20, blue: 0.42, alpha: 1),
               ending: NSColor(srgbRed: 0.06, green: 0.08, blue: 0.20, alpha: 1))!.draw(in: squircle, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // A left-half tile and two stacked right tiles — a Tessera layout.
    let inset = body.insetBy(dx: 150 * s, dy: 150 * s)
    let gap = 34 * s
    let halfWidth = (inset.width - gap) / 2
    let halfHeight = (inset.height - gap) / 2
    let tiles: [(NSRect, NSColor)] = [
        (NSRect(x: inset.minX, y: inset.minY, width: halfWidth, height: inset.height),
         NSColor(srgbRed: 0.98, green: 0.73, blue: 0.33, alpha: 1)),
        (NSRect(x: inset.minX + halfWidth + gap, y: inset.minY + halfHeight + gap, width: halfWidth, height: halfHeight),
         NSColor(srgbRed: 0.36, green: 0.83, blue: 0.80, alpha: 1)),
        (NSRect(x: inset.minX + halfWidth + gap, y: inset.minY, width: halfWidth, height: halfHeight),
         NSColor(srgbRed: 0.93, green: 0.42, blue: 0.47, alpha: 1)),
    ]
    for (rect, color) in tiles {
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 46 * s, yRadius: 46 * s).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try render(pixels: points * scale).write(to: iconset.appendingPathComponent(name))
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
exit(iconutil.terminationStatus)
