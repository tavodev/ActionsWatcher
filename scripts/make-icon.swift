import AppKit

// A code-drawn native icon; no external assets or build dependencies.
let directory = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
var chunks = Data()
func bigEndian(_ value: Int) -> Data {
    var integer = UInt32(value).bigEndian
    return withUnsafeBytes(of: &integer) { Data($0) }
}
let types = ["16-1": "icp4", "16-2": "ic11", "32-1": "icp5", "32-2": "ic12",
             "128-1": "ic07", "128-2": "ic13", "256-1": "ic08", "256-2": "ic14",
             "512-1": "ic09", "512-2": "ic10"]
let navy = NSColor(srgbRed: 1 / 255.0, green: 7 / 255.0, blue: 54 / 255.0, alpha: 1).cgColor
let navySurface = NSColor(srgbRed: 13 / 255.0, green: 28 / 255.0, blue: 66 / 255.0, alpha: 1).cgColor
let blue = NSColor(srgbRed: 34 / 255.0, green: 57 / 255.0, blue: 111 / 255.0, alpha: 1).cgColor
let cream = NSColor(srgbRed: 252 / 255.0, green: 241 / 255.0, blue: 208 / 255.0, alpha: 1).cgColor
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let rect = CGRect(x: 45, y: 45, width: 934, height: 934)
        let background = CGPath(roundedRect: rect, cornerWidth: 212, cornerHeight: 212, transform: nil)
        context.addPath(background)
        context.setFillColor(navy)
        context.fillPath()
        context.saveGState()
        context.addPath(background)
        context.clip()
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: [navySurface, navy] as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 45, y: 979),
            end: CGPoint(x: 979, y: 45), options: [])
        context.restoreGState()
        context.addPath(background)
        context.setStrokeColor(blue)
        context.setLineWidth(4)
        context.strokePath()
        context.setStrokeColor(cream)
        context.setLineWidth(48)
        context.setLineCap(.round)
        context.move(to: CGPoint(x: 368, y: 300))
        context.addLine(to: CGPoint(x: 368, y: 710))
        context.move(to: CGPoint(x: 368, y: 450))
        context.addCurve(to: CGPoint(x: 660, y: 690), control1: CGPoint(x: 368, y: 635), control2: CGPoint(x: 660, y: 505))
        context.strokePath()
        for point in [CGPoint(x: 368, y: 300), CGPoint(x: 368, y: 710), CGPoint(x: 660, y: 710)] {
            context.setFillColor(cream)
            context.fillEllipse(in: CGRect(x: point.x - 62, y: point.y - 62, width: 124, height: 124))
            context.setFillColor(navy)
            context.fillEllipse(in: CGRect(x: point.x - 25, y: point.y - 25, width: 50, height: 50))
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let png = bitmap.representation(using: .png, properties: [:])!
        try png.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
        chunks.append(Data(types["\(size)-\(scale)"]!.utf8))
        chunks.append(bigEndian(png.count + 8))
        chunks.append(png)
    }
}
var icon = Data("icns".utf8)
icon.append(bigEndian(chunks.count + 8))
icon.append(chunks)
try icon.write(to: directory.deletingLastPathComponent().appendingPathComponent("AppIcon.icns"))
