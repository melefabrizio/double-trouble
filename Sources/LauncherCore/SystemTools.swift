import Foundation

public enum Dock {
    /// The Dock caches icons; restarting it is the only reliable way to show a new one.
    public static func restart() {
        _ = try? Shell.run("/usr/bin/killall", ["Dock"], check: false)
    }
}

public enum ProfileTools {
    /// Electron caches, safe to delete while the instance is quit (they are rebuilt).
    public static let cacheFolders = [
        "Cache", "Code Cache", "GPUCache", "GPUPersistentCache", "DawnGraphiteCache",
        "DawnWebGPUCache", "GraphiteDawnCache", "ShaderCache",
    ]
    /// The local agent / Cowork runtime. Often many GB; re-downloaded on demand.
    public static let vmBundles = "vm_bundles"

    public static func size(of url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in walker {
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    public static func reclaimableSize(in profile: URL, folders: [String]) -> Int64 {
        folders.reduce(0) { $0 + size(of: profile.appendingPathComponent($1)) }
    }

    /// Deletes the given subfolders of a profile for good (they are regenerable,
    /// and the Trash would not actually free the space).
    public static func remove(folders: [String], in profile: URL) throws {
        let fm = FileManager.default
        for name in folders {
            let url = profile.appendingPathComponent(name)
            if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
        }
    }

    /// Copies Claude's default profile into a new isolated one, so the new
    /// instance starts signed in. Same excludes as the README, plus vm_bundles.
    public static func copyProfile(from source: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var args = ["-a"]
        for exclude in ["Singleton*", "Crashpad", "blob_storage", vmBundles] + cacheFolders {
            args += ["--exclude", exclude]
        }
        args += [source.path + "/", destination.path + "/"]
        try Shell.run("/usr/bin/rsync", args)
    }
}
