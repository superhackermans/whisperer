import Foundation

/// Writes diagnostic information to ~/Library/Logs/Whisperer.log so that
/// Finder-launched failures are visible (NSLog/print go nowhere without a terminal).
enum DiagnosticLog {
    private static let logURL: URL = {
        // Place log next to the .app bundle (same directory the user sees in Finder).
        // Falls back to ~/Library/Logs/ if the bundle's parent isn't writable.
        let bundleParent = URL(fileURLWithPath: Bundle.main.bundlePath)
            .deletingLastPathComponent()
        let candidate = bundleParent.appendingPathComponent("Whisperer.log")
        if FileManager.default.isWritableFile(atPath: bundleParent.path) {
            return candidate
        }
        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs")
        return logsDir.appendingPathComponent("Whisperer.log")
    }()

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    /// Append a timestamped line to the log file and also send to NSLog.
    static func log(_ message: String) {
        let timestamp = formatter.string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        NSLog("[Whisperer] %@", message)

        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path) {
                if let handle = try? FileHandle(forWritingTo: logURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: logURL)
            }
        }
    }

    /// Clear and start a new session in the log file.
    static func startSession() {
        let separator = String(repeating: "=", count: 60)
        let header = """
        \(separator)
        WHISPERER LAUNCH — \(formatter.string(from: Date()))
        PID: \(ProcessInfo.processInfo.processIdentifier)
        Bundle: \(Bundle.main.bundlePath)
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        \(separator)

        """
        try? header.write(to: logURL, atomically: false, encoding: .utf8)
    }

    static var logPath: String { logURL.path }
}
