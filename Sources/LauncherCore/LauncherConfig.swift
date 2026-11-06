import Foundation

/// `Contents/MacOS/config.sh` inside a launcher. The launcher script `source`s it,
/// so it must stay valid bash. The original script only wrote INSTANCE_NAME;
/// we also record the tint so the color can be edited later.
public struct LauncherConfig: Equatable, Sendable {
    public var instance: String
    public var tint: Tint?
    public var badge: Badge?

    public init(instance: String, tint: Tint?, badge: Badge? = nil) {
        self.instance = instance
        self.tint = tint
        self.badge = badge
    }

    public static func parse(_ text: String) -> LauncherConfig? {
        var values: [String: String] = [:]
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).replacingOccurrences(of: "export ", with: "")
            var value = String(line[line.index(after: eq)...])
            if value.count >= 2, let f = value.first, f == "\"" || f == "'", value.last == f {
                value = String(value.dropFirst().dropLast())
            }
            values[key] = value
        }
        guard let instance = values["INSTANCE_NAME"], !instance.isEmpty else { return nil }
        var tint: Tint?
        if let hue = values["HUE_SHIFT"].flatMap({ Int($0) }) {
            tint = Tint(hueShift: hue, satGain: values["SAT_GAIN"].flatMap { Double($0) } ?? 1.0)
        }
        let badge = values["BADGE_COLOR"].flatMap(BadgeColor.init(rawValue:))
            .map { Badge(color: $0, text: values["BADGE_TEXT"] ?? "") }
        return LauncherConfig(instance: instance, tint: tint, badge: badge)
    }

    public var text: String {
        var lines = ["INSTANCE_NAME=\(instance)"]
        if let tint {
            lines.append("HUE_SHIFT=\(tint.hueShift)")
            lines.append("SAT_GAIN=\(String(format: "%.2f", tint.satGain))")
        }
        if let badge {
            lines.append("BADGE_COLOR=\(badge.color.rawValue)")
            // normalize() keeps only letters and digits, so single quotes are safe.
            if !badge.text.isEmpty { lines.append("BADGE_TEXT='\(Badge.normalize(badge.text))'") }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
