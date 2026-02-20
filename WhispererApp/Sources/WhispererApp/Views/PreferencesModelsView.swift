import SwiftUI

struct PreferencesModelsView: View {
    @ObservedObject var configManager: ConfigManager

    // Ordered model names for display
    private let modelOrder = ["tiny.en", "base.en", "small.en", "large-v3-turbo"]

    var body: some View {
        Form {
            Section(header: Text("Model Duration Ranges").font(.headline)) {
                Text("Each model handles recordings within its duration range (seconds). \"large-v3-turbo\" is always manual-only (triggered via Left Cmd modifier).")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ForEach(modelOrder, id: \.self) { name in
                    modelRow(name: name)
                }
            }

            HStack {
                Spacer()
                Button("Apply") {
                    configManager.saveConfig()
                    if let delegate = NSApp.delegate as? AppDelegate {
                        delegate.restartSubprocess()
                    }
                }
                .keyboardShortcut(.return)
            }
        }
        .padding()
    }

    @ViewBuilder
    private func modelRow(name: String) -> some View {
        let isManualOnly = (name == "large-v3-turbo")

        HStack {
            Text(name)
                .frame(width: 130, alignment: .leading)
                .fontWeight(.medium)

            if isManualOnly {
                Text("Manual only (Left Cmd + hotkey)")
                    .foregroundColor(.secondary)
                    .font(.caption)
                Spacer()
            } else {
                let range = configManager.config.models[name] ?? nil

                Text("Min:")
                    .foregroundColor(.secondary)
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

                Text("Max:")
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

                Text("s")
                    .foregroundColor(.secondary)
            }
        }
    }
}
