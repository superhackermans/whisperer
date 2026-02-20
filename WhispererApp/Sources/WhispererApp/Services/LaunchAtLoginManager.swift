import Foundation
import ServiceManagement

/// Wraps SMAppService for launch-at-login (macOS 13+).
final class LaunchAtLoginManager {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func enable() {
        do {
            try SMAppService.mainApp.register()
            NSLog("[Whisperer] Launch at login enabled")
        } catch {
            NSLog("[Whisperer] Failed to enable launch at login: %@", error.localizedDescription)
        }
    }

    func disable() {
        do {
            try SMAppService.mainApp.unregister()
            NSLog("[Whisperer] Launch at login disabled")
        } catch {
            NSLog("[Whisperer] Failed to disable launch at login: %@", error.localizedDescription)
        }
    }
}
