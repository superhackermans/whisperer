import SwiftUI

struct PreferencesAdvancedView: View {
    @ObservedObject var configManager: ConfigManager
    var launchAtLoginManager: LaunchAtLoginManager

    @State private var pythonPathText: String = ""
    @State private var launchAtLogin: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Launch") {
                    Toggle("Open at Login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { newValue in
                            if newValue {
                                launchAtLoginManager.enable()
                            } else {
                                launchAtLoginManager.disable()
                            }
                        }
                }

                Section {
                    HStack {
                        TextField("Python interpreter path", text: $pythonPathText)
                            .textFieldStyle(.roundedBorder)
                        Button("Detect") {
                            pythonPathText = ConfigManager.findPython()
                        }
                    }
                    LabeledContent("Current") {
                        Text(configManager.pythonPath)
                            .foregroundColor(.secondary)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } header: {
                    Text("Python")
                }

                Section("Log File") {
                    let logPath = "~/whisperer_debug.log"
                    HStack {
                        Text(logPath)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Reveal in Finder") {
                            let expanded = NSString(string: logPath).expandingTildeInPath
                            NSWorkspace.shared.selectFile(expanded, inFileViewerRootedAtPath: "")
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Apply") {
                    if !pythonPathText.isEmpty {
                        configManager.pythonPath = pythonPathText
                    }
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
        .onAppear {
            pythonPathText = configManager.pythonPath
            launchAtLogin = launchAtLoginManager.isEnabled
        }
    }
}
