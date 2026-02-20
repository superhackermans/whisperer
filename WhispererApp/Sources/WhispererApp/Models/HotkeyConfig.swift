import Foundation

/// The four modifier keys that can be distinguished via device-specific CGEventFlags.
enum ModifierKey: String, CaseIterable, Codable, Hashable {
    case rightCmd
    case rightOption
    case leftCmd
    case leftOption

    var displayName: String {
        switch self {
        case .rightCmd:    return "Right Cmd"
        case .rightOption: return "Right Option"
        case .leftCmd:     return "Left Cmd"
        case .leftOption:  return "Left Option"
        }
    }

    /// Device-specific CGEventFlags mask from IOKit/IOLLEvent.h (NX_DEVICE*KEYMASK).
    var deviceFlagMask: UInt64 {
        switch self {
        case .leftCmd:     return 0x00000008
        case .rightCmd:    return 0x00000010
        case .leftOption:  return 0x00000020
        case .rightOption: return 0x00000040
        }
    }
}

/// Role assigned to each modifier key.
enum ModifierRole: String, CaseIterable, Codable, Hashable {
    case trigger
    case largeModel
    case punctuation

    var displayName: String {
        switch self {
        case .trigger:     return "Trigger"
        case .largeModel:  return "Large Model"
        case .punctuation: return "Punctuation"
        }
    }
}

/// Hotkey configuration mapping each modifier key to its role.
struct HotkeyConfig: Codable, Equatable {
    var keyRoles: [ModifierKey: ModifierRole]

    /// Default config matching current hardcoded behavior:
    /// RCmd + ROpt = trigger, LCmd = large model, LOpt = punctuation
    static let `default` = HotkeyConfig(keyRoles: [
        .rightCmd: .trigger,
        .rightOption: .trigger,
        .leftCmd: .largeModel,
        .leftOption: .punctuation,
    ])

    /// Keys assigned the trigger role (exactly 2 required for valid config).
    var triggerKeys: [ModifierKey] {
        keyRoles.filter { $0.value == .trigger }.map(\.key)
    }

    /// The key assigned the large model role (exactly 1 required).
    var largeModelKey: ModifierKey? {
        keyRoles.first { $0.value == .largeModel }?.key
    }

    /// The key assigned the punctuation role (exactly 1 required).
    var punctuationKey: ModifierKey? {
        keyRoles.first { $0.value == .punctuation }?.key
    }

    /// Config is valid when exactly 2 triggers, 1 largeModel, and 1 punctuation are assigned.
    var isValid: Bool {
        let triggers = keyRoles.values.filter { $0 == .trigger }.count
        let large = keyRoles.values.filter { $0 == .largeModel }.count
        let punct = keyRoles.values.filter { $0 == .punctuation }.count
        return triggers == 2 && large == 1 && punct == 1
            && keyRoles.count == 4
    }

    var validationMessage: String {
        let triggers = keyRoles.values.filter { $0 == .trigger }.count
        let large = keyRoles.values.filter { $0 == .largeModel }.count
        let punct = keyRoles.values.filter { $0 == .punctuation }.count

        if triggers != 2 {
            return "Need exactly 2 trigger keys (have \(triggers))"
        }
        if large != 1 {
            return "Need exactly 1 large model key (have \(large))"
        }
        if punct != 1 {
            return "Need exactly 1 punctuation key (have \(punct))"
        }
        return "Valid configuration"
    }

    // MARK: - UserDefaults Persistence

    private static let userDefaultsKey = "hotkeyConfig"

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: HotkeyConfig.userDefaultsKey)
        }
    }

    static func load() -> HotkeyConfig {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let config = try? JSONDecoder().decode(HotkeyConfig.self, from: data)
        else {
            return .default
        }
        return config
    }
}
