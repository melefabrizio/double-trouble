// Draws the disk image window background: Design/dmg-background.png, 640×400 at 1x.
// Only 1x on purpose: on macOS 26 Finder draws the 2x image of a HiDPI TIFF (or a
// 144 dpi PNG) at twice the window size, so the layout breaks.
// Layout must match scripts/dmg-settings.py: 640×400 window, icons centered at
// (170, 190) and (470, 190). Run: swift Design/scripts/make-dmg-background.swift
import AppKit

let width = 640.0, height = 400.0
let appCenter = CGPoint(x: 170, y: 190), appsCenter = CGPoint(x: 470, y: 190) // top-left origin

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func render(scale: Double) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: scale, y: scale)
    // Flip to top-left origin, like Finder coordinates.
    ctx.translateBy(x: 0, y: height); ctx.scaleBy(x: 1, y: -1)

    // Background: the icon's warm gradient.
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [color(0xF5F1E8), color(0xE9E2D3)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: height), options: [])

    // Arrow from the app to Applications: a dotted line ending in a chevron.
    let y = appCenter.y - 6
    let from = appCenter.x + 92, to = appsCenter.x - 92
    ctx.setFillColor(color(0x2B2A27, 0.4))
    var x = from
    while x < to - 10 {
        ctx.fillEllipse(in: CGRect(x: x - 2.25, y: y - 2.25, width: 4.5, height: 4.5))
        x += 11
    }
    let chevron = CGMutablePath()
    chevron.move(to: CGPoint(x: to - 9, y: y - 9))
    chevron.addLine(to: CGPoint(x: to, y: y))
    chevron.addLine(to: CGPoint(x: to - 9, y: y + 9))
    ctx.setStrokeColor(color(0x2B2A27, 0.4))
    ctx.setLineWidth(4.5); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.addPath(chevron); ctx.strokePath()

    // Caption.
    ctx.translateBy(x: 0, y: height); ctx.scaleBy(x: 1, y: -1) // back to AppKit coordinates for text
    let caption = NSAttributedString(string: "Drag Double Trouble to Applications", attributes: [
        .font: NSFont.systemFont(ofSize: 13, weight: .medium),
        .foregroundColor: NSColor(cgColor: color(0x2B2A27, 0.6))!,
    ])
    let size = caption.size()
    caption.draw(at: NSPoint(x: (width - size.width) / 2, y: 62))

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let dir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let out = dir.appendingPathComponent("dmg-background.png")
try! render(scale: 1).representation(using: .png, properties: [:])!.write(to: out)
print("✅ \(out.path)")
