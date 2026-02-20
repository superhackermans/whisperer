import SwiftUI

struct PreferencesGeneralView: View {
    @ObservedObject var configManager: ConfigManager

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("whisper.cpp path:", text: $configManager.config.whispercppFolder)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse...") {
                        browseForFolder()
                    }
                }

                TextField("Prompt:", text: $configManager.config.prompt)
                    .textFieldStyle(.roundedBorder)
            }

            Section {
                Toggle("Auto-delete recordings after transcription", isOn: $configManager.config.cleanupRecordings)
                Toggle("Debug logging", isOn: $configManager.config.debug)
            }

            HStack {
                Spacer()
                Button("Apply") {
                    configManager.saveConfig()
                    // Subprocess restart is handled by the AppDelegate observing config changes
                    if let delegate = NSApp.delegate as? AppDelegate {
                        delegate.restartSubprocess()
                    }
                }
                .keyboardShortcut(.return)
            }
        }
        .padding()
    }

    private func browseForFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select the whisper.cpp installation directory"
        panel.directoryURL = URL(fileURLWithPath: configManager.config.whispercppFolder.isEmpty
            ? FileManager.default.homeDirectoryForCurrentUser.path
            : configManager.config.whispercppFolder)

        if panel.runModal() == .OK, let url = panel.url {
            configManager.config.whispercppFolder = url.path
        }
    }
}
