// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
let root = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(size)/1024, y: CGFloat(size)/1024)
    let background = NSBezierPath(roundedRect: NSRect(x: 24, y: 24, width: 976, height: 976), xRadius: 198, yRadius: 198)
    NSGradient(colors: [NSColor(calibratedRed: 0.08, green: 0.18, blue: 0.23, alpha: 1), NSColor(calibratedRed: 0.025, green: 0.08, blue: 0.10, alpha: 1)])!.draw(in: background, angle: -55)
    let disc = NSBezierPath(ovalIn: NSRect(x: 150,y: 150,width: 724,height: 724))
    NSGradient(colors: [.init(white: 0.97, alpha: 1), .init(calibratedRed: 0.48, green: 0.77, blue: 0.80, alpha: 1), .init(white: 0.84, alpha: 1), .init(white: 0.98, alpha: 1)])!.draw(in: disc, angle: 40)
    NSColor(white: 0.25, alpha: 0.14).setStroke()
    for radius in stride(from: 180, through: 340, by: 26) { let circle = NSBezierPath(ovalIn: NSRect(x: 512-radius,y: 512-radius,width: radius*2,height: radius*2)); circle.lineWidth = 2; circle.stroke() }
    NSColor(calibratedRed: 0.045, green: 0.12, blue: 0.15, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 426,y: 426,width: 172,height: 172)).fill()
    NSColor(white: 0.85, alpha: 0.85).setStroke(); let rim = NSBezierPath(ovalIn: NSRect(x: 414,y: 414,width: 196,height: 196)); rim.lineWidth = 6; rim.stroke()
    NSColor(calibratedRed: 0.96, green: 0.36, blue: 0.20, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 728,y: 175,width: 128,height: 128)).fill()
    NSGraphicsContext.restoreGraphicsState()
    let data = bitmap.representation(using: .png, properties: [:])!
    let name: String
    if size == 1024 { name = "icon_512x512@2x.png" }
    else { name = "icon_\(size)x\(size).png" }
    try data.write(to: root.appendingPathComponent(name))
    if size >= 32 && size <= 512 { try data.write(to: root.appendingPathComponent("icon_\(size/2)x\(size/2)@2x.png")) }
}
