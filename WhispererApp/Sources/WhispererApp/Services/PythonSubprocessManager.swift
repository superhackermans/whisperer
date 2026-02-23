import Foundation

final class PythonSubprocessManager {
    private var process: Process?
    private var stdinPipe: Pipe?
    private let appState: AppState
    private let configManager: ConfigManager
    private let parser = StdoutParser()

    private var crashCount = 0
    private var crashWindowStart = Date()
    private let maxCrashesInWindow = 3
    private let crashWindowSeconds: TimeInterval = 30

    private var isRunning = false

    /// Protects mutable state accessed from multiple threads:
    /// isRunning, crashCount, crashWindowStart
    private let lock = NSLock()

    init(appState: AppState, configManager: ConfigManager) {
        self.appState = appState
        self.configManager = configManager
    }

    // MARK: - Lifecycle

    func start() {
        lock.lock()
        let alreadyRunning = isRunning
        lock.unlock()
        guard !alreadyRunning else { return }
        launchProcess()
    }

    func stop() {
        lock.lock()
        isRunning = false
        lock.unlock()
        sendCommand("quit")
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) { [weak self] in
            if self?.process?.isRunning == true {
                self?.process?.terminate()
            }
            self?.process = nil
        }
    }

    func sendCommand(_ command: String) {
        guard let pipe = stdinPipe, let proc = process, proc.isRunning else {
            DiagnosticLog.log("Cannot send '\(command)' — subprocess not running (process=\(process == nil ? "nil" : "exists"), isRunning=\(process?.isRunning == true))")
            return
        }
        guard let data = (command + "\n").data(using: .utf8) else { return }
        DiagnosticLog.log(">>> Sending to Python stdin: '\(command)'")
        // SIGPIPE is ignored globally (set in AppDelegate), so writing to a broken
        // pipe won't crash — it will simply fail silently, which is acceptable
        // since the terminationHandler will handle recovery.
        pipe.fileHandleForWriting.write(data)
    }

    // MARK: - Process Management

    private func launchProcess() {
        lock.lock()
        isRunning = true
        lock.unlock()

        DiagnosticLog.log("launchProcess: starting Python subprocess")

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()

        // Bridge script path
        let bridgePath = findBridgeScript()
        DiagnosticLog.log("Bridge script path: \(bridgePath)")

        // Use the detected/configured Python interpreter.
        // ConfigManager.findPython() probes each candidate to ensure it has pyyaml.
        let pythonPath = configManager.pythonPath
        DiagnosticLog.log("ConfigManager.pythonPath = '\(pythonPath)'")
        if pythonPath.isEmpty {
            // Fallback: use /usr/bin/env to resolve from PATH
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["python3", bridgePath]
            DiagnosticLog.log("Using /usr/bin/env python3 (no configured Python)")
        } else {
            let pythonExists = FileManager.default.fileExists(atPath: pythonPath)
            DiagnosticLog.log("Using configured Python: \(pythonPath) (exists: \(pythonExists))")
            process.executableURL = URL(fileURLWithPath: pythonPath)
            process.arguments = [bridgePath]
        }

        // Working directory is the bridge script's directory so imports work
        let workingDir = URL(fileURLWithPath: bridgePath).deletingLastPathComponent()
        process.currentDirectoryURL = workingDir
        DiagnosticLog.log("Working directory: \(workingDir.path)")

        // Environment — Finder launches have minimal PATH, so ensure common paths are included
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let extraPaths = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/usr/bin",
            "\(home)/miniconda3/bin",
            "\(home)/anaconda3/bin",
            "\(home)/miniforge3/bin",
        ]
        let currentPath = env["PATH"] ?? "/usr/bin:/bin"
        let existing = currentPath.split(separator: ":").map(String.init)
        let toAdd = extraPaths.filter { !existing.contains($0) }
        env["PATH"] = (existing + toAdd).joined(separator: ":")
        DiagnosticLog.log("PATH = \(env["PATH"] ?? "(nil)")")

        // Always enable debug logging in Python bridge for diagnostics.
        // Python debug lines are prefixed with DEBUG and parsed by StdoutParser.
        env["WHISPERER_DEBUG"] = "1"

        process.environment = env
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = stdinPipe

        // Handle stdout
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                // EOF
                handle.readabilityHandler = nil
                return
            }
            if let output = String(data: data, encoding: .utf8) {
                let lines = output.components(separatedBy: .newlines)
                for line in lines where !line.isEmpty {
                    self?.handleLine(line)
                }
            }
        }

        // Handle stderr — write to diagnostic log so Finder launch errors are visible
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            if let output = String(data: data, encoding: .utf8) {
                let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    DiagnosticLog.log("Python stderr: \(trimmed)")
                }
            }
        }

        // Handle termination
        process.terminationHandler = { [weak self] proc in
            guard let self = self else { return }
            DiagnosticLog.log("Subprocess terminated — exit status \(proc.terminationStatus), reason \(proc.terminationReason.rawValue)")

            DispatchQueue.main.async {
                self.appState.isSubprocessRunning = false
            }

            self.lock.lock()
            let shouldRestart = self.isRunning
            self.lock.unlock()

            if shouldRestart {
                self.handleCrash()
            }
        }

        self.process = process
        self.stdinPipe = stdinPipe

        do {
            let execPath = process.executableURL?.path ?? "?"
            let args = process.arguments?.joined(separator: " ") ?? ""
            DiagnosticLog.log("Launching: \(execPath) \(args)")
            try process.run()
            DiagnosticLog.log("Subprocess launched successfully — PID \(process.processIdentifier)")
            DispatchQueue.main.async {
                self.appState.isSubprocessRunning = true
            }
        } catch {
            DiagnosticLog.log("FAILED to launch subprocess: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.appState.status = .error("Failed to start Python bridge: \(error.localizedDescription)")
                self.appState.isSubprocessRunning = false
            }
        }
    }

    private func findBridgeScript() -> String {
        DiagnosticLog.log("findBridgeScript: searching for swift_bridge.py")
        DiagnosticLog.log("  Bundle.main.bundlePath = \(Bundle.main.bundlePath)")
        DiagnosticLog.log("  Bundle.main.resourceURL = \(Bundle.main.resourceURL?.path ?? "nil")")
        DiagnosticLog.log("  Bundle.main.executableURL = \(Bundle.main.executableURL?.path ?? "nil")")
        DiagnosticLog.log("  cwd = \(FileManager.default.currentDirectoryPath)")

        // 1. Check inside the .app bundle's Resources (Finder launch)
        if let resourceURL = Bundle.main.resourceURL {
            let bundled = resourceURL.appendingPathComponent("swift_bridge.py").path
            let exists = FileManager.default.fileExists(atPath: bundled)
            DiagnosticLog.log("  Check bundle Resources: \(bundled) — \(exists ? "FOUND" : "not found")")
            if exists {
                return bundled
            }
        }

        // 2. Walk upward from the executable (terminal/SPM development launch)
        let startURL: URL
        if let execURL = Bundle.main.executableURL {
            startURL = execURL.deletingLastPathComponent()
        } else {
            startURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        }

        DiagnosticLog.log("  Walking up from: \(startURL.path)")
        var dir = startURL
        for i in 0..<10 {
            let candidate = dir.appendingPathComponent("swift_bridge.py").path
            let exists = FileManager.default.fileExists(atPath: candidate)
            DiagnosticLog.log("  Walk[\(i)]: \(candidate) — \(exists ? "FOUND" : "not found")")
            if exists {
                return candidate
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }

        // 3. Check current working directory
        let cwdCandidate = FileManager.default.currentDirectoryPath + "/swift_bridge.py"
        let cwdExists = FileManager.default.fileExists(atPath: cwdCandidate)
        DiagnosticLog.log("  Check cwd: \(cwdCandidate) — \(cwdExists ? "FOUND" : "not found")")
        if cwdExists {
            return cwdCandidate
        }

        // Last resort — caller will get a "file not found" from Python
        DiagnosticLog.log("  swift_bridge.py NOT FOUND anywhere!")
        return "swift_bridge.py"
    }

    // MARK: - Line Parsing

    private func handleLine(_ line: String) {
        let event = parser.parse(line: line)
        NSLog("[Whisperer-PY] <<< %@  →  event=%@", line.prefix(200).description, "\(event)")

        switch event {
        case .bridgeReady:
            NSLog("[Whisperer-PY] Bridge ready — setting status to .idle")
            DispatchQueue.main.async {
                self.appState.status = .idle
                self.appState.isSubprocessRunning = true
            }

        case .recordingStarted:
            NSLog("[Whisperer-PY] Recording started — setting status to .recording")
            DispatchQueue.main.async {
                self.appState.status = .recording
            }
            // Safety net: if still recording after 5 minutes, auto-recover
            DispatchQueue.main.asyncAfter(deadline: .now() + 300) { [weak self] in
                if case .recording = self?.appState.status {
                    NSLog("[Whisperer] Recording timeout — auto-recovering to idle")
                    self?.appState.status = .idle
                }
            }

        case .stoppingRecording:
            // Transitional — will go to transcribing or idle
            break

        case .transcribing(let model):
            NSLog("[Whisperer-PY] Transcribing with model '%@' — setting status to .transcribing", model)
            DispatchQueue.main.async {
                self.appState.status = .transcribing
                self.appState.currentModel = model
            }
            // Safety net: if status is still .transcribing after 60s, auto-recover
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
                if case .transcribing = self?.appState.status {
                    NSLog("[Whisperer] Transcription timeout — auto-recovering to idle")
                    self?.appState.status = .idle
                }
            }

        case .finalText(let text):
            DispatchQueue.main.async {
                self.appState.lastTranscription = text
            }

        case .pasted:
            NSLog("[Whisperer-PY] Pasted — setting status to .idle")
            DispatchQueue.main.async {
                self.appState.status = .idle
                self.postTranscriptionNotification()
            }

        case .transcriptionDone:
            // Reliable completion signal — return to idle from any active state.
            // This fires via on_transcription_done callback regardless of paste success/failure.
            // Also handles early-exit paths (no frames, too short) where status is still .recording.
            NSLog("[Whisperer-PY] TRANSCRIPTION_DONE — current status=%@", "\(self.appState.status)")
            DispatchQueue.main.async {
                switch self.appState.status {
                case .recording, .transcribing:
                    NSLog("[Whisperer-PY] TRANSCRIPTION_DONE: recovering to .idle from %@", "\(self.appState.status)")
                    self.appState.status = .idle
                default:
                    NSLog("[Whisperer-PY] TRANSCRIPTION_DONE: status already %@ — no change", "\(self.appState.status)")
                    break
                }
            }

        case .cancelThat, .emptyTranscription, .bracketedSkip, .tooShort:
            NSLog("[Whisperer-PY] Skip event (%@) — setting status to .idle", "\(event)")
            DispatchQueue.main.async {
                self.appState.status = .idle
            }

        case .error(let title, let message):
            NSLog("[Whisperer-PY] ERROR: %@: %@", title, message)
            DispatchQueue.main.async {
                self.appState.status = .error("\(title): \(message)")
            }
            // Auto-recover to idle after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                if case .error = self?.appState.status {
                    self?.appState.status = .idle
                }
            }

        case .copied:
            // Intermediate state, pasted follows
            break

        case .rawText, .cleanedText:
            // Informational, already logged
            break

        case .debug(let tag, let message):
            appState.appendDebug("[\(tag)] \(message)")

        case .log(let message):
            if !message.isEmpty {
                appState.appendDebug(message)
            }
        }
    }

    // MARK: - Crash Recovery

    private func handleCrash() {
        lock.lock()
        let now = Date()
        if now.timeIntervalSince(crashWindowStart) > crashWindowSeconds {
            crashCount = 0
            crashWindowStart = now
        }
        crashCount += 1
        let count = crashCount
        let maxCrashes = maxCrashesInWindow
        lock.unlock()

        if count >= maxCrashes {
            DiagnosticLog.log("Too many crashes (\(count) in \(Int(crashWindowSeconds))s) — NOT restarting")
            DispatchQueue.main.async {
                self.appState.status = .error("Python bridge crashed repeatedly")
            }
            lock.lock()
            isRunning = false
            lock.unlock()
            return
        }

        DiagnosticLog.log("Restarting subprocess (crash \(count)/\(maxCrashes)) in 1s...")
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.launchProcess()
        }
    }

    // MARK: - Notifications

    private func postTranscriptionNotification() {
        guard UserDefaults.standard.bool(forKey: "notificationsEnabled") else { return }
        let text = appState.lastTranscription ?? "Transcription complete"
        let preview = String(text.prefix(100))

        // Use osascript with argv-based parameter passing to avoid injection.
        // The transcription text is passed as a handler argument, never interpolated
        // into the AppleScript source.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e", "on run argv",
            "-e", "display notification (item 1 of argv) with title \"Whisperer\"",
            "-e", "end run",
            "--",
            preview,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            NSLog("[Whisperer] Notification error: %@", error.localizedDescription)
        }
    }
}
