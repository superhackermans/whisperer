import SwiftUI

/// Helper for menu bar status text formatting.
struct MenuBarHelper {
    static func statusText(for status: WhispererStatus) -> String {
        switch status {
        case .idle:
            return "Idle"
        case .recording:
            return "Recording..."
        case .transcribing:
            return "Transcribing..."
        case .error(let msg):
            return "Error: \(msg)"
        }
    }

    static func iconName(for status: WhispererStatus) -> String {
        let defaults = UserDefaults.standard
        switch status {
        case .idle:
            return defaults.string(forKey: AppDelegate.iconIdleKey) ?? AppDelegate.defaultIconIdle
        case .recording:
            return defaults.string(forKey: AppDelegate.iconRecordingKey) ?? AppDelegate.defaultIconRecording
        case .transcribing:
            return defaults.string(forKey: AppDelegate.iconTranscribingKey) ?? AppDelegate.defaultIconTranscribing
        case .error:
            return defaults.string(forKey: AppDelegate.iconErrorKey) ?? AppDelegate.defaultIconError
        }
    }
}
