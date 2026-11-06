import AppKit
import LauncherCore
import Observation

/// State for the Claude Code tab. Independent from the Desktop `Store`.
@MainActor @Observable
final class CodeStore {
    let paths = CodePaths.live
    var environments: [CodeEnvironment] = []
    var selection: String?
    var sizes: [String: Int64] = [:]
    var busy: Set<String> = []
    var error: UserFacingError?
    var showingNewSheet = false
    var isInstalled = false

    private var manager: CodeManager { CodeManager(paths: paths) }
    private var pollTask: Task<Void, Never>?

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func refresh() async {
        let paths = self.paths
        let (envs, installed) = await Task.detached {
            (CodeScanner(paths: paths).scan(),
             paths.claudeBinary != nil || FileManager.default.fileExists(atPath: paths.mainConfigDir.path))
        }.value
        if envs != environments { environments = envs }
        isInstalled = installed
    }

    func environment(_ id: String?) -> CodeEnvironment? {
        environments.first { $0.id == id }
    }

    var existingDirs: Set<String> { Set(environments.map(\.configDir.path)) }

    private func perform(_ id: String, failure: String.LocalizationValue, _ work: @escaping @Sendable () throws -> Void) async -> Bool {
        busy.insert(id)
        defer { busy.remove(id) }
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

    func create(name: String, displayName: String, copyConfigFrom source: URL?) async -> Bool {
        let manager = self.manager
        let dir = paths.configDir(for: name).path
        let ok = await perform(dir, failure: "Impossibile creare l'ambiente") {
            try manager.create(name: name, displayName: displayName, copyConfigFrom: source)
        }
        if ok { selection = dir }
        return ok
    }

    /// Creates the script for an existing folder and, if asked, disables the
    /// shell aliases that would shadow it.
    func adopt(_ env: CodeEnvironment, displayName: String, disableAliases: Bool) async {
        let manager = self.manager
        let command = env.command ?? paths.command(for: env.name)
        let aliases = disableAliases ? env.aliases : []
        _ = await perform(env.id, failure: "Impossibile creare il comando") {
            try manager.writeScript(command: command, displayName: displayName, configDir: env.configDir)
            for alias in aliases { try ShellAliases.disable(alias) }
        }
    }

    func rename(_ env: CodeEnvironment, to displayName: String) async {
        guard let command = env.command else { return }
        let manager = self.manager
        _ = await perform(env.id, failure: "Impossibile rinominare") {
            try manager.writeScript(command: command, displayName: displayName, configDir: env.configDir)
        }
    }

    func disableAliases(_ env: CodeEnvironment) async {
        let aliases = env.aliases
        _ = await perform(env.id, failure: "Impossibile disattivare l'alias") {
            for alias in aliases { try ShellAliases.disable(alias) }
        }
    }

    func delete(_ env: CodeEnvironment, includingConfig: Bool) async {
        guard !env.isMain else { return }
        let manager = self.manager
        let ok = await perform(env.id, failure: "Impossibile eliminare l'ambiente") {
            try manager.delete(env, includingConfig: includingConfig)
        }
        if ok && includingConfig { sizes[env.id] = nil }
    }

    func measure(_ env: CodeEnvironment) async {
        guard env.configExists else { return }
        let url = env.configDir
        let size = await Task.detached { ProfileTools.size(of: url) }.value
        sizes[env.id] = size
    }

    func copyCommand(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }
}
