import ApplicationServices
import AppKit
import AVFoundation
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var cancellables = Set<AnyCancellable>()
    private var preferencesWindow: NSWindow?

    let appState = AppState()
    let configManager = ConfigManager()
    let launchAtLoginManager = LaunchAtLoginManager()
    private(set) var hotkeyManager: HotkeyManager?
    private var subprocessManager: PythonSubprocessManager!
    private var accessibilityRetryTimer: Timer?
    private var microphoneRetryTimer: Timer?
    private var bridgeReadyWatchdog: Timer?

    // MARK: - Icon UserDefaults Keys

    static let iconIdleKey = "iconIdle"
    static let iconRecordingKey = "iconRecording"
    static let iconTranscribingKey = "iconTranscribing"
    static let iconErrorKey = "iconError"

    static let defaultIconIdle = "waveform"
    static let defaultIconRecording = "record.circle.fill"
    static let defaultIconTranscribing = "ellipsis.circle"
    static let defaultIconError = "exclamationmark.triangle"

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        signal(SIGPIPE, SIG_IGN)
        DiagnosticLog.log("applicationDidFinishLaunching started")

        registerIconDefaults()
        DiagnosticLog.log("Icon defaults registered")

        setupStatusItem()
        DiagnosticLog.log("Status item created")

        setupSubprocess()
        DiagnosticLog.log("Subprocess setup initiated")

        setupNotificationObservers()
        observeState()

        checkMicrophonePermission()

        let hotkeyOK = setupHotkeyManager()
        DiagnosticLog.log("Hotkey manager started: \(hotkeyOK ? "SUCCESS" : "FAILED (Accessibility denied)")")

        if hotkeyOK {
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(.accessory)
                DiagnosticLog.log("Switched to .accessory (menu bar only)")
            }
        } else {
            // Show macOS's native Accessibility prompt and poll until granted
            promptForAccessibilityAndRetry()
        }

        // Watchdog: if the Python bridge hasn't sent BRIDGE_READY within 15 seconds,
        // show a visible alert so the user knows something is wrong.
        bridgeReadyWatchdog = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.bridgeReadyWatchdog = nil
            if !self.appState.isSubprocessRunning || self.appState.status != .idle {
                DiagnosticLog.log("WATCHDOG: Bridge not ready after 15s — showing alert")
                DiagnosticLog.log("  isSubprocessRunning=\(self.appState.isSubprocessRunning)")
                DiagnosticLog.log("  status=\(self.appState.status)")
                DiagnosticLog.log("  hotkeysActive=\(self.appState.hotkeysActive)")
                self.showStartupFailureAlert()
            }
        }

        DiagnosticLog.log("applicationDidFinishLaunching complete")
    }

    func applicationWillTerminate(_ notification: Notification) {
        accessibilityRetryTimer?.invalidate()
        microphoneRetryTimer?.invalidate()
        bridgeReadyWatchdog?.invalidate()
        NSStatusBar.system.removeStatusItem(statusItem)
        hotkeyManager?.stop()
        subprocessManager?.stop()
    }

    // MARK: - Icon Defaults

    private func registerIconDefaults() {
        UserDefaults.standard.register(defaults: [
            AppDelegate.iconIdleKey: AppDelegate.defaultIconIdle,
            AppDelegate.iconRecordingKey: AppDelegate.defaultIconRecording,
            AppDelegate.iconTranscribingKey: AppDelegate.defaultIconTranscribing,
            AppDelegate.iconErrorKey: AppDelegate.defaultIconError,
        ])
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            let iconName = UserDefaults.standard.string(forKey: AppDelegate.iconIdleKey) ?? AppDelegate.defaultIconIdle
            if let img = NSImage(systemSymbolName: iconName, accessibilityDescription: "Whisperer") {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "W"
            }
        }

        rebuildMenu()
    }

    func rebuildMenu() {
        let menu = NSMenu()

        let statusString: String
        switch appState.status {
        case .idle:
            statusString = "Status: Idle"
        case .recording:
            statusString = "Status: Recording..."
        case .transcribing:
            statusString = "Status: Transcribing..."
        case .error(let msg):
            statusString = "Status: Error — \(msg)"
        }
        let statusItem = NSMenuItem(title: statusString, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        let modelName = appState.currentModel ?? "auto"
        let modelItem = NSMenuItem(title: "Current Model: \(modelName)", action: nil, keyEquivalent: "")
        modelItem.isEnabled = false
        menu.addItem(modelItem)

        if appState.hotkeysActive {
            let hotkeyItem = NSMenuItem(title: "Hotkeys: Active", action: nil, keyEquivalent: "")
            hotkeyItem.isEnabled = false
            menu.addItem(hotkeyItem)
        } else {
            let hotkeyItem = NSMenuItem(title: "Hotkeys: Inactive (needs Accessibility)", action: nil, keyEquivalent: "")
            hotkeyItem.isEnabled = false
            menu.addItem(hotkeyItem)

            let grantItem = NSMenuItem(title: "Grant Accessibility Permission...", action: #selector(grantAccessibility), keyEquivalent: "")
            grantItem.target = self
            menu.addItem(grantItem)

            let inputMonItem = NSMenuItem(title: "Grant Input Monitoring Permission...", action: #selector(grantInputMonitoring), keyEquivalent: "")
            inputMonItem.target = self
            menu.addItem(inputMonItem)
        }

        if !appState.microphoneGranted {
            let micItem = NSMenuItem(title: "Microphone: Denied", action: nil, keyEquivalent: "")
            micItem.isEnabled = false
            menu.addItem(micItem)

            let grantMicItem = NSMenuItem(title: "Grant Microphone Permission...", action: #selector(grantMicrophone), keyEquivalent: "")
            grantMicItem.target = self
            menu.addItem(grantMicItem)
        }

        menu.addItem(NSMenuItem.separator())

        let startItem = NSMenuItem(title: "Start Recording", action: #selector(startRecording), keyEquivalent: "")
        startItem.target = self
        startItem.isEnabled = appState.status == .idle
        menu.addItem(startItem)

        let stopItem = NSMenuItem(title: "Stop Recording", action: #selector(stopRecording), keyEquivalent: "")
        stopItem.target = self
        stopItem.isEnabled = appState.status == .recording
        menu.addItem(stopItem)

        menu.addItem(NSMenuItem.separator())

        let prefsItem = NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        let loginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = launchAtLoginManager.isEnabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem.separator())

        let logItem = NSMenuItem(title: "Show Diagnostic Log", action: #selector(showDiagnosticLog), keyEquivalent: "")
        logItem.target = self
        menu.addItem(logItem)

        let quitItem = NSMenuItem(title: "Quit Whisperer", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        self.statusItem.menu = menu
    }

    // MARK: - State Observation

    private func observeState() {
        appState.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.updateIcon(for: status)
                self?.rebuildMenu()

                // Cancel the watchdog when bridge reports idle (BRIDGE_READY received)
                if status == .idle, self?.bridgeReadyWatchdog != nil {
                    DiagnosticLog.log("Bridge ready — cancelling watchdog")
                    self?.bridgeReadyWatchdog?.invalidate()
                    self?.bridgeReadyWatchdog = nil
                }
            }
            .store(in: &cancellables)

        appState.$microphoneGranted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)
    }

    private func updateIcon(for status: WhispererStatus) {
        guard let button = statusItem.button else { return }
        let defaults = UserDefaults.standard
        let symbolName: String
        switch status {
        case .idle:
            symbolName = defaults.string(forKey: AppDelegate.iconIdleKey) ?? AppDelegate.defaultIconIdle
        case .recording:
            symbolName = defaults.string(forKey: AppDelegate.iconRecordingKey) ?? AppDelegate.defaultIconRecording
        case .transcribing:
            symbolName = defaults.string(forKey: AppDelegate.iconTranscribingKey) ?? AppDelegate.defaultIconTranscribing
        case .error:
            symbolName = defaults.string(forKey: AppDelegate.iconErrorKey) ?? AppDelegate.defaultIconError
        }
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Whisperer") {
            image.isTemplate = true
            button.image = image
            button.title = ""
        }
    }

    // MARK: - Notification Observers

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleIconConfigChange),
            name: Notification.Name("IconConfigDidChange"),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHotkeyConfigChange),
            name: Notification.Name("HotkeyConfigDidChange"),
            object: nil
        )
    }

    @objc private func handleIconConfigChange() {
        updateIcon(for: appState.status)
    }

    @objc private func handleHotkeyConfigChange() {
        let ok = setupHotkeyManager()
        if !ok {
            promptForAccessibilityAndRetry()
        }
    }

    @objc private func grantMicrophone() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
        if microphoneRetryTimer == nil {
            startMicrophoneRetryTimer()
        }
    }

    @objc private func grantInputMonitoring() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func grantAccessibility() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options = [key: kCFBooleanTrue!] as CFDictionary
        AXIsProcessTrustedWithOptions(options)

        // Start retry polling if not already running
        if accessibilityRetryTimer == nil {
            promptForAccessibilityAndRetry()
        }
    }

    // MARK: - Subprocess

    private func setupSubprocess() {
        subprocessManager = PythonSubprocessManager(appState: appState, configManager: configManager)
        subprocessManager.start()
    }

    // MARK: - Hotkey Manager

    /// Returns true if hotkeys started successfully, false if Accessibility denied.
    @discardableResult
    private func setupHotkeyManager() -> Bool {
        hotkeyManager?.stop()
        hotkeyManager = nil

        let config = HotkeyConfig.load()
        let manager = HotkeyManager(appState: appState, config: config) { [weak self] command in
            self?.subprocessManager.sendCommand(command)
        }

        let ok = manager.start()
        hotkeyManager = manager

        appState.hotkeysActive = ok
        rebuildMenu()

        return ok
    }

    /// Show the macOS native Accessibility prompt and poll until permission is granted.
    private func promptForAccessibilityAndRetry() {
        DiagnosticLog.log("Accessibility denied — showing system prompt and starting retry timer")

        // Trigger macOS's native "allow Accessibility" dialog
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options = [key: kCFBooleanTrue!] as CFDictionary
        AXIsProcessTrustedWithOptions(options)

        // Poll every 2 seconds; auto-enable hotkeys once permission is granted.
        accessibilityRetryTimer?.invalidate()
        accessibilityRetryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            if AXIsProcessTrusted() {
                DiagnosticLog.log("Accessibility permission granted — enabling hotkeys")
                timer.invalidate()
                self.accessibilityRetryTimer = nil
                let ok = self.setupHotkeyManager()
                if ok {
                    DispatchQueue.main.async {
                        NSApp.setActivationPolicy(.accessory)
                    }
                }
            }
        }
    }

    // MARK: - Microphone Permission

    private func checkMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            DiagnosticLog.log("Microphone permission: authorized")
            appState.microphoneGranted = true
        case .notDetermined:
            DiagnosticLog.log("Microphone permission: not determined — requesting")
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.appState.microphoneGranted = granted
                    DiagnosticLog.log("Microphone permission request result: \(granted)")
                    self?.rebuildMenu()
                    if !granted {
                        self?.startMicrophoneRetryTimer()
                    }
                }
            }
        case .denied, .restricted:
            DiagnosticLog.log("Microphone permission: denied/restricted")
            appState.microphoneGranted = false
            startMicrophoneRetryTimer()
        @unknown default:
            break
        }
    }

    private func startMicrophoneRetryTimer() {
        microphoneRetryTimer?.invalidate()
        microphoneRetryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
                DiagnosticLog.log("Microphone permission granted — updating state")
                timer.invalidate()
                self.microphoneRetryTimer = nil
                self.appState.microphoneGranted = true
                self.rebuildMenu()
            }
        }
    }

    // MARK: - Startup Failure Alert

    private func showStartupFailureAlert() {
        // Bring app to front so alert is visible
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Whisperer Failed to Start"

        var details: [String] = []
        if !appState.hotkeysActive {
            details.append("Hotkeys: NOT WORKING (Accessibility permission needed)")
        }
        if !appState.microphoneGranted {
            details.append("Microphone: DENIED (permission needed)")
        }
        if !appState.isSubprocessRunning {
            details.append("Python bridge: NOT RUNNING")
        }
        if case .error(let msg) = appState.status {
            details.append("Error: \(msg)")
        }

        let logPath = DiagnosticLog.logPath
        alert.informativeText = details.joined(separator: "\n") +
            "\n\nDiagnostic log written to:\n\(logPath)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Log File")
        alert.addButton(withTitle: "OK")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(fileURLWithPath: logPath))
        }

        // Now safe to hide from Dock if hotkeys are working
        if appState.hotkeysActive {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - Actions

    @objc private func startRecording() {
        subprocessManager.sendCommand("start")
    }

    @objc private func stopRecording() {
        subprocessManager.sendCommand("stop")
    }

    @objc private func openPreferences() {
        if let window = preferencesWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let prefsView = PreferencesWindow(
            appState: appState,
            configManager: configManager,
            hotkeyManager: hotkeyManager,
            launchAtLoginManager: launchAtLoginManager
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Whisperer Preferences"
        window.contentView = NSHostingView(rootView: prefsView)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)

        self.preferencesWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        if launchAtLoginManager.isEnabled {
            launchAtLoginManager.disable()
        } else {
            launchAtLoginManager.enable()
        }
        rebuildMenu()
    }

    @objc private func showDiagnosticLog() {
        NSWorkspace.shared.open(URL(fileURLWithPath: DiagnosticLog.logPath))
    }

    @objc private func quitApp() {
        accessibilityRetryTimer?.invalidate()
        microphoneRetryTimer?.invalidate()
        bridgeReadyWatchdog?.invalidate()
        NSStatusBar.system.removeStatusItem(statusItem)
        hotkeyManager?.stop()
        subprocessManager?.stop()
        NSApp.terminate(nil)
    }

    // MARK: - Public API for config changes

    func restartSubprocess() {
        subprocessManager?.stop()
        subprocessManager = PythonSubprocessManager(appState: appState, configManager: configManager)
        subprocessManager.start()
    }
}
