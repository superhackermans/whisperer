import AppKit
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

        registerIconDefaults()
        setupStatusItem()
        setupSubprocess()
        setupHotkeyManager()
        setupNotificationObservers()
        observeState()

        // Hide Dock icon after status item is set up
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
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
        // Stop old hotkey manager and create new one with updated config
        hotkeyManager?.stop()
        hotkeyManager = nil
        setupHotkeyManager()
    }

    // MARK: - Subprocess

    private func setupSubprocess() {
        subprocessManager = PythonSubprocessManager(appState: appState, configManager: configManager)
        subprocessManager.start()
    }

    // MARK: - Hotkey Manager

    private func setupHotkeyManager() {
        let config = HotkeyConfig.load()
        let manager = HotkeyManager(appState: appState, config: config) { [weak self] command in
            self?.subprocessManager.sendCommand(command)
        }

        if !manager.start() {
            DispatchQueue.main.async { [weak self] in
                self?.showAccessibilityAlert()
            }
        }

        hotkeyManager = manager
    }

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "Whisperer needs Accessibility access to detect global hotkeys. Please grant access in System Settings > Privacy & Security > Accessibility."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
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
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 500),
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

    @objc private func quitApp() {
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
