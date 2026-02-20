import Foundation

/// Swift representation of ~/.whisperer/config.yaml
/// Matches the Python DEFAULT_CONFIG schema in config.py
struct WhispererConfig: Codable {
    var whispercppFolder: String
    var prompt: String
    var models: [String: ModelRange?]
    var enableBeeps: Bool
    var enableStartSound: Bool
    var enableStopSound: Bool
    var enableErrorSound: Bool
    var soundVolume: Int
    var cleanupRecordings: Bool
    var debug: Bool

    /// A model's duration range [min, max] or null for manual-only
    struct ModelRange: Codable {
        var min: Double
        var max: Double

        init(min: Double, max: Double) {
            self.min = min
            self.max = max
        }

        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            self.min = try container.decode(Double.self)
            self.max = try container.decode(Double.self)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.unkeyedContainer()
            try container.encode(min)
            try container.encode(max)
        }
    }

    enum CodingKeys: String, CodingKey {
        case whispercppFolder = "whispercpp_folder"
        case prompt
        case models
        case enableBeeps = "enable_beeps"
        case enableStartSound = "enable_start_sound"
        case enableStopSound = "enable_stop_sound"
        case enableErrorSound = "enable_error_sound"
        case soundVolume = "sound_volume"
        case cleanupRecordings = "cleanup_recordings"
        case debug
    }

    static let `default` = WhispererConfig(
        whispercppFolder: "",
        prompt: "Voice dictation, clear speech, single speaker.",
        models: [
            "tiny.en": ModelRange(min: 0, max: 1.5),
            "base.en": ModelRange(min: 1.5, max: 3),
            "small.en": ModelRange(min: 3, max: 999999),
            "large-v3-turbo": nil,
        ],
        enableBeeps: true,
        enableStartSound: true,
        enableStopSound: true,
        enableErrorSound: true,
        soundVolume: 50,
        cleanupRecordings: true,
        debug: false
    )
}
