import AppKit
import Foundation

let destination = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Could not create icon bitmap") }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        NSColor(calibratedWhite: 0.11, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 200, yRadius: 200).fill()
        NSColor(calibratedWhite: 0.38, alpha: 1).setStroke()
        let frame = NSBezierPath(roundedRect: NSRect(x: 235, y: 278, width: 554, height: 468), xRadius: 46, yRadius: 46)
        frame.lineWidth = 18; frame.stroke()
        let play = NSBezierPath()
        play.move(to: NSPoint(x: 436, y: 376)); play.line(to: NSPoint(x: 436, y: 648)); play.line(to: NSPoint(x: 654, y: 512)); play.close()
        NSColor(calibratedWhite: 0.96, alpha: 1).setFill(); play.fill()
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(name))
    }
}
