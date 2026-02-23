import SwiftUI

struct PreferencesGeneralView: View {
    @ObservedObject var configManager: ConfigManager

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Whisper.cpp") {
                    HStack {
                        TextField("Path (auto-detected if empty)", text: $configManager.config.whispercppFolder)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse...") {
                            browseForFolder()
                        }
                    }

                    TextField("Transcription prompt", text: $configManager.config.prompt)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Options") {
                    Toggle("Auto-delete recordings after transcription", isOn: $configManager.config.cleanupRecordings)
                    Toggle("Debug logging", isOn: $configManager.config.debug)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Apply") {
                    configManager.saveConfig()
                    if let delegate = NSApp.delegate as? AppDelegate {
                        delegate.restartSubprocess()
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
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
