import Foundation

/// Finds launchers (bundles with `Contents/MacOS/config.sh`) and profiles on disk.
public struct Scanner: Sendable {
    public let paths: Paths

    public init(paths: Paths) { self.paths = paths }

    public func readLauncher(at url: URL, location: LauncherLocation) -> Launcher? {
        let configURL = url.appendingPathComponent("Contents/MacOS/config.sh")
        guard let text = try? String(contentsOf: configURL, encoding: .utf8),
              let config = LauncherConfig.parse(text) else { return nil }
        let plist = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist"))
        var name = (plist?["CFBundleDisplayName"] as? String)
            ?? (plist?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        if name.hasPrefix("Claude ") { name = String(name.dropFirst("Claude ".count)) }
        return Launcher(url: url, instance: config.instance, displayName: name,
                        tint: config.tint, badge: config.badge, location: location)
    }

    public func launchers() -> [Launcher] {
        let fm = FileManager.default
        let places: [(URL, LauncherLocation)] = [
            (paths.applications, .applications),
            (paths.userApplications, .userApplications),
            (paths.staging, .staging),
        ]
        var found: [Launcher] = []
        for (dir, location) in places {
            let names = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
            for name in names where name.hasSuffix(".app") {
                if let launcher = readLauncher(at: dir.appendingPathComponent(name), location: location) {
                    found.append(launcher)
                }
            }
        }
        return found
    }

    public func scan() -> [InstanceRecord] {
        let fm = FileManager.default
        var byName: [String: [Launcher]] = [:]
        for launcher in launchers() { byName[launcher.instance, default: []].append(launcher) }

        // Profiles without a launcher still show up, so they can be re-adopted or removed.
        let profiles = ((try? fm.contentsOfDirectory(atPath: paths.instancesBase.path)) ?? [])
            .filter { name in
                var isDir: ObjCBool = false
                return !name.hasPrefix(".")
                    && fm.fileExists(atPath: paths.instancesBase.appendingPathComponent(name).path, isDirectory: &isDir)
                    && isDir.boolValue
            }
        for name in profiles where byName[name] == nil { byName[name] = [] }

        return byName.map { name, launchers in
            let profile = paths.profile(for: name)
            return InstanceRecord(
                name: name,
                launchers: launchers.sorted { ($0.location, $0.url.path) < ($1.location, $1.url.path) },
                profileURL: profile,
                profileExists: fm.fileExists(atPath: profile.path))
        }
        .sorted { a, b in
            if a.isOrphan != b.isOrphan { return !a.isOrphan }
            return a.displayName.localizedStandardCompare(b.displayName) == .orderedAscending
        }
    }

    /// Staging copies that are redundant because the same launcher was also
    /// installed elsewhere (e.g. dragged to Applications, which copies).
    public static func redundantStagingCopies(in records: [InstanceRecord]) -> [URL] {
        records.flatMap { record -> [URL] in
            let installedNames = Set(record.launchers.filter { $0.location != .staging }.map(\.url.lastPathComponent))
            return record.launchers
                .filter { $0.location == .staging && installedNames.contains($0.url.lastPathComponent) }
                .map(\.url)
        }
    }
}
