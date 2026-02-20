import SwiftUI

struct PreferencesAppearanceView: View {
    @ObservedObject var configManager: ConfigManager
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @AppStorage(AppDelegate.iconIdleKey) private var iconIdle = AppDelegate.defaultIconIdle
    @AppStorage(AppDelegate.iconRecordingKey) private var iconRecording = AppDelegate.defaultIconRecording
    @AppStorage(AppDelegate.iconTranscribingKey) private var iconTranscribing = AppDelegate.defaultIconTranscribing
    @AppStorage(AppDelegate.iconErrorKey) private var iconError = AppDelegate.defaultIconError

    private static let idleOptions = ["waveform", "mic", "waveform.circle", "headphones", "speaker.wave.2"]
    private static let recordingOptions = ["record.circle.fill", "waveform.circle.fill", "mic.fill", "mic.circle.fill"]
    private static let transcribingOptions = ["ellipsis.circle", "waveform.badge.plus", "text.bubble", "hourglass"]
    private static let errorOptions = ["exclamationmark.triangle", "xmark.circle", "waveform.badge.exclamationmark", "mic.slash"]

    var body: some View {
        ScrollView {
            Form {
                Section(header: Text("Notifications").font(.headline)) {
                    Toggle("Show notification when transcription completes", isOn: $notificationsEnabled)
                }

                Section(header: Text("Sounds").font(.headline)) {
                    Toggle("Enable sound effects", isOn: $configManager.config.enableBeeps)

                    if configManager.config.enableBeeps {
                        Toggle("Start recording sound", isOn: $configManager.config.enableStartSound)
                            .padding(.leading, 16)
                        Toggle("Stop recording sound", isOn: $configManager.config.enableStopSound)
                            .padding(.leading, 16)
                        Toggle("Error sound", isOn: $configManager.config.enableErrorSound)
                            .padding(.leading, 16)

                        HStack {
                            Text("Volume")
                            Slider(
                                value: Binding(
                                    get: { Double(configManager.config.soundVolume) },
                                    set: { configManager.config.soundVolume = Int($0) }
                                ),
                                in: 0...100,
                                step: 5
                            )
                            Text("\(configManager.config.soundVolume)%")
                                .frame(width: 40, alignment: .trailing)
                                .font(.system(.body, design: .monospaced))
                        }
                    }

                    Button("Apply Sound Settings") {
                        configManager.saveConfig()
                        if let delegate = NSApp.delegate as? AppDelegate {
                            delegate.restartSubprocess()
                        }
                    }
                    .font(.caption)
                }

                Section(header: Text("Menu Bar Icons").font(.headline)) {
                    Text("Choose an icon for each app state:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    iconPickerRow(label: "Idle", selection: $iconIdle, options: Self.idleOptions)
                    iconPickerRow(label: "Recording", selection: $iconRecording, options: Self.recordingOptions)
                    iconPickerRow(label: "Transcribing", selection: $iconTranscribing, options: Self.transcribingOptions)
                    iconPickerRow(label: "Error", selection: $iconError, options: Self.errorOptions)
                }

                Section {
                    Button("Reset Icons to Defaults") {
                        iconIdle = AppDelegate.defaultIconIdle
                        iconRecording = AppDelegate.defaultIconRecording
                        iconTranscribing = AppDelegate.defaultIconTranscribing
                        iconError = AppDelegate.defaultIconError
                        notifyIconChange()
                    }
                }
            }
            .padding()
        }
    }

    private func iconPickerRow(label: String, selection: Binding<String>, options: [String]) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(width: 90, alignment: .leading)

            HStack(spacing: 6) {
                ForEach(options, id: \.self) { symbol in
                    Button(action: {
                        selection.wrappedValue = symbol
                        notifyIconChange()
                    }) {
                        Image(systemName: symbol)
                            .font(.title3)
                            .frame(width: 32, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(selection.wrappedValue == symbol ? Color.accentColor.opacity(0.2) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(selection.wrappedValue == symbol ? Color.accentColor : Color.clear, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()
        }
    }

    private func notifyIconChange() {
        NotificationCenter.default.post(name: Notification.Name("IconConfigDidChange"), object: nil)
    }
}
