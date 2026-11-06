import Foundation

public struct ShellError: LocalizedError {
    public let command: String
    public let status: Int32
    public let stderr: String
    public var errorDescription: String? {
        let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(localized: "\(command) non è riuscito (codice \(status))") + (detail.isEmpty ? "" : ": \(detail)")
    }
}

public enum Shell {
    /// Runs a program synchronously. Call it off the main thread.
    @discardableResult
    public static func run(_ executable: String, _ arguments: [String], check: Bool = true) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        // Read before waiting so a chatty process cannot fill the pipe and block.
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let stdout = String(decoding: outData, as: UTF8.self)
        if check && process.terminationStatus != 0 {
            throw ShellError(command: (executable as NSString).lastPathComponent,
                             status: process.terminationStatus,
                             stderr: String(decoding: errData, as: UTF8.self))
        }
        return stdout
    }
}
