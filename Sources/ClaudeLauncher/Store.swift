import AppKit
import LauncherCore
import Observation
import SwiftUI

struct UserFacingError: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// App state. Everything slow (file I/O, ps, iconutil, rsync) runs off the main actor.
@MainActor @Observable
final class Store {
    let paths = Paths.live
    var records: [InstanceRecord] = []
    var running: [String: RunningState] = [:]
    var sizes: [String: Int64] = [:]
    var selection: String?
    var busy: Set<String> = []
    var error: UserFacingError?
    var showingNewSheet = false
    /// Pre-fills the new-environment sheet when adopting a profile that has no launcher.
    var adoptingProfile: String?
    var claudeInstalled = true

    private var builder: LauncherBuilder { LauncherBuilder(paths: paths) }
    private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var handledStrays: Set<Int32> = []

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            await Task.detached { Paths.migrateLegacySupportFolder() }.value
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func refresh() async {
        let paths = self.paths
        let (records, running, installed, strays) = await Task.detached {
            var records = Scanner(paths: paths).scan()
            // Dragging a staged launcher into Applications copies it: drop the staged duplicate.
            let redundant = Scanner.redundantStagingCopies(in: records)
            if !redundant.isEmpty {
                redundant.forEach { try? FileManager.default.removeItem(at: $0) }
                records = Scanner(paths: paths).scan()
            }
            // Launchers from older versions get the clone-aware script.
            for launcher in records.flatMap(\.launchers) { _ = try? LauncherBuilder.upgradeScript(of: launcher.url) }
            return (records,
                    ProcessInspector.snapshot(instancesBase: paths.instancesBase),
                    FileManager.default.fileExists(atPath: paths.claudeApp.path),
                    ProcessInspector.strays(clonesBase: paths.clones))
        }.value
        if records != self.records { self.records = records }
        if running != self.running { self.running = running }
        claudeInstalled = installed
        rehome(strays)
    }

    /// After updating itself, Claude relaunches a clone without its profile, so it
    /// opens on the default one. Put a just-relaunched clone back on its profile.
    /// Only fresh ones (under a minute old): an older one may be in use.
    private func rehome(_ strays: [ProcessInspector.Stray]) {
        for stray in strays where stray.seconds < 60 && !handledStrays.contains(stray.pid) {
            guard let record = record(stray.instance), record.primary != nil else { continue }
            handledStrays.insert(stray.pid)
            ProcessInspector.forceQuit(pid: stray.pid)
            Task {
                try? await Task.sleep(for: .seconds(1))
                launch(record)
            }
        }
    }

    func record(_ name: String?) -> InstanceRecord? {
        records.first { $0.name == name }
    }


    /// The launcher's tint: recorded in config.sh, or guessed from its icon for
    /// launchers made by the old script.
    func currentTint(_ record: InstanceRecord) -> Tint {
        guard let launcher = record.primary else { return .stock }
        if let tint = launcher.tint { return tint }
        let modified = (try? FileManager.default.attributesOfItem(atPath: launcher.iconURL.path)[.modificationDate] as? Date)
            ?? .distantPast
        let key = launcher.iconURL.path
        if let (date, tint) = estimatedTints[key], date == modified { return tint }
        var tint = Tint.stock
        // Old script launchers were tinted from electron.icns, so compare against that.
        if let icon = paths.claudeIcon,
           let base = IconTinter.loadImage(icon, pixelSize: 128),
           let mine = IconTinter.loadImage(launcher.iconURL, pixelSize: 128),
           let guess = IconTinter.estimateTint(of: mine, base: base) {
            // Snap to a preset when it is clearly the one that was used.
            tint = Preset.all.map(\.tint).first {
                abs($0.hueShift - guess.hueShift) <= 3 && abs($0.satGain - guess.satGain) <= 0.05
            } ?? guess
        }
        estimatedTints[key] = (modified, tint)
        return tint
    }

    @ObservationIgnored private var estimatedTints: [String: (Date, Tint)] = [:]

    var existingNames: Set<String> { Set(records.map(\.name)) }

    var defaultClaudeRunning: Bool { running[InstanceName.defaultName] != nil }

    // MARK: - Actions

    private func perform(_ name: String, failure: String.LocalizationValue, _ work: @escaping @Sendable () throws -> Void) async -> Bool {
        busy.insert(name)
        defer { busy.remove(name) }
        do {
            try await Task.detached(operation: work).value
            await refresh()
            return true
        } catch {
            self.error = UserFacingError(title: String(localized: failure), message: error.localizedDescription)
            await refresh()
            return false
        }
    }

    func create(_ spec: LauncherSpec, copyLogin: Bool) async -> Bool {
        let builder = self.builder, paths = self.paths
        let ok = await perform(spec.instance, failure: "Impossibile creare l'ambiente") {
            if copyLogin {
                try ProfileTools.copyProfile(from: paths.defaultProfile, to: paths.profile(for: spec.instance))
            }
            try builder.create(spec, in: paths.staging)
        }
        if ok { selection = spec.instance }
        return ok
    }

    func apply(_ spec: LauncherSpec, to record: InstanceRecord) async {
        let builder = self.builder
        let launchers = record.launchers.map(\.url)
        let colorChanged = currentTint(record) != spec.tint || record.primary?.badge != spec.badge
        let ok = await perform(record.name, failure: "Impossibile salvare le modifiche") {
            for url in launchers { try builder.update(url, to: spec) }
        }
        // The Dock caches icons: restart it so a pinned launcher shows the new look.
        if ok && colorChanged { Dock.restartLater() }
    }

    func install(_ record: InstanceRecord) async {
        guard let staged = record.launchers.first(where: { $0.location == .staging }) else { return }
        let builder = self.builder, target = paths.applications
        _ = await perform(record.name, failure: "Impossibile installare in Applicazioni") {
            try builder.move(staged.url, to: target)
        }
    }

    func launch(_ record: InstanceRecord) {
        if let url = record.primary?.url {
            NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
                if let error {
                    Task { @MainActor in
                        self.error = UserFacingError(title: String(localized: "Impossibile aprire Claude"), message: error.localizedDescription)
                    }
                }
            }
        } else {
            // A profile with no launcher: start Claude on it directly.
            let config = NSWorkspace.OpenConfiguration()
            config.createsNewApplicationInstance = true
            config.arguments = ["--user-data-dir=\(record.profileURL.path)"]
            NSWorkspace.shared.openApplication(at: paths.claudeApp, configuration: config)
        }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            await refresh()
        }
    }

    func forceQuit(_ record: InstanceRecord) async {
        guard let pid = running[record.name]?.pid else { return }
        ProcessInspector.forceQuit(pid: pid)
        try? await Task.sleep(for: .milliseconds(600))
        await refresh()
    }

    func delete(_ record: InstanceRecord, includingProfile: Bool) async {
        let launchers = record.launchers.map(\.url)
        let profile = record.profileURL
        let clone = paths.clone(for: record.name).deletingLastPathComponent()
        let removeProfile = includingProfile && !record.isDefault
        let ok = await perform(record.name, failure: "Impossibile eliminare l'ambiente") {
            let fm = FileManager.default
            for url in launchers { try fm.trashItem(at: url, resultingItemURL: nil) }
            // The clone is a copy of Claude.app, rebuilt on demand: no need for the Trash.
            try? fm.removeItem(at: clone)
            if removeProfile && fm.fileExists(atPath: profile.path) {
                try fm.trashItem(at: profile, resultingItemURL: nil)
            }
        }
        if ok {
            sizes[record.name] = nil
        }
    }

    func measure(_ record: InstanceRecord) async {
        let url = record.profileURL
        guard record.profileExists else { return }
        let size = await Task.detached { ProfileTools.size(of: url) }.value
        sizes[record.name] = size
    }

    func freeSpace(_ record: InstanceRecord, folders: [String]) async {
        let profile = record.profileURL
        _ = await perform(record.name, failure: "Impossibile liberare spazio") {
            try ProfileTools.remove(folders: folders, in: profile)
        }
        await measure(record)
    }
}

extension Dock {
    /// Restarts the Dock after LaunchServices has caught up with the new icon.
    static func restartLater() {
        Task.detached {
            try? await Task.sleep(for: .milliseconds(400))
            Dock.restart()
        }
    }
}
