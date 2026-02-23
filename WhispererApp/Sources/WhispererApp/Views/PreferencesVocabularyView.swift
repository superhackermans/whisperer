import SwiftUI

struct PreferencesVocabularyView: View {
    @ObservedObject var configManager: ConfigManager

    @State private var newFrom: String = ""
    @State private var newTo: String = ""

    private var sortedKeys: [String] {
        configManager.config.customWords.keys.sorted { $0.lowercased() < $1.lowercased() }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    HStack(spacing: 8) {
                        TextField("Mistranscribed", text: $newFrom)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { addWord() }
                        Image(systemName: "arrow.right")
                            .foregroundColor(.secondary)
                        TextField("Correct", text: $newTo)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { addWord() }
                        Button {
                            addWord()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.borderless)
                        .disabled(newFrom.trimmingCharacters(in: .whitespaces).isEmpty
                                  || newTo.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Add Word")
                } footer: {
                    Text("Matching is case-insensitive. The replacement preserves the case you enter.")
                }

                Section("Custom Words") {
                    if sortedKeys.isEmpty {
                        Text("No custom words defined.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(sortedKeys, id: \.self) { key in
                            HStack {
                                Text(key)
                                    .frame(minWidth: 80, alignment: .leading)
                                Image(systemName: "arrow.right")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                                Text(configManager.config.customWords[key] ?? "")
                                    .frame(minWidth: 80, alignment: .leading)
                                Spacer()
                                Button {
                                    configManager.config.customWords.removeValue(forKey: key)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
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

    private func addWord() {
        let from = newFrom.trimmingCharacters(in: .whitespaces)
        let to = newTo.trimmingCharacters(in: .whitespaces)
        guard !from.isEmpty, !to.isEmpty else { return }
        configManager.config.customWords[from] = to
        newFrom = ""
        newTo = ""
    }
}
