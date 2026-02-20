import SwiftUI

struct PreferencesHotkeysView: View {
    @State private var config = HotkeyConfig.load()

    var body: some View {
        Form {
            Section(header: Text("Hotkey Roles").font(.headline)) {
                Text("Assign a role to each modifier key. You need exactly 2 trigger keys, 1 large model key, and 1 punctuation key.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)

                ForEach(ModifierKey.allCases, id: \.self) { key in
                    HStack {
                        Text(key.displayName)
                            .frame(width: 120, alignment: .leading)
                        Picker("", selection: bindingForKey(key)) {
                            ForEach(ModifierRole.allCases, id: \.self) { role in
                                Text(role.displayName).tag(role)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 280)
                    }
                }

                // Validation status
                HStack(spacing: 6) {
                    if config.isValid {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(config.validationMessage)
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(config.validationMessage)
                            .foregroundColor(.orange)
                    }
                }
                .font(.caption)
                .padding(.top, 4)
            }

            Section(header: Text("Current Bindings").font(.headline)) {
                hotkeyRow(
                    label: "Record & Transcribe",
                    binding: config.triggerKeys.map(\.displayName).sorted().joined(separator: " + ")
                )
                hotkeyRow(
                    label: "Use Large Model",
                    binding: config.largeModelKey.map { "+ \($0.displayName)" } ?? "Not assigned"
                )
                hotkeyRow(
                    label: "Keep Punctuation",
                    binding: config.punctuationKey.map { "+ \($0.displayName)" } ?? "Not assigned"
                )
                hotkeyRow(
                    label: "Stop Recording",
                    binding: "Release either trigger key"
                )
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
        .padding()
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

    private func hotkeyRow(label: String, binding: String) -> some View {
        HStack {
            Text(label)
                .frame(width: 180, alignment: .leading)
            Text(binding)
                .foregroundColor(.secondary)
                .font(.system(.body, design: .monospaced))
            Spacer()
        }
    }
}
