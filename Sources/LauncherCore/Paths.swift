import Foundation

/// Every filesystem location the launcher touches. Injected so tests can point
/// everything at a temporary directory.
public struct Paths: Sendable {
    /// The real Claude Desktop bundle that every launcher starts.
    public var claudeApp: URL
    /// Where isolated profiles live: `<base>/<instance>`.
    public var instancesBase: URL
    /// Claude's built-in profile (used by the `default` instance).
    public var defaultProfile: URL
    /// Folder for launchers that have been created but not installed yet.
    public var staging: URL
    /// The system Applications folder (install target).
    public var applications: URL
    /// The per-user Applications folder (scanned, never written to).
    public var userApplications: URL
    /// Per-instance APFS clones of Claude.app, so a running instance shows its
    /// launcher's icon in the Dock. `.noindex` keeps them out of Spotlight.
    /// Must match CLONES in `LauncherScript`.
    public var clones: URL { staging.deletingLastPathComponent().appendingPathComponent("Clones.noindex") }

    public init(claudeApp: URL, instancesBase: URL, defaultProfile: URL,
                staging: URL, applications: URL, userApplications: URL) {
        self.claudeApp = claudeApp
        self.instancesBase = instancesBase
        self.defaultProfile = defaultProfile
        self.staging = staging
        self.applications = applications
        self.userApplications = userApplications
    }

    public static var live: Paths {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return Paths(
            claudeApp: URL(fileURLWithPath: "/Applications/Claude.app"),
            instancesBase: home.appendingPathComponent(".claude-instances"),
            defaultProfile: home.appendingPathComponent("Library/Application Support/Claude"),
            staging: home.appendingPathComponent("Library/Application Support/Double Trouble/Launchers"),
            applications: URL(fileURLWithPath: "/Applications"),
            userApplications: home.appendingPathComponent("Applications")
        )
    }

    public func profile(for instance: String) -> URL {
        instance == InstanceName.defaultName
            ? defaultProfile
            : instancesBase.appendingPathComponent(instance)
    }

    /// Before the rename the app kept its files in "Claude Launcher". Moves staged
    /// launchers to the new folder and drops old clones (they are rebuilt on
    /// demand), skipping any clone still running; retried on every start.
    public static func migrateLegacySupportFolder(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        let fm = FileManager.default
        let support = home.appendingPathComponent("Library/Application Support")
        let old = support.appendingPathComponent("Claude Launcher")
        let new = support.appendingPathComponent("Double Trouble")
        guard fm.fileExists(atPath: old.path) else { return }
        let ps = (try? Shell.run("/bin/ps", ["-axww", "-o", "command="], check: false)) ?? ""

        let oldLaunchers = old.appendingPathComponent("Launchers")
        let newLaunchers = new.appendingPathComponent("Launchers")
        for name in (try? fm.contentsOfDirectory(atPath: oldLaunchers.path)) ?? [] {
            let target = newLaunchers.appendingPathComponent(name)
            guard !fm.fileExists(atPath: target.path) else { continue }
            try? fm.createDirectory(at: newLaunchers, withIntermediateDirectories: true)
            try? fm.moveItem(at: oldLaunchers.appendingPathComponent(name), to: target)
        }
        let oldClones = old.appendingPathComponent("Clones.noindex")
        for name in (try? fm.contentsOfDirectory(atPath: oldClones.path)) ?? [] {
            let dir = oldClones.appendingPathComponent(name)
            if !ps.contains(dir.path + "/") { try? fm.removeItem(at: dir) }
        }
        // Remove whatever is now empty, deepest first.
        for dir in [oldLaunchers, oldClones, old] {
            let rest = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0 != ".DS_Store" }
            if rest.isEmpty { try? fm.removeItem(at: dir) }
        }
    }

    public func clone(for instance: String) -> URL {
        clones.appendingPathComponent(instance).appendingPathComponent("Claude.app")
    }

    /// The Claude icon that launcher icons are recolored from.
    public var claudeIcon: URL? {
        let resources = claudeApp.appendingPathComponent("Contents/Resources")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: resources.path)) ?? []
        return files.sorted().first { $0.hasSuffix(".icns") }.map { resources.appendingPathComponent($0) }
    }
}
