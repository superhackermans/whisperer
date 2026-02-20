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
            NSLog("[Whisperer-CMD] Cannot send '%@' — subprocess not running (process=%@, isRunning=%d)",
                  command,
                  process == nil ? "nil" : "exists",
                  process?.isRunning == true ? 1 : 0)
            return
        }
        guard let data = (command + "\n").data(using: .utf8) else { return }
        NSLog("[Whisperer-CMD] >>> Sending to Python stdin: '%@'", command)
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

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()

        // Bridge script path
        let bridgePath = findBridgeScript()

        // Use the detected/configured Python interpreter.
        // ConfigManager.findPython() probes each candidate to ensure it has pyyaml.
        let pythonPath = configManager.pythonPath
        if pythonPath.isEmpty {
            // Fallback: use /usr/bin/env to resolve from PATH
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["python3", bridgePath]
        } else {
            process.executableURL = URL(fileURLWithPath: pythonPath)
            process.arguments = [bridgePath]
        }

        // Working directory is the bridge script's directory so imports work
        process.currentDirectoryURL = URL(fileURLWithPath: bridgePath).deletingLastPathComponent()

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

        // Handle stderr (just log it)
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            if let output = String(data: data, encoding: .utf8) {
                NSLog("[Whisperer stderr] %@", output.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        // Handle termination
        process.terminationHandler = { [weak self] proc in
            guard let self = self else { return }
            NSLog("[Whisperer] Subprocess terminated with status %d", proc.terminationStatus)

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
            try process.run()
            let args = process.arguments?.joined(separator: " ") ?? ""
            NSLog("[Whisperer] Subprocess launched: %@ %@", process.executableURL?.path ?? "?", args)
            DispatchQueue.main.async {
                self.appState.isSubprocessRunning = true
            }
        } catch {
            NSLog("[Whisperer] Failed to launch subprocess: %@", error.localizedDescription)
            DispatchQueue.main.async {
                self.appState.status = .error("Failed to start Python bridge")
                self.appState.isSubprocessRunning = false
            }
        }
    }

    private func findBridgeScript() -> String {
        // 1. Check inside the .app bundle's Resources (Finder launch)
        if let resourceURL = Bundle.main.resourceURL {
            let bundled = resourceURL.appendingPathComponent("swift_bridge.py").path
            if FileManager.default.fileExists(atPath: bundled) {
                NSLog("[Whisperer] Found swift_bridge.py in bundle Resources: %@", bundled)
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

        var dir = startURL
        for _ in 0..<10 {
            let candidate = dir.appendingPathComponent("swift_bridge.py").path
            if FileManager.default.fileExists(atPath: candidate) {
                NSLog("[Whisperer] Found swift_bridge.py walking up from executable: %@", candidate)
                return candidate
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }

        // 3. Check current working directory
        let cwdCandidate = FileManager.default.currentDirectoryPath + "/swift_bridge.py"
        if FileManager.default.fileExists(atPath: cwdCandidate) {
            NSLog("[Whisperer] Found swift_bridge.py in cwd: %@", cwdCandidate)
            return cwdCandidate
        }

        // Last resort — caller will get a "file not found" from Python
        NSLog("[Whisperer] swift_bridge.py NOT FOUND — searched bundle Resources, walked up from %@, checked cwd %@",
              startURL.path, FileManager.default.currentDirectoryPath)
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
            NSLog("[Whisperer] Too many crashes (%d in %ds) — not restarting", count, Int(crashWindowSeconds))
            DispatchQueue.main.async {
                self.appState.status = .error("Python bridge crashed repeatedly")
            }
            lock.lock()
            isRunning = false
            lock.unlock()
            return
        }

        NSLog("[Whisperer] Restarting subprocess (crash %d/%d)", count, maxCrashes)
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
