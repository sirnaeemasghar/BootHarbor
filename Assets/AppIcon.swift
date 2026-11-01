// SPDX-License-Identifier: GPL-3.0-or-later
// Original vector artwork. Regenerate with scripts/generate-icon.sh.
import AppKit

func drawIcon() {
    if CommandLine.arguments.count > 2, let portrait = NSImage(contentsOfFile: CommandLine.arguments[2]) {
        portrait.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024), from: .zero, operation: .sourceOver, fraction: 1)
        return
    }
    let tile = NSRect(x: 64, y: 64, width: 896, height: 896)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 196, yRadius: 196)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.20)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    NSGradient(starting: NSColor(srgbRed: 0.13, green: 0.68, blue: 0.76, alpha: 1),
               ending: NSColor(srgbRed: 0.07, green: 0.23, blue: 0.50, alpha: 1))!.draw(in: shape, angle: -65)
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.withAlphaComponent(0.25).setStroke()
    shape.lineWidth = 2; shape.stroke()
    func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: tile.minX + tile.width * x, y: tile.minY + tile.height * (1 - y))
    }
    let mark = NSBezierPath()
    mark.move(to: point(0.5, 0.23)); mark.line(to: point(0.5, 0.58))
    mark.move(to: point(0.35, 0.44)); mark.line(to: point(0.5, 0.59)); mark.line(to: point(0.65, 0.44))
    mark.move(to: point(0.24, 0.56)); mark.line(to: point(0.24, 0.70))
    mark.curve(to: point(0.32, 0.78), controlPoint1: point(0.24, 0.753), controlPoint2: point(0.267, 0.78))
    mark.line(to: point(0.68, 0.78))
    mark.curve(to: point(0.76, 0.70), controlPoint1: point(0.733, 0.78), controlPoint2: point(0.76, 0.753))
    mark.line(to: point(0.76, 0.56))
    mark.lineWidth = tile.width * 0.065
    mark.lineCapStyle = .round; mark.lineJoinStyle = .round
    NSColor.white.setStroke(); mark.stroke()
}

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = base * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let transform = NSAffineTransform()
        transform.scale(by: CGFloat(pixels) / 1024); transform.concat()
        drawIcon()
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(base)x\(base)" + (scale == 2 ? "@2x" : "") + ".png"
        let data = bitmap.representation(using: .png, properties: [:])!
        try data.write(to: output.appendingPathComponent(name))
        if pixels == 1024 { try data.write(to: output.deletingLastPathComponent().appendingPathComponent("AppIconPreview.png")) }
    }
}
