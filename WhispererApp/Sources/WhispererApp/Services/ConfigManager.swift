import Combine
import Foundation
import Yams

/// Manages reading/writing ~/.whisperer/config.yaml
final class ConfigManager: ObservableObject {
    @Published var config: WhispererConfig

    private let configDir: String
    private let configPath: String

    /// Python interpreter path (Swift-only setting, stored in UserDefaults)
    var pythonPath: String {
        get {
            let stored = UserDefaults.standard.string(forKey: "pythonPath") ?? ""
            if !stored.isEmpty { return stored }
            // Auto-detect
            return Self.findPython()
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "pythonPath")
        }
    }

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.configDir = "\(home)/.whisperer"
        self.configPath = "\(home)/.whisperer/config.yaml"
        self.config = WhispererConfig.default

        loadConfig()
    }

    // MARK: - Load

    func loadConfig() {
        guard FileManager.default.fileExists(atPath: configPath) else {
            NSLog("[Whisperer] No config file at %@ — using defaults", configPath)
            config = WhispererConfig.default
            return
        }

        do {
            let yamlString = try String(contentsOfFile: configPath, encoding: .utf8)
            // Parse as generic dict first, then map to our struct
            guard let dict = try Yams.load(yaml: yamlString) as? [String: Any] else {
                NSLog("[Whisperer] Config file is not a YAML dict — using defaults")
                config = WhispererConfig.default
                return
            }

            var c = WhispererConfig.default

            if let v = dict["whispercpp_folder"] as? String { c.whispercppFolder = v }
            if let v = dict["prompt"] as? String { c.prompt = v }
            if let v = dict["enable_beeps"] as? Bool { c.enableBeeps = v }
            if let v = dict["enable_start_sound"] as? Bool { c.enableStartSound = v }
            if let v = dict["enable_stop_sound"] as? Bool { c.enableStopSound = v }
            if let v = dict["enable_error_sound"] as? Bool { c.enableErrorSound = v }
            if let v = dict["sound_volume"] as? Int { c.soundVolume = v }
            if let v = dict["cleanup_recordings"] as? Bool { c.cleanupRecordings = v }
            if let v = dict["debug"] as? Bool { c.debug = v }

            if let modelsDict = dict["models"] as? [String: Any] {
                var models: [String: WhispererConfig.ModelRange?] = [:]
                for (name, value) in modelsDict {
                    if let arr = value as? [Any], arr.count == 2,
                       let min = (arr[0] as? NSNumber)?.doubleValue,
                       let max = (arr[1] as? NSNumber)?.doubleValue {
                        models[name] = WhispererConfig.ModelRange(min: min, max: max)
                    } else {
                        models[name] = nil  // manual-only
                    }
                }
                c.models = models
            }

            self.config = c
            NSLog("[Whisperer] Config loaded from %@", configPath)

        } catch {
            NSLog("[Whisperer] Failed to load config: %@ — using defaults", error.localizedDescription)
            config = WhispererConfig.default
        }
    }

    // MARK: - Save

    func saveConfig() {
        // Build a dict matching Python's YAML output format
        var dict: [String: Any] = [:]
        dict["whispercpp_folder"] = config.whispercppFolder
        dict["prompt"] = config.prompt

        // Models as dict of [min, max] lists or null
        var modelsDict: [String: Any] = [:]
        // Sort models to maintain consistent order
        let sortedModels = config.models.sorted { a, b in
            // Preserve insertion order roughly: tiny, base, small, large
            let order = ["tiny.en", "base.en", "small.en", "large-v3-turbo"]
            let ai = order.firstIndex(of: a.key) ?? order.count
            let bi = order.firstIndex(of: b.key) ?? order.count
            return ai < bi
        }
        for (name, range) in sortedModels {
            if let r = range {
                modelsDict[name] = [r.min, r.max]
            } else {
                modelsDict[name] = NSNull()
            }
        }
        dict["models"] = modelsDict
        dict["enable_beeps"] = config.enableBeeps
        dict["enable_start_sound"] = config.enableStartSound
        dict["enable_stop_sound"] = config.enableStopSound
        dict["enable_error_sound"] = config.enableErrorSound
        dict["sound_volume"] = config.soundVolume
        dict["cleanup_recordings"] = config.cleanupRecordings
        dict["debug"] = config.debug

        do {
            try FileManager.default.createDirectory(
                atPath: configDir, withIntermediateDirectories: true)

            // Use Yams to produce YAML compatible with PyYAML's default_flow_style=False
            let yamlString = try Yams.dump(object: dict, allowUnicode: true)
            try yamlString.write(toFile: configPath, atomically: true, encoding: .utf8)

            NSLog("[Whisperer] Config saved to %@", configPath)
        } catch {
            NSLog("[Whisperer] Failed to save config: %@", error.localizedDescription)
        }
    }

    // MARK: - Python Detection

    /// Find a python3 interpreter that has pyyaml installed by probing each candidate.
    ///
    /// Searches two sources:
    /// 1. The process's inherited PATH (has conda/venv when launched from terminal)
    /// 2. Well-known locations (covers Finder launches where PATH is minimal)
    ///
    /// Each candidate is tested by running `python3 -c "import yaml"`.
    /// The first one that succeeds is returned.
    static func findPython() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        var candidates: [String] = []

        func addCandidate(_ path: String) {
            if !candidates.contains(path) && FileManager.default.isExecutableFile(atPath: path) {
                candidates.append(path)
            }
        }

        // 1. Walk the inherited PATH
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.split(separator: ":") {
                addCandidate("\(dir)/python3")
                addCandidate("\(dir)/python")
            }
        }

        // 2. Well-known locations (covers GUI launches where PATH is minimal)
        let knownPaths = [
            // Conda (default install locations)
            "\(home)/miniconda3/bin/python3",
            "\(home)/miniconda3/bin/python",
            "\(home)/anaconda3/bin/python3",
            "\(home)/anaconda3/bin/python",
            "\(home)/miniforge3/bin/python3",
            "\(home)/miniforge3/bin/python",
            // Homebrew
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            // pyenv
            "\(home)/.pyenv/shims/python3",
            "\(home)/.pyenv/shims/python",
            // User local
            "\(home)/.local/bin/python3",
            // System
            "/usr/bin/python3",
        ]
        for path in knownPaths {
            addCandidate(path)
        }

        NSLog("[Whisperer] Python candidates (%d): %@",
              candidates.count, candidates.joined(separator: ", "))

        // Test each candidate: can it import yaml?
        for python in candidates {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: python)
            proc.arguments = ["-c", "import yaml"]
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            do {
                try proc.run()
                proc.waitUntilExit()
                if proc.terminationStatus == 0 {
                    NSLog("[Whisperer] Found working Python with yaml: %@", python)
                    return python
                } else {
                    NSLog("[Whisperer] %@ cannot import yaml (exit %d)", python, proc.terminationStatus)
                }
            } catch {
                NSLog("[Whisperer] %@ failed to launch: %@", python, error.localizedDescription)
            }
        }

        // Nothing has yaml — return first candidate and let error propagate clearly
        NSLog("[Whisperer] WARNING: No Python with pyyaml found. Install with: pip install pyyaml")
        return candidates.first ?? "/usr/bin/python3"
    }
}
