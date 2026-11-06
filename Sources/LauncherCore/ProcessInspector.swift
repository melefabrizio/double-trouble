import Darwin
import Foundation

public struct RunningState: Equatable, Sendable {
    public var pid: Int32
    /// Number of renderer processes: 0 means the instance runs with no window open.
    public var windows: Int
}

/// Tells which instances are running, with the same rules as the launcher script:
/// the main process has no `--type=`, open windows show up as `--type=renderer`.
public enum ProcessInspector {
    static let binaryMarker = "Claude.app/Contents/MacOS/Claude"

    public static func parse(psOutput: String, instancesBase: String) -> [String: RunningState] {
        let base = instancesBase.hasSuffix("/") ? instancesBase : instancesBase + "/"
        var mains: [String: Int32] = [:]
        var renderers: [String: Int] = [:]

        for raw in psOutput.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let space = line.firstIndex(of: " "), let pid = Int32(line[..<space]) else { continue }
            let command = String(line[space...])
            // Claude's own processes: the app binary, plus helpers in Contents/Frameworks.
            guard command.contains("Claude.app/Contents/") else { continue }
            var isMainBinary = false
            if let markerRange = command.range(of: binaryMarker) {
                // The binary itself, not ".../MacOS/Claude Helper": next char is a space or the end.
                isMainBinary = markerRange.upperBound == command.endIndex || command[markerRange.upperBound] == " "
            }

            var instance = InstanceName.defaultName
            if let dir = userDataDir(in: command), dir.hasPrefix(base) {
                instance = String(dir.dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
            if command.contains("--type=renderer") {
                renderers[instance, default: 0] += 1
            } else if isMainBinary && !command.contains("--type=") {
                if instance == InstanceName.defaultName, userDataDir(in: command) != nil { continue }
                mains[instance] = mains[instance].map { min($0, pid) } ?? pid
            }
        }
        return mains.reduce(into: [:]) { result, entry in
            result[entry.key] = RunningState(pid: entry.value, windows: renderers[entry.key] ?? 0)
        }
    }

    static func userDataDir(in command: String) -> String? {
        guard let start = command.range(of: "--user-data-dir=") else { return nil }
        let rest = command[start.upperBound...]
        let end = rest.range(of: " --")?.lowerBound ?? rest.endIndex
        var value = String(rest[..<end]).trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 { value = String(value.dropFirst().dropLast()) }
        return value
    }

    /// A clone of a non-default instance running without `--user-data-dir`:
    /// Claude relaunched it after updating itself, so it is on the default profile.
    public struct Stray: Equatable, Sendable {
        public var instance: String
        public var pid: Int32
        public var seconds: Int
    }

    /// Parses `ps -o pid=,etime=,command=`.
    public static func strays(psOutput: String, clonesBase: String) -> [Stray] {
        let base = clonesBase.hasSuffix("/") ? clonesBase : clonesBase + "/"
        var found: [Stray] = []
        for raw in psOutput.split(whereSeparator: \.isNewline) {
            let parts = raw.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3, let pid = Int32(parts[0]), let seconds = elapsedSeconds(String(parts[1])) else { continue }
            let command = String(parts[2])
            guard command.hasPrefix(base), !command.contains("--type="), !command.contains("--user-data-dir") else { continue }
            let rest = command.dropFirst(base.count)
            guard let slash = rest.firstIndex(of: "/"),
                  rest[slash...].hasPrefix("/Claude.app/Contents/MacOS/Claude") else { continue }
            let instance = String(rest[..<slash])
            if instance != InstanceName.defaultName { found.append(Stray(instance: instance, pid: pid, seconds: seconds)) }
        }
        return found
    }

    /// `ps` etime: [[dd-]hh:]mm:ss
    static func elapsedSeconds(_ text: String) -> Int? {
        var days = 0, clock = Substring(text)
        if let dash = text.firstIndex(of: "-") {
            guard let d = Int(text[..<dash]) else { return nil }
            days = d
            clock = text[text.index(after: dash)...]
        }
        let fields = clock.split(separator: ":").map { Int($0) }
        guard !fields.isEmpty, fields.count <= 3, fields.allSatisfy({ $0 != nil }) else { return nil }
        return days * 86400 + fields.reduce(0) { $0 * 60 + $1! }
    }

    public static func strays(clonesBase: URL) -> [Stray] {
        let output = (try? Shell.run("/bin/ps", ["-axww", "-o", "pid=,etime=,command="], check: false)) ?? ""
        return strays(psOutput: output, clonesBase: clonesBase.path)
    }

    public static func snapshot(instancesBase: URL) -> [String: RunningState] {
        let output = (try? Shell.run("/bin/ps", ["-axww", "-o", "pid=,command="], check: false)) ?? ""
        return parse(psOutput: output, instancesBase: instancesBase.path)
    }

    /// Claude's main process ignores SIGTERM, so quitting a
    /// specific instance from outside means SIGKILL. Its helpers go with it.
    public static func forceQuit(pid: Int32) {
        kill(pid, SIGKILL)
    }
}
