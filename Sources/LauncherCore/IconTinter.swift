import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Pillow-compatible HSV recoloring, so launchers made with the original shell
/// script keep the same look: rotate hue and scale saturation
/// in HSV space, keeping alpha. No Python or Pillow needed.
public enum IconTinter {

    /// Recolors a single RGBA pixel (straight alpha, 0–255 channels).
    public static func tint(r: UInt8, g: UInt8, b: UInt8, with tint: Tint) -> (UInt8, UInt8, UInt8) {
        let rf = Double(r) / 255, gf = Double(g) / 255, bf = Double(b) / 255
        let maxc = max(rf, gf, bf), minc = min(rf, gf, bf)
        let v = maxc
        let delta = maxc - minc
        var s = maxc == 0 ? 0 : delta / maxc
        var h = 0.0
        if delta > 0 {
            if maxc == rf { h = (gf - bf) / delta }
            else if maxc == gf { h = 2 + (bf - rf) / delta }
            else { h = 4 + (rf - gf) / delta }
            h /= 6
            if h < 0 { h += 1 }
        }
        h += Double(tint.hueShift) / 256
        h -= h.rounded(.down)
        s = min(1, s * tint.satGain)

        let i = Int(h * 6) % 6
        let f = h * 6 - Double(Int(h * 6))
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        let (ro, go, bo): (Double, Double, Double)
        switch i {
        case 0: (ro, go, bo) = (v, t, p)
        case 1: (ro, go, bo) = (q, v, p)
        case 2: (ro, go, bo) = (p, v, t)
        case 3: (ro, go, bo) = (p, q, v)
        case 4: (ro, go, bo) = (t, p, v)
        default: (ro, go, bo) = (v, p, q)
        }
        func byte(_ x: Double) -> UInt8 { UInt8(max(0, min(255, (x * 255).rounded()))) }
        return (byte(ro), byte(go), byte(bo))
    }

    public static func tint(_ image: CGImage, with tint: Tint) -> CGImage? {
        let w = image.width, h = image.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        if tint.isStock { return ctx.makeImage() }
        guard let data = ctx.data else { return nil }
        let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        for i in stride(from: 0, to: w * h * 4, by: 4) {
            let a = px[i + 3]
            if a == 0 { continue }
            let af = Double(a)
            // un-premultiply -> recolor -> premultiply
            func straight(_ c: UInt8) -> UInt8 { UInt8(min(255, (Double(c) * 255 / af).rounded())) }
            let (r, g, b) = Self.tint(r: straight(px[i]), g: straight(px[i + 1]), b: straight(px[i + 2]), with: tint)
            px[i] = UInt8((Double(r) * af / 255).rounded())
            px[i + 1] = UInt8((Double(g) * af / 255).rounded())
            px[i + 2] = UInt8((Double(b) * af / 255).rounded())
        }
        return ctx.makeImage()
    }

    /// Mean hue (circular, 0–1) and mean saturation of an image's colorful,
    /// opaque pixels. nil when the image has no colorful pixels.
    static func colorStats(_ image: CGImage) -> (hue: Double, saturation: Double)? {
        let size = 64
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let _ = Optional(ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))),
              let data = ctx.data else { return nil }
        let px = data.bindMemory(to: UInt8.self, capacity: size * size * 4)
        var x = 0.0, y = 0.0, satSum = 0.0, count = 0.0
        for i in stride(from: 0, to: size * size * 4, by: 4) where px[i + 3] > 200 {
            let r = Double(px[i]) / 255, g = Double(px[i + 1]) / 255, b = Double(px[i + 2]) / 255
            let maxc = max(r, g, b), minc = min(r, g, b), delta = maxc - minc
            guard maxc > 0.2, delta / maxc > 0.25 else { continue }
            var h: Double
            if maxc == r { h = (g - b) / delta } else if maxc == g { h = 2 + (b - r) / delta } else { h = 4 + (r - g) / delta }
            h /= 6
            x += cos(h * 2 * .pi); y += sin(h * 2 * .pi)
            satSum += delta / maxc; count += 1
        }
        guard count > 20 else { return nil }
        var hue = atan2(y, x) / (2 * .pi)
        if hue < 0 { hue += 1 }
        return (hue, satSum / count)
    }

    /// Guesses the tint that turned `base` into `tinted` (for launchers made by
    /// the old script, which did not record it). Returns `Tint(0, 0)` for gray icons.
    public static func estimateTint(of tinted: CGImage, base: CGImage) -> Tint? {
        guard let b = colorStats(base) else { return nil }
        guard let t = colorStats(tinted) else { return Tint(hueShift: 0, satGain: 0) }
        // Same range as the presets (-7…215), so a guessed blue reads as 135, not -121.
        var shift = (t.hue - b.hue) * 256
        while shift >= 224 { shift -= 256 }
        while shift < -32 { shift += 256 }
        let gain = (t.saturation / b.saturation * 100).rounded() / 100
        return Tint(hueShift: Int(shift.rounded()), satGain: abs(gain - 1) < 0.05 ? 1.0 : gain)
    }

    /// Loads the representation of an .icns closest to (but not smaller than) `pixelSize`.
    public static func loadImage(_ url: URL, pixelSize: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        var best: CGImage?
        for i in 0..<CGImageSourceGetCount(src) {
            guard let img = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
            guard let current = best else { best = img; continue }
            let fits = img.width >= pixelSize, currentFits = current.width >= pixelSize
            if (fits && (!currentFits || img.width < current.width)) || (!fits && !currentFits && img.width > current.width) {
                best = img
            }
        }
        return best
    }

    /// The icon macOS actually shows for an app, rendered at `pixelSize`.
    /// For Claude this is the asset-catalog icon (Assets.car), which is slightly
    /// brighter than the bundled electron.icns, so we tint from this one.
    public static func appIcon(_ app: URL, pixelSize: Int) -> CGImage? {
        let image = NSWorkspace.shared.icon(forFile: app.path)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: pixelSize, height: pixelSize, bitsPerComponent: 8,
                                  bytesPerRow: pixelSize * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        image.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize), from: .zero,
                   operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    /// Writes a recolored copy of `app`'s icon (as macOS shows it) to `destination`.
    public static func writeTintedIcon(ofApp app: URL, to destination: URL, tint: Tint, badge: Badge? = nil) throws {
        let fm = FileManager.default
        try? fm.removeItem(at: destination)
        let tmp = fm.temporaryDirectory.appendingPathComponent("claude-launcher-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: tmp) }
        let iconset = tmp.appendingPathComponent("icon.iconset")
        try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
        let files: [(Int, String)] = [
            (16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"), (128, "128x128"),
            (256, "128x128@2x"), (256, "256x256"), (512, "256x256@2x"), (512, "512x512"), (1024, "512x512@2x"),
        ]
        for (pixels, name) in files {
            let url = iconset.appendingPathComponent("icon_\(name).png")
            guard let base = appIcon(app, pixelSize: pixels),
                  let tinted = Self.tint(base, with: tint),
                  let out = badge.map({ applying($0, to: tinted) }) ?? tinted,
                  let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
            else { continue }
            CGImageDestinationAddImage(dest, out, nil)
            CGImageDestinationFinalize(dest)
        }
        try Shell.run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", destination.path])
    }
}
