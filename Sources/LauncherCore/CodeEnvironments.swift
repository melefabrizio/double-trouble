import Foundation

// Claude Code environments: same idea as the Desktop launchers. An environment is
// a config folder (CLAUDE_CONFIG_DIR) plus a small launcher script in ~/.local/bin
// that carries its own metadata, so the scripts themselves are the registry.

public struct CodePaths: Sendable {
    public var home: URL
    /// Where command scripts are written (`claude-<name>`). Must be on PATH.
    public var bin: URL
    /// Shell startup files searched for old `claude-*` aliases.
    public var shellFiles: [URL]
    /// fish autoloaded functions (`functions/claude-*.fish`).
    public var fishFunctions: URL

    public init(home: URL, bin: URL, shellFiles: [URL], fishFunctions: URL) {
        self.home = home
        self.bin = bin
        self.shellFiles = shellFiles
        self.fishFunctions = fishFunctions
    }

    public static var live: CodePaths {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let fish = home.appendingPathComponent(".config/fish")
        let confD = fish.appendingPathComponent("conf.d")
        let confDFiles = ((try? FileManager.default.contentsOfDirectory(atPath: confD.path)) ?? [])
            .filter { $0.hasSuffix(".fish") }.sorted().map { confD.appendingPathComponent($0) }
        return CodePaths(
            home: home,
            bin: home.appendingPathComponent(".local/bin"),
            shellFiles: [fish.appendingPathComponent("config.fish")] + confDFiles
                + [".zshrc", ".zprofile", ".zshenv", ".bashrc", ".bash_profile", ".profile"]
                    .map { home.appendingPathComponent($0) },
            fishFunctions: fish.appendingPathComponent("functions"))
    }

    /// The main profile used by plain `claude`.
    public var mainConfigDir: URL { home.appendingPathComponent(".claude") }

    public func configDir(for name: String) -> URL { home.appendingPathComponent(".claude-\(name)") }
    public func command(for name: String) -> String { "claude-\(name)" }
    public func script(for name: String) -> URL { bin.appendingPathComponent(command(for: name)) }

    /// `claude` itself, wherever it is installed (nil = Claude Code not installed).
    public var claudeBinary: URL? {
        let candidates = [bin.path, "/opt/homebrew/bin", "/usr/local/bin",
                          home.appendingPathComponent(".npm-global/bin").path,
                          home.appendingPathComponent(".claude/local").path]
        return candidates.map { URL(fileURLWithPath: $0).appendingPathComponent("claude") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

// MARK: - Model

public struct CodeAccount: Equatable, Hashable, Sendable {
    public var email: String
    public var organization: String?
}

/// A `claude-*` alias or function in a shell startup file that sets CLAUDE_CONFIG_DIR.
public struct ShellAlias: Equatable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable { case line(Int), fishFunctionFile }
    public var file: URL
    public var kind: Kind
    public var command: String
    public var configDir: URL?

    public var fileDescription: String {
        let path = (file.path as NSString).abbreviatingWithTildeInPath
        if case .line(let n) = kind { return "\(path):\(n)" }
        return path
    }
}

public struct CodeEnvironment: Identifiable, Hashable, Sendable {
    public var id: String { configDir.path }
    /// Short name: "work" for ~/.claude-work. Empty for the main profile.
    public var name: String
    public var displayName: String
    public var configDir: URL
    /// Our launcher script, if any.
    public var script: URL?
    public var command: String?
    public var aliases: [ShellAlias]
    public var account: CodeAccount?
    public var configExists: Bool
    public var isMain: Bool

    /// A folder that looks like a Code profile but no script launches it.
    public var needsCommand: Bool { !isMain && script == nil }
}

// MARK: - Launcher script

public enum CodeScript {
    static let marker = "# claude-launcher: code-environment"

    public static func text(displayName: String, configDir: URL) -> String {
        let dir = configDir.path.replacingOccurrences(of: "'", with: "'\\''")
        let name = displayName.replacingOccurrences(of: "\n", with: " ")
        return """
        #!/bin/sh
        \(marker)
        # name: \(name)
        # Runs Claude Code with its own config folder (account, settings, history).
        # Managed by Double Trouble: edit it from the app.
        export CLAUDE_CONFIG_DIR='\(dir)'
        exec claude "$@"

        """
    }

    public struct Parsed: Equatable {
        public var displayName: String?
        public var configDir: URL
    }

    public static func parse(_ text: String, home: URL) -> Parsed? {
        guard text.contains(marker) else { return nil }
        var name: String?
        var dir: URL?
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("# name:") {
                name = line.dropFirst("# name:".count).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("export CLAUDE_CONFIG_DIR=") {
                dir = expandPath(String(line.dropFirst("export CLAUDE_CONFIG_DIR=".count)), home: home)
            }
        }
        guard let dir else { return nil }
        return Parsed(displayName: name?.isEmpty == false ? name : nil, configDir: dir)
    }

    /// '~/x', "$HOME/x", '/abs' -> URL. Quotes stripped.
    static func expandPath(_ raw: String, home: URL) -> URL {
        var value = raw.trimmingCharacters(in: .whitespaces)
        if value.count >= 2, let f = value.first, f == "'" || f == "\"", value.last == f {
            value = String(value.dropFirst().dropLast())
        }
        value = value.replacingOccurrences(of: "'\\''", with: "'")
        for prefix in ["$HOME", "${HOME}", "~"] where value.hasPrefix(prefix) {
            value = home.path + value.dropFirst(prefix.count)
        }
        return URL(fileURLWithPath: value).standardizedFileURL
    }
}

// MARK: - Shell aliases

public enum ShellAliases {
    /// Finds `alias claude-x …CLAUDE_CONFIG_DIR=…` lines (fish, zsh, bash) and
    /// fish function files named claude-*.fish that set CLAUDE_CONFIG_DIR.
    public static func find(in paths: CodePaths) -> [ShellAlias] {
        var found: [ShellAlias] = []
        for file in paths.shellFiles {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for (index, line) in text.components(separatedBy: "\n").enumerated() {
                if let alias = parseAliasLine(line, home: paths.home) {
                    found.append(ShellAlias(file: file, kind: .line(index + 1), command: alias.command,
                                            configDir: alias.configDir))
                }
            }
        }
        let functionFiles = (try? FileManager.default.contentsOfDirectory(atPath: paths.fishFunctions.path)) ?? []
        for name in functionFiles where name.hasPrefix("claude-") && name.hasSuffix(".fish") {
            let file = paths.fishFunctions.appendingPathComponent(name)
            guard let text = try? String(contentsOf: file, encoding: .utf8), text.contains("CLAUDE_CONFIG_DIR") else { continue }
            found.append(ShellAlias(file: file, kind: .fishFunctionFile,
                                    command: String(name.dropLast(".fish".count)),
                                    configDir: configDir(in: text, home: paths.home)))
        }
        return found
    }

    static func parseAliasLine(_ line: String, home: URL) -> (command: String, configDir: URL?)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("alias "), trimmed.contains("CLAUDE_CONFIG_DIR") else { return nil }
        let rest = trimmed.dropFirst("alias ".count).trimmingCharacters(in: .whitespaces)
        let command = String(rest.prefix { !$0.isWhitespace && $0 != "=" })
        guard command.hasPrefix("claude-") else { return nil }
        return (command, configDir(in: trimmed, home: home))
    }

    static func configDir(in text: String, home: URL) -> URL? {
        guard let range = text.range(of: "CLAUDE_CONFIG_DIR") else { return nil }
        var rest = text[range.upperBound...].drop { $0 == " " || $0 == "=" || $0 == "\t" }
        // fish: `set -x CLAUDE_CONFIG_DIR value` / `--export`; sh: `CLAUDE_CONFIG_DIR=value`
        var value = ""
        var quote: Character?
        if let f = rest.first, f == "'" || f == "\"" { quote = f; rest = rest.dropFirst() }
        for ch in rest {
            if let q = quote, ch == q { break }
            if quote == nil && (ch.isWhitespace || ch == "'" || ch == "\"" || ch == ";") { break }
            value.append(ch)
        }
        return value.isEmpty ? nil : CodeScript.expandPath(value, home: home)
    }

    /// Disables an alias: the line is commented out (fish function files are
    /// renamed so fish stops autoloading them). A backup of the file is kept.
    public static func disable(_ alias: ShellAlias) throws {
        let fm = FileManager.default
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
        switch alias.kind {
        case .fishFunctionFile:
            try fm.moveItem(at: alias.file, to: alias.file.appendingPathExtension("disabled-\(stamp)"))
        case .line(let number):
            let text = try String(contentsOf: alias.file, encoding: .utf8)
            var lines = text.components(separatedBy: "\n")
            guard number - 1 < lines.count,
                  parseAliasLine(lines[number - 1], home: URL(fileURLWithPath: "/"))?.command == alias.command
            else { throw CocoaError(.fileWriteUnknown) }
            try fm.copyItem(at: alias.file,
                            to: alias.file.deletingLastPathComponent()
                                .appendingPathComponent(alias.file.lastPathComponent + ".bak-claude-launcher-\(stamp)"))
            lines[number - 1] = "# [disabled by Double Trouble, replaced by ~/.local/bin/\(alias.command)] " + lines[number - 1]
            try lines.joined(separator: "\n").write(to: alias.file, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Scanning

public struct CodeScanner: Sendable {
    public let paths: CodePaths
    public init(paths: CodePaths) { self.paths = paths }

    /// Reads email/org from the profile's .claude.json (the main profile keeps it in ~/.claude.json).
    public func account(configDir: URL, isMain: Bool) -> CodeAccount? {
        let state = isMain ? paths.home.appendingPathComponent(".claude.json")
                           : configDir.appendingPathComponent(".claude.json")
        guard let data = try? Data(contentsOf: state),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = json["oauthAccount"] as? [String: Any],
              let email = account["emailAddress"] as? String, !email.isEmpty
        else { return nil }
        return CodeAccount(email: email, organization: account["organizationName"] as? String)
    }

    /// `~/.claude-<x>` folders that look like Claude Code config dirs.
    func profileFolders() -> [URL] {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: paths.home.path)) ?? []
        return names.filter { $0.hasPrefix(".claude-") && $0 != ".claude-instances" }
            .map { paths.home.appendingPathComponent($0) }
            .filter { url in
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return false }
                return [".claude.json", "settings.json", "projects", "history.jsonl"]
                    .contains { fm.fileExists(atPath: url.appendingPathComponent($0).path) }
            }
    }

    public func scan(includeMain: Bool = true) -> [CodeEnvironment] {
        let fm = FileManager.default
        var byDir: [String: CodeEnvironment] = [:]

        func name(for dir: URL) -> String {
            let last = dir.lastPathComponent
            return last.hasPrefix(".claude-") ? String(last.dropFirst(".claude-".count)) : last
        }
        func blank(_ dir: URL) -> CodeEnvironment {
            let n = name(for: dir)
            return CodeEnvironment(name: n, displayName: n.prefix(1).uppercased() + n.dropFirst(),
                                   configDir: dir, script: nil, command: nil, aliases: [], account: nil,
                                   configExists: fm.fileExists(atPath: dir.path), isMain: false)
        }

        // 1. Our scripts.
        for file in (try? fm.contentsOfDirectory(atPath: paths.bin.path)) ?? [] where file.hasPrefix("claude-") {
            let url = paths.bin.appendingPathComponent(file)
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  let parsed = CodeScript.parse(text, home: paths.home) else { continue }
            var env = byDir[parsed.configDir.path] ?? blank(parsed.configDir)
            env.script = url
            env.command = file
            if let display = parsed.displayName { env.displayName = display }
            byDir[parsed.configDir.path] = env
        }
        // 2. Profile folders nobody launches yet.
        for dir in profileFolders() {
            let key = dir.standardizedFileURL.path
            if byDir[key] == nil { byDir[key] = blank(dir.standardizedFileURL) }
        }
        // 3. Old shell aliases, attached to the folder they point at.
        for alias in ShellAliases.find(in: paths) {
            guard let dir = alias.configDir else { continue }
            var env = byDir[dir.path] ?? blank(dir)
            env.aliases.append(alias)
            byDir[dir.path] = env
        }

        var result = byDir.values.map { env -> CodeEnvironment in
            var env = env
            env.account = account(configDir: env.configDir, isMain: false)
            return env
        }
        .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }

        if includeMain && fm.fileExists(atPath: paths.mainConfigDir.path) {
            result.insert(CodeEnvironment(
                name: "", displayName: "Principale", configDir: paths.mainConfigDir, script: nil,
                command: "claude", aliases: [], account: account(configDir: paths.mainConfigDir, isMain: true),
                configExists: true, isMain: true), at: 0)
        }
        return result
    }
}

// MARK: - Actions

public enum CodeEnvironmentError: LocalizedError, Equatable {
    case commandInUse(String)
    case notOurScript(String)

    public var errorDescription: String? {
        switch self {
        case .commandInUse(let path): String(localized: "Esiste già un comando con questo nome: \(path)")
        case .notOurScript(let path): String(localized: "\(path) non è stato creato da Double Trouble e non verrà modificato.")
        }
    }
}

public struct CodeManager: Sendable {
    public let paths: CodePaths
    public init(paths: CodePaths) { self.paths = paths }

    /// What `~/.claude` items are copied by "start from the main configuration".
    /// Never the login, history or caches.
    public static let sharedConfigItems = ["settings.json", "CLAUDE.md", "agents", "commands", "skills", "output-styles"]

    public static func validate(name: String, existingDirs: Set<String>, paths: CodePaths) -> InstanceName.Problem? {
        if let problem = InstanceName.validate(name, existing: []) { return problem }
        if name == "instances" { return .reserved }
        if existingDirs.contains(paths.configDir(for: name).path)
            || FileManager.default.fileExists(atPath: paths.configDir(for: name).path)
            || FileManager.default.fileExists(atPath: paths.script(for: name).path) { return .taken }
        return nil
    }

    /// Writes (or rewrites) the launcher script for a config folder.
    @discardableResult
    public func writeScript(command: String, displayName: String, configDir: URL) throws -> URL {
        let fm = FileManager.default
        let url = paths.bin.appendingPathComponent(command)
        if fm.fileExists(atPath: url.path) {
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            guard text.contains(CodeScript.marker) else { throw CodeEnvironmentError.notOurScript(url.path) }
        }
        try fm.createDirectory(at: paths.bin, withIntermediateDirectories: true)
        try CodeScript.text(displayName: displayName, configDir: configDir)
            .write(to: url, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    /// New environment: folder + script, optionally seeded with another profile's
    /// configuration (`sharedConfigItems` only: never login or history).
    public func create(name: String, displayName: String, copyConfigFrom source: URL?) throws {
        let fm = FileManager.default
        let dir = paths.configDir(for: name)
        if fm.fileExists(atPath: paths.script(for: name).path) {
            throw CodeEnvironmentError.commandInUse(paths.script(for: name).path)
        }
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        if let sourceDir = source {
            for item in Self.sharedConfigItems {
                let source = sourceDir.appendingPathComponent(item)
                guard fm.fileExists(atPath: source.path) else { continue }
                // rsync keeps symlinks (skills are often symlinked) and permissions.
                let isDir = (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                try Shell.run("/usr/bin/rsync", ["-a", source.path + (isDir ? "/" : ""),
                                                 dir.appendingPathComponent(item).path + (isDir ? "/" : "")])
            }
        }
        try writeScript(command: paths.command(for: name), displayName: displayName, configDir: dir)
    }

    public func delete(_ env: CodeEnvironment, includingConfig: Bool) throws {
        let fm = FileManager.default
        if let script = env.script { try fm.trashItem(at: script, resultingItemURL: nil) }
        if includingConfig && !env.isMain && fm.fileExists(atPath: env.configDir.path) {
            try fm.trashItem(at: env.configDir, resultingItemURL: nil)
        }
    }
}
