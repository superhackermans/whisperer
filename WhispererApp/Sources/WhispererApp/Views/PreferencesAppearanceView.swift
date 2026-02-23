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
        Form {
            Section("Notifications") {
                Toggle("Show notification when transcription completes", isOn: $notificationsEnabled)
            }

            Section("Sounds") {
                Toggle("Enable sound effects", isOn: $configManager.config.enableBeeps)

                if configManager.config.enableBeeps {
                    Toggle("Start recording sound", isOn: $configManager.config.enableStartSound)
                        .padding(.leading, 20)
                    Toggle("Stop recording sound", isOn: $configManager.config.enableStopSound)
                        .padding(.leading, 20)
                    Toggle("Error sound", isOn: $configManager.config.enableErrorSound)
                        .padding(.leading, 20)

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
                            .monospacedDigit()
                    }
                }

                Button("Apply Sound Settings") {
                    configManager.saveConfig()
                    if let delegate = NSApp.delegate as? AppDelegate {
                        delegate.restartSubprocess()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            Section {
                iconPickerRow(label: "Idle", selection: $iconIdle, options: Self.idleOptions)
                iconPickerRow(label: "Recording", selection: $iconRecording, options: Self.recordingOptions)
                iconPickerRow(label: "Transcribing", selection: $iconTranscribing, options: Self.transcribingOptions)
                iconPickerRow(label: "Error", selection: $iconError, options: Self.errorOptions)

                Button("Reset Icons to Defaults") {
                    iconIdle = AppDelegate.defaultIconIdle
                    iconRecording = AppDelegate.defaultIconRecording
                    iconTranscribing = AppDelegate.defaultIconTranscribing
                    iconError = AppDelegate.defaultIconError
                    notifyIconChange()
                }
            } header: {
                Text("Menu Bar Icons")
            } footer: {
                Text("Choose an icon for each app state. Changes apply immediately.")
            }
        }
        .formStyle(.grouped)
    }

    private func iconPickerRow(label: String, selection: Binding<String>, options: [String]) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .frame(width: 100, alignment: .leading)

            HStack(spacing: 8) {
                ForEach(options, id: \.self) { symbol in
                    Button(action: {
                        selection.wrappedValue = symbol
                        notifyIconChange()
                    }) {
                        Image(systemName: symbol)
                            .font(.title3)
                            .frame(width: 36, height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selection.wrappedValue == symbol ? Color.accentColor.opacity(0.15) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
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
