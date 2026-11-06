import AppKit
import LauncherCore
import SwiftUI

/// Renders tinted previews of the Claude icon. The base image is decoded once.
@MainActor
final class IconRenderer {
    static let shared = IconRenderer()
    private var base: CGImage?
    private struct Key: Hashable { let tint: Tint; let badge: Badge? }
    private var cache: [Key: NSImage] = [:]

    private init() {
        base = IconTinter.appIcon(Paths.live.claudeApp, pixelSize: 256)
    }

    func image(for tint: Tint, badge: Badge? = nil) -> NSImage {
        let key = Key(tint: tint, badge: badge)
        if let hit = cache[key] { return hit }
        guard let base, let tinted = IconTinter.tint(base, with: tint),
              let final = badge.map({ IconTinter.applying($0, to: tinted) }) ?? tinted else {
            return NSWorkspace.shared.icon(for: .applicationBundle)
        }
        let image = NSImage(cgImage: final, size: NSSize(width: 128, height: 128))
        if cache.count > 200 { cache.removeAll() }
        cache[key] = image
        return image
    }
}

/// The icon actually stored in a launcher (read from its .icns, so it is never
/// a stale Finder/Dock cache).
struct LauncherIcon: View {
    let launcher: Launcher?
    var size: CGFloat

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }

    private var image: NSImage {
        guard let launcher else {
            return NSImage(systemSymbolName: "person.crop.circle.badge.questionmark", accessibilityDescription: nil)
                ?? NSImage()
        }
        let modified = (try? FileManager.default.attributesOfItem(atPath: launcher.iconURL.path)[.modificationDate] as? Date)
            ?? .distantPast
        return IconFileCache.shared.image(at: launcher.iconURL, modified: modified)
            ?? NSWorkspace.shared.icon(forFile: launcher.url.path)
    }
}

@MainActor
final class IconFileCache {
    static let shared = IconFileCache()
    private var cache: [String: (Date, NSImage)] = [:]

    func image(at url: URL, modified: Date) -> NSImage? {
        if let (date, image) = cache[url.path], date == modified { return image }
        guard let image = NSImage(contentsOf: url) else { return nil }
        cache[url.path] = (modified, image)
        return image
    }
}

/// Lets an app bundle be dragged out of the window into the Dock, Finder or Applications.
struct DraggableApp: ViewModifier {
    let url: URL?

    func body(content: Content) -> some View {
        if let url {
            content.onDrag { NSItemProvider(object: url as NSURL) }
        } else {
            content
        }
    }
}

extension View {
    func draggableApp(_ url: URL?) -> some View { modifier(DraggableApp(url: url)) }
}
