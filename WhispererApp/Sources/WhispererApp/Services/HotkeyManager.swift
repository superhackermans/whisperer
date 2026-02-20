import CoreGraphics
import Foundation

/// Manages global hotkey detection via CGEvent tap.
///
/// Uses device-specific CGEventFlags bits (from IOKit/IOLLEvent.h) to
/// correctly distinguish left vs right modifier keys.
/// Hotkey roles are driven by HotkeyConfig rather than hardcoded.
final class HotkeyManager {
    private let appState: AppState
    private let onCommand: (String) -> Void
    private let config: HotkeyConfig

    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retainedSelf: Unmanaged<HotkeyManager>?

    // Track which modifier keys are currently held, keyed by ModifierKey
    private var keyStates: [ModifierKey: Bool] = [
        .rightCmd: false,
        .rightOption: false,
        .leftCmd: false,
        .leftOption: false,
    ]

    init(appState: AppState, config: HotkeyConfig = .default, onCommand: @escaping (String) -> Void) {
        self.appState = appState
        self.config = config
        self.onCommand = onCommand
        NSLog("[Whisperer-HK] Init with config: triggers=%@, large=%@, punct=%@",
              config.triggerKeys.map(\.displayName).joined(separator: "+"),
              config.largeModelKey?.displayName ?? "none",
              config.punctuationKey?.displayName ?? "none")
    }

    /// Start listening for global hotkeys. Returns false if Accessibility access is denied.
    func start() -> Bool {
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)

        // Use a closure wrapper via Unmanaged pointer
        let unmanaged = Unmanaged.passRetained(self)
        let selfPtr = unmanaged.toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: hotkeyCallback,
            userInfo: selfPtr
        ) else {
            NSLog("[Whisperer-HK] FAILED to create event tap — Accessibility permission likely denied")
            unmanaged.release()
            return false
        }

        retainedSelf = unmanaged

        eventTap = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        NSLog("[Whisperer-HK] Event tap installed successfully")
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }
        retainedSelf?.release()
        retainedSelf = nil
        NSLog("[Whisperer-HK] Stopped and cleaned up")
    }

    // MARK: - Event Handling

    fileprivate func handleFlagsChanged(flags: CGEventFlags) {
        let rawFlags = flags.rawValue
        let triggers = config.triggerKeys

        // Log raw flags and individual key bits
        let rCmd = rawFlags & ModifierKey.rightCmd.deviceFlagMask != 0
        let rOpt = rawFlags & ModifierKey.rightOption.deviceFlagMask != 0
        let lCmd = rawFlags & ModifierKey.leftCmd.deviceFlagMask != 0
        let lOpt = rawFlags & ModifierKey.leftOption.deviceFlagMask != 0

        NSLog("[Whisperer-HK] flagsChanged raw=0x%llX  RCmd=%d ROpt=%d LCmd=%d LOpt=%d",
              rawFlags, rCmd ? 1 : 0, rOpt ? 1 : 0, lCmd ? 1 : 0, lOpt ? 1 : 0)

        // Save previous state for each trigger key
        var wasTriggerDown: [ModifierKey: Bool] = [:]
        for key in triggers {
            wasTriggerDown[key] = keyStates[key] ?? false
        }

        // Update ALL modifier states from device-specific flag bits
        for key in ModifierKey.allCases {
            keyStates[key] = rawFlags & key.deviceFlagMask != 0
        }

        // Detect trigger combo activation (all triggers now down, at least one was previously up)
        let allTriggersNowDown = triggers.allSatisfy { keyStates[$0] ?? false }
        let allTriggersWereDown = triggers.allSatisfy { wasTriggerDown[$0] ?? false }
        if allTriggersNowDown && !allTriggersWereDown {
            NSLog("[Whisperer-HK] >>> TRIGGER COMBO ACTIVATED — calling handlePress")
            handlePress()
        }

        // Detect trigger key release (any trigger key transitioned from down to up)
        let anyTriggerReleased = triggers.contains { key in
            (wasTriggerDown[key] ?? false) && !(keyStates[key] ?? false)
        }
        if anyTriggerReleased {
            NSLog("[Whisperer-HK] >>> TRIGGER KEY RELEASED — calling handleRelease")
            handleRelease()
        }
    }

    private func handlePress() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                NSLog("[Whisperer-HK] handlePress: self deallocated")
                return
            }

            let currentStatus = self.appState.status
            guard currentStatus == .idle else {
                NSLog("[Whisperer-HK] handlePress: BLOCKED — status is not idle (status=%@)", "\(currentStatus)")
                return
            }

            var command = "start"

            // Check large model modifier
            if let largeKey = self.config.largeModelKey, self.keyStates[largeKey] ?? false {
                command += " --large"
            }

            // Check punctuation modifier
            if let punctKey = self.config.punctuationKey, self.keyStates[punctKey] ?? false {
                command += " --punct"
            }

            NSLog("[Whisperer-HK] handlePress: sending command '%@'", command)
            self.onCommand(command)
        }
    }

    private func handleRelease() {
        // Always send "stop" when trigger keys are released — don't check appState.status.
        // There's a race between the CGEvent callback (which fires immediately on the main
        // run loop) and the Python stdout handler (which dispatches async to main). If the
        // user releases quickly, appState might still be .idle when this fires, causing
        // "stop" to never be sent. The Python side handles redundant stops gracefully.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            NSLog("[Whisperer-HK] handleRelease: sending 'stop' (status=%@)", "\(self.appState.status)")
            self.onCommand("stop")
        }
    }
}

// MARK: - C Callback

private func hotkeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .flagsChanged {
        manager.handleFlagsChanged(flags: event.flags)
    } else if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        // Re-enable the tap
        NSLog("[Whisperer-HK] Event tap was disabled (type=%d) — re-enabling", type.rawValue)
        if let tap = manager.eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    return Unmanaged.passUnretained(event)
}
