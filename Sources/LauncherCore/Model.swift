import Foundation

public enum InstanceName {
    public static let defaultName = "default"

    /// Turns a display name into a profile identifier: "Lavoro Ufficio" -> "lavoro-ufficio".
    public static func slug(from displayName: String) -> String {
        let folded = displayName.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        var out = ""
        var lastWasDash = false
        for scalar in folded.unicodeScalars {
            if ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) {
                out.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash && !out.isEmpty {
                out.append("-")
                lastWasDash = true
            }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return out
    }

    public enum Problem: Equatable, Sendable {
        case empty, invalidCharacters, reserved, taken
    }

    public static func validate(_ name: String, existing: Set<String>) -> Problem? {
        if name.isEmpty { return .empty }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-_")
        if name.unicodeScalars.contains(where: { !allowed.contains($0) }) { return .invalidCharacters }
        if name == defaultName { return .reserved }
        if existing.contains(name) { return .taken }
        return nil
    }
}

/// Icon tint. `hueShift` uses the same units as the original script (Pillow HSV,
/// 0–255 == 0–360°), so the colors of launchers made with it read back unchanged.
public struct Tint: Equatable, Hashable, Sendable {
    public var hueShift: Int
    public var satGain: Double

    public init(hueShift: Int, satGain: Double = 1.0) {
        self.hueShift = hueShift
        self.satGain = satGain
    }

    public static let stock = Tint(hueShift: 0, satGain: 1.0)
    public var isStock: Bool { hueShift % 256 == 0 && abs(satGain - 1.0) < 0.001 }

    public var degrees: Double {
        get { Double(hueShift) * 360.0 / 256.0 }
        set { hueShift = Int((newValue * 256.0 / 360.0).rounded()) }
    }
}

public struct Preset: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let tint: Tint

    /// Common hue shifts, plus graphite (no saturation).
    public static let all: [Preset] = [
        Preset(name: "Arancio", tint: Tint(hueShift: 0)),
        Preset(name: "Rosso", tint: Tint(hueShift: -7, satGain: 1.08)),
        Preset(name: "Giallo", tint: Tint(hueShift: 22, satGain: 1.05)),
        Preset(name: "Verde", tint: Tint(hueShift: 80)),
        Preset(name: "Azzurro", tint: Tint(hueShift: 115)),
        Preset(name: "Blu", tint: Tint(hueShift: 135)),
        Preset(name: "Viola", tint: Tint(hueShift: 170)),
        Preset(name: "Rosa", tint: Tint(hueShift: 215)),
        Preset(name: "Grafite", tint: Tint(hueShift: 0, satGain: 0.0)),
    ]
}

public enum LauncherLocation: Int, Comparable, Sendable {
    case applications, userApplications, staging

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// One `Claude <Name>.app` wrapper on disk.
public struct Launcher: Hashable, Sendable {
    public var url: URL
    public var instance: String
    public var displayName: String
    /// nil when the launcher was made by the old script, which did not record the tint.
    public var tint: Tint?
    public var badge: Badge?
    public var location: LauncherLocation

    public var iconURL: URL { url.appendingPathComponent("Contents/Resources/claude-icon.icns") }
}

/// A profile plus whatever launchers point at it.
public struct InstanceRecord: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public var name: String
    /// Sorted so the first one is the "main" launcher (Applications before staging).
    public var launchers: [Launcher]
    public var profileURL: URL
    public var profileExists: Bool

    public var primary: Launcher? { launchers.first }
    public var isOrphan: Bool { launchers.isEmpty }
    public var isDefault: Bool { name == InstanceName.defaultName }
    public var isInstalled: Bool { launchers.contains { $0.location != .staging } }
    public var displayName: String { primary?.displayName ?? name }
}
