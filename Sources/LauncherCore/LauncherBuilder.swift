import Foundation

public struct LauncherSpec: Equatable, Sendable {
    public var instance: String
    public var displayName: String
    public var tint: Tint
    public var badge: Badge?

    public init(instance: String, displayName: String, tint: Tint, badge: Badge? = nil) {
        self.instance = instance
        self.displayName = displayName
        self.tint = tint
        self.badge = badge
    }

    public var bundleName: String { "Claude \(displayName).app" }
}

public enum LauncherError: LocalizedError, Equatable {
    case claudeMissing
    case nameInUse(String)
    case invalidDisplayName

    public var errorDescription: String? {
        switch self {
        case .claudeMissing: String(localized: "Claude non è installato in /Applications. Scaricalo da claude.ai/download.")
        case .nameInUse(let path): String(localized: "Esiste già un'app con questo nome: \(path)")
        case .invalidDisplayName: String(localized: "Il nome non può essere vuoto né contenere \"/\" o \":\".")
        }
    }
}

/// Writes `Claude <Name>.app` bundles in the same layout as `make-claude-instance.sh`.
public struct LauncherBuilder: Sendable {
    public let paths: Paths
    /// Off in tests: no LaunchServices registration.
    public var registerWithSystem = true

    public init(paths: Paths) { self.paths = paths }

    public static func isValidDisplayName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && !trimmed.contains("/") && !trimmed.contains(":") && !trimmed.hasPrefix(".")
    }

    /// Creates a new launcher inside `directory`. Also creates the profile folder.
    @discardableResult
    public func create(_ spec: LauncherSpec, in directory: URL) throws -> URL {
        guard Self.isValidDisplayName(spec.displayName) else { throw LauncherError.invalidDisplayName }
        let fm = FileManager.default
        let target = directory.appendingPathComponent(spec.bundleName)
        if fm.fileExists(atPath: target.path) { throw LauncherError.nameInUse(target.path) }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let built = try buildBundle(spec, near: directory)
        defer { try? fm.removeItem(at: built.deletingLastPathComponent()) }
        try fm.moveItem(at: built, to: target)
        if spec.instance != InstanceName.defaultName {
            try fm.createDirectory(at: paths.profile(for: spec.instance), withIntermediateDirectories: true)
        }
        register(target)
        return target
    }

    /// Rebuilds an existing launcher with a new name and/or color. Renames the
    /// bundle when the name changes. Returns the new location.
    @discardableResult
    public func update(_ existing: URL, to spec: LauncherSpec) throws -> URL {
        guard Self.isValidDisplayName(spec.displayName) else { throw LauncherError.invalidDisplayName }
        let fm = FileManager.default
        let directory = existing.deletingLastPathComponent()
        let target = directory.appendingPathComponent(spec.bundleName)
        let renaming = target.standardizedFileURL.path != existing.standardizedFileURL.path
        if renaming && fm.fileExists(atPath: target.path) { throw LauncherError.nameInUse(target.path) }

        let built = try buildBundle(spec, near: directory)
        defer { try? fm.removeItem(at: built.deletingLastPathComponent()) }
        if renaming {
            try fm.moveItem(at: built, to: target)
            try fm.removeItem(at: existing)
        } else {
            _ = try fm.replaceItemAt(existing, withItemAt: built)
        }
        register(target)
        return target
    }

    /// Moves a launcher into another folder (staging -> /Applications).
    @discardableResult
    public func move(_ launcher: URL, to directory: URL) throws -> URL {
        let fm = FileManager.default
        let target = directory.appendingPathComponent(launcher.lastPathComponent)
        if fm.fileExists(atPath: target.path) { throw LauncherError.nameInUse(target.path) }
        try fm.moveItem(at: launcher, to: target)
        register(target)
        return target
    }

    /// Rewrites the script of a launcher made by an older version of this app (or
    /// by the original shell script), keeping its config and icon. Returns true when it changed.
    @discardableResult
    public static func upgradeScript(of launcher: URL) throws -> Bool {
        let script = launcher.appendingPathComponent("Contents/MacOS/claude-launcher")
        guard let current = try? String(contentsOf: script, encoding: .utf8),
              FileManager.default.fileExists(atPath: launcher.appendingPathComponent("Contents/MacOS/config.sh").path),
              !current.contains(LauncherScript.marker)
        else { return false }
        try LauncherScript.text.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return true
    }

    // MARK: - Private

    /// Assembles the bundle in a temporary folder on the same volume as `directory`
    /// so the final step is an atomic rename.
    private func buildBundle(_ spec: LauncherSpec, near directory: URL) throws -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: paths.claudeApp.path) else { throw LauncherError.claudeMissing }
        let scratch = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                 appropriateFor: directory, create: true)
        let app = scratch.appendingPathComponent(spec.bundleName)
        let macOS = app.appendingPathComponent("Contents/MacOS")
        let resources = app.appendingPathComponent("Contents/Resources")
        try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "CFBundleExecutable": "claude-launcher",
            "CFBundleIdentifier": "local.claude-launcher.\(spec.instance)",
            "CFBundleName": "Claude \(spec.displayName)",
            "CFBundleDisplayName": "Claude \(spec.displayName)",
            "CFBundleVersion": "1.0",
            "CFBundleShortVersionString": "1.0",
            "CFBundlePackageType": "APPL",
            "CFBundleInfoDictionaryVersion": "6.0",
            "LSMinimumSystemVersion": "11.0",
            "CFBundleIconFile": "claude-icon",
            "NSHighResolutionCapable": true,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: app.appendingPathComponent("Contents/Info.plist"))

        try LauncherConfig(instance: spec.instance, tint: spec.tint, badge: spec.badge).text
            .write(to: macOS.appendingPathComponent("config.sh"), atomically: true, encoding: .utf8)
        let script = macOS.appendingPathComponent("claude-launcher")
        try LauncherScript.text.write(to: script, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        try IconTinter.writeTintedIcon(ofApp: paths.claudeApp, to: resources.appendingPathComponent("claude-icon.icns"),
                                       tint: spec.tint, badge: spec.badge)
        return app
    }

    private func register(_ app: URL) {
        guard registerWithSystem else { return }
        // Bump the mtime so Finder drops its cached icon, then tell LaunchServices.
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: app.path)
        _ = try? Shell.run(
            "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
            ["-f", app.path], check: false)
    }
}
