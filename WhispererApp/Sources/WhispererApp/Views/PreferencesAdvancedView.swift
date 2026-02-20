import SwiftUI

struct PreferencesAdvancedView: View {
    @ObservedObject var configManager: ConfigManager
    var launchAtLoginManager: LaunchAtLoginManager

    @State private var pythonPathText: String = ""
    @State private var launchAtLogin: Bool = false

    var body: some View {
        Form {
            Section(header: Text("Launch").font(.headline)) {
                Toggle("Open at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        if newValue {
                            launchAtLoginManager.enable()
                        } else {
                            launchAtLoginManager.disable()
                        }
                    }
            }

            Section(header: Text("Python").font(.headline)) {
                HStack {
                    TextField("Python interpreter:", text: $pythonPathText)
                        .textFieldStyle(.roundedBorder)
                    Button("Detect") {
                        pythonPathText = ConfigManager.findPython()
                    }
                }
                Text("Current: \(configManager.pythonPath)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(header: Text("Log File").font(.headline)) {
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
                .keyboardShortcut(.return)
            }
        }
        .padding()
        .onAppear {
            pythonPathText = configManager.pythonPath
            launchAtLogin = launchAtLoginManager.isEnabled
        }
    }
}
