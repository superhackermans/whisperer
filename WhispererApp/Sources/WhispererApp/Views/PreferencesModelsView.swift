import SwiftUI

struct PreferencesModelsView: View {
    @ObservedObject var configManager: ConfigManager

    private let modelOrder = ["tiny.en", "base.en", "small.en", "large-v3-turbo"]

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    ForEach(modelOrder, id: \.self) { name in
                        modelRow(name: name)
                    }
                } header: {
                    Text("Duration Ranges")
                } footer: {
                    Text("Models are auto-selected by recording duration. large-v3-turbo is manual-only (Left Cmd + hotkey).")
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

    @ViewBuilder
    private func modelRow(name: String) -> some View {
        let isManualOnly = (name == "large-v3-turbo")

        HStack {
            Text(name)
                .fontWeight(.medium)
                .frame(minWidth: 120, alignment: .leading)

            Spacer()

            if isManualOnly {
                Text("Manual only")
                    .foregroundColor(.secondary)
            } else {
                let range = configManager.config.models[name] ?? nil

                HStack(spacing: 6) {
                    TextField("", value: Binding(
                        get: { range?.min ?? 0 },
                        set: { newVal in
                            var r = range ?? WhispererConfig.ModelRange(min: 0, max: 999999)
                            r.min = newVal
                            configManager.config.models[name] = r
                        }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)

                    Text("to")
                        .foregroundColor(.secondary)

                    TextField("", value: Binding(
                        get: { range?.max ?? 999999 },
                        set: { newVal in
                            var r = range ?? WhispererConfig.ModelRange(min: 0, max: 999999)
                            r.max = newVal
                            configManager.config.models[name] = r
                        }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)

                    Text("sec")
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
