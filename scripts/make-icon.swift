// Renders the 👀 emoji into Resources/AppIcon.icns.
// Run from the repo root: swift scripts/make-icon.swift
import AppKit

let emoji = "👀"
let fill: CGFloat = 0.9   // share of the icon the emoji's widest side covers

// 1. Draw the emoji once, large, with room to spare.
let master = 2048
let big = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: master, pixelsHigh: master,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: big)
NSAttributedString(string: emoji, attributes: [.font: NSFont(name: "Apple Color Emoji", size: 1024)!])
    .draw(at: NSPoint(x: 256, y: 256))
NSGraphicsContext.restoreGraphicsState()

// 2. Find the painted pixels. The font's own glyph metrics include empty
//    space, which left the eyes off-centre, so measure the pixels instead.
var (minX, minY, maxX, maxY) = (master, master, 0, 0)
for y in 0..<master {
    for x in 0..<master where big.colorAt(x: x, y: y)!.alphaComponent > 0.02 {
        minX = min(minX, x); maxX = max(maxX, x)
        minY = min(minY, y); maxY = max(maxY, y)
    }
}
// colorAt's y runs top-down; NSImage drawing runs bottom-up.
let painted = NSRect(x: minX, y: master - 1 - maxY, width: maxX - minX + 1, height: maxY - minY + 1)
let source = NSImage(size: NSSize(width: master, height: master))
source.addRepresentation(big)

// 3. Scale that box into each icon size, centred.
func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let canvas = CGFloat(pixels)
    let scale = canvas * fill / max(painted.width, painted.height)
    let size = NSSize(width: painted.width * scale, height: painted.height * scale)
    source.draw(in: NSRect(x: (canvas - size.width) / 2, y: (canvas - size.height) / 2,
                           width: size.width, height: size.height),
                from: painted, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(filePath: NSTemporaryDirectory()).appending(path: "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: iconset.appending(path: "icon_\(size)x\(size).png"))
    try render(size * 2).write(to: iconset.appending(path: "icon_\(size)x\(size)@2x.png"))
}

let task = Process()
task.executableURL = URL(filePath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
