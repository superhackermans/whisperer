import SwiftUI

struct PreferencesHotkeysView: View {
    @State private var config = HotkeyConfig.load()

    var body: some View {
        Form {
            Section {
                ForEach(ModifierKey.allCases, id: \.self) { key in
                    HStack {
                        Text(key.displayName)
                            .frame(width: 110, alignment: .leading)
                        Picker("", selection: bindingForKey(key)) {
                            ForEach(ModifierRole.allCases, id: \.self) { role in
                                Text(role.displayName).tag(role)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: config.isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(config.isValid ? .green : .orange)
                    Text(config.validationMessage)
                        .foregroundColor(config.isValid ? .green : .orange)
                }
                .font(.callout)
                .padding(.top, 4)
            } header: {
                Text("Key Roles")
            } footer: {
                Text("Assign a role to each modifier key. You need exactly 2 triggers, 1 large model key, and 1 punctuation key.")
            }

            Section("Current Bindings") {
                LabeledContent("Record & Transcribe") {
                    Text(config.triggerKeys.map(\.displayName).sorted().joined(separator: " + "))
                        .foregroundColor(.secondary)
                        .font(.system(.body, design: .monospaced))
                }
                LabeledContent("Use Large Model") {
                    Text(config.largeModelKey.map { "+ \($0.displayName)" } ?? "Not assigned")
                        .foregroundColor(.secondary)
                        .font(.system(.body, design: .monospaced))
                }
                LabeledContent("Keep Punctuation") {
                    Text(config.punctuationKey.map { "+ \($0.displayName)" } ?? "Not assigned")
                        .foregroundColor(.secondary)
                        .font(.system(.body, design: .monospaced))
                }
                LabeledContent("Stop Recording") {
                    Text("Release either trigger key")
                        .foregroundColor(.secondary)
                        .font(.system(.body, design: .monospaced))
                }
            }

            Section {
                HStack {
                    Button("Reset to Defaults") {
                        config = .default
                        saveAndNotify()
                    }

                    Spacer()

                    Button("Open Accessibility Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func bindingForKey(_ key: ModifierKey) -> Binding<ModifierRole> {
        Binding(
            get: { config.keyRoles[key] ?? .trigger },
            set: { newRole in
                config.keyRoles[key] = newRole
                saveAndNotify()
            }
        )
    }

    private func saveAndNotify() {
        guard config.isValid else { return }
        config.save()
        NotificationCenter.default.post(name: Notification.Name("HotkeyConfigDidChange"), object: nil)
    }
}
