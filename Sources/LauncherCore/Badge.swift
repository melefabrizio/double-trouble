import AppKit
import CoreGraphics
import CoreText
import Foundation

/// A small colored mark in the bottom-right corner of a launcher icon, with up
/// to three uppercase characters. Bottom right because the Dock puts
/// notification badges top right, and the Finder puts the alias arrow bottom left.
public struct Badge: Hashable, Sendable {
    public var color: BadgeColor
    public var text: String

    public static let maxLength = 3

    public init(color: BadgeColor, text: String = "") {
        self.color = color
        self.text = Self.normalize(text)
    }

    /// Uppercase letters and digits only, at most three. Keeps config.sh safe to source.
    public static func normalize(_ text: String) -> String {
        String(text.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(maxLength))
    }
}

/// Fixed palette. No red: a red mark on an icon reads as a notification badge.
public enum BadgeColor: String, CaseIterable, Identifiable, Sendable {
    case blue, teal, green, yellow, purple, pink, graphite, black

    public var id: String { rawValue }

    /// Localized, ready to display.
    public var name: String {
        switch self {
        case .blue: String(localized: "Blu")
        case .teal: String(localized: "Azzurro")
        case .green: String(localized: "Verde")
        case .yellow: String(localized: "Giallo")
        case .purple: String(localized: "Viola")
        case .pink: String(localized: "Rosa")
        case .graphite: String(localized: "Grafite")
        case .black: String(localized: "Nero")
        }
    }

    /// sRGB, close to the macOS system colors.
    public var rgb: (Double, Double, Double) {
        switch self {
        case .blue: (0.00, 0.48, 1.00)
        case .teal: (0.19, 0.69, 0.78)
        case .green: (0.20, 0.78, 0.35)
        case .yellow: (1.00, 0.80, 0.00)
        case .purple: (0.69, 0.32, 0.87)
        case .pink: (1.00, 0.18, 0.57)
        case .graphite: (0.56, 0.56, 0.58)
        case .black: (0.11, 0.11, 0.12)
        }
    }

    /// Dark text on light badges, white elsewhere.
    public var textIsDark: Bool { self == .yellow }
}

extension IconTinter {
    /// Below this size the text is unreadable, so only the dot is drawn.
    public static let badgeTextMinPixels = 64

    /// Draws `badge` over `image`, inside the bottom-right corner of the rounded
    /// square. Nothing may fall outside the icon's own shape: macOS 26 boxes any
    /// icon whose silhouette is not the standard one in a gray tile.
    public static func applying(_ badge: Badge, to image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let s = CGFloat(w)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        let height = s * 0.26
        let edge = s * 0.845
        var line: CTLine?
        var width = height
        if !badge.text.isEmpty && w >= badgeTextMinPixels {
            let base = NSFont.systemFont(ofSize: height * 0.6, weight: .bold)
            let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: height * 0.6) } ?? base
            let (r, g, b) = badge.color.textIsDark ? (0.1, 0.1, 0.1) : (1.0, 1.0, 1.0)
            let attributed = NSAttributedString(string: badge.text, attributes: [
                .font: font,
                .foregroundColor: CGColor(srgbRed: r, green: g, blue: b, alpha: 1),
            ])
            let l = CTLineCreateWithAttributedString(attributed)
            line = l
            let textWidth = CTLineGetTypographicBounds(l, nil, nil, nil)
            width = max(height, CGFloat(textWidth) + height * 0.55)
        }
        let rect = CGRect(x: edge - width, y: s - edge, width: width, height: height)
        let path = CGPath(roundedRect: rect, cornerWidth: height / 2, cornerHeight: height / 2, transform: nil)

        let (r, g, b) = badge.color.rgb
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.006), blur: max(1, s * 0.015),
                      color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.35))
        ctx.setFillColor(CGColor(srgbRed: r, green: g, blue: b, alpha: 1))
        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.setLineWidth(max(1, s * 0.018))
        ctx.addPath(path)
        ctx.strokePath()

        if let line {
            // Center on the cap height: the text is always uppercase.
            let runs = CTLineGetGlyphRuns(line) as! [CTRun]
            let font = runs.first.map { (CTRunGetAttributes($0) as NSDictionary)[kCTFontAttributeName] as! CTFont }
            let cap = font.map { CTFontGetCapHeight($0) } ?? height * 0.42
            let textWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            ctx.textPosition = CGPoint(x: rect.midX - textWidth / 2, y: rect.midY - cap / 2)
            CTLineDraw(line, ctx)
        }
        // Keep only what lies within the original silhouette.
        ctx.setBlendMode(.destinationIn)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }
}
