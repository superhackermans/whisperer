import Foundation

/// Events parsed from Python subprocess stdout.
enum SubprocessEvent {
    case bridgeReady
    case recordingStarted
    case stoppingRecording
    case transcribing(model: String)
    case rawText(String)
    case cleanedText(String)
    case finalText(String)
    case pasted
    case copied
    case cancelThat
    case emptyTranscription
    case bracketedSkip
    case transcriptionDone
    case tooShort(duration: String)
    case error(title: String, message: String)
    case debug(tag: String, message: String)
    case log(String)
}

struct StdoutParser {
    /// Strip the `[2026-02-19 14:30:22.417] ` timestamp prefix and return the message.
    /// Returns the original string if no timestamp is found.
    private func stripTimestamp(_ line: String) -> String {
        // Format: [YYYY-MM-DD HH:MM:SS.mmm] message
        guard line.hasPrefix("["),
              let closingBracket = line.firstIndex(of: "]"),
              line.distance(from: line.startIndex, to: closingBracket) >= 24 else {
            return line
        }
        let afterBracket = line.index(after: closingBracket)
        if afterBracket < line.endIndex && line[afterBracket] == " " {
            return String(line[line.index(after: afterBracket)...])
        }
        return String(line[afterBracket...])
    }

    /// Extract a `[tag]` prefix from a debug message.
    /// Returns `(tag, rest)` or `nil` if no tag is found.
    private func extractTag(_ text: String) -> (String, String)? {
        guard text.hasPrefix("[") else { return nil }
        guard let close = text.firstIndex(of: "]") else { return nil }
        let tag = String(text[text.index(after: text.startIndex)..<close])
        // Tag should be a simple word (letters, digits, hyphens)
        guard !tag.isEmpty, tag.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else {
            return nil
        }
        let rest = String(text[text.index(after: close)...])
            .trimmingCharacters(in: .init(charactersIn: " "))
        return (tag, rest)
    }

    /// Parse a single line of stdout from the Python bridge process.
    func parse(line: String) -> SubprocessEvent {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .log("") }

        // Extract the message after the timestamp
        let message = stripTimestamp(trimmed)

        // Debug lines
        if message.hasPrefix("DEBUG ") {
            let debugContent = String(message.dropFirst(6))
            if let (tag, rest) = extractTag(debugContent) {
                return .debug(tag: tag, message: rest)
            }
            return .debug(tag: "", message: debugContent)
        }

        // Bridge ready
        if message == "BRIDGE_READY" {
            return .bridgeReady
        }

        // Recording started
        if message == "Recording started." {
            return .recordingStarted
        }

        // Stopping recording
        if message == "Stopping recording..." {
            return .stoppingRecording
        }

        // Transcribing with model
        if message.hasPrefix("Transcribing with model ") {
            let model = message
                .replacingOccurrences(of: "Transcribing with model ", with: "")
                .replacingOccurrences(of: "...", with: "")
            return .transcribing(model: model)
        }

        // Raw transcription
        if message.hasPrefix("Raw: '") && message.hasSuffix("'") {
            let text = String(message.dropFirst(6).dropLast(1))
            return .rawText(text)
        }

        // Cleaned transcription
        if message.hasPrefix("Cleaned: '") && message.hasSuffix("'") {
            let text = String(message.dropFirst(10).dropLast(1))
            return .cleanedText(text)
        }

        // Final transcription
        if message.hasPrefix("Final: '") && message.hasSuffix("'") {
            let text = String(message.dropFirst(8).dropLast(1))
            return .finalText(text)
        }

        // Pasted
        if message == "Pasted (Cmd+V)." {
            return .pasted
        }

        // Copied
        if message == "Copied to clipboard." {
            return .copied
        }

        // Cancel that
        if message == "Contains 'cancel that' \u{2014} skipping." {
            return .cancelThat
        }

        // Empty transcription
        if message == "Empty transcription \u{2014} skipping." {
            return .emptyTranscription
        }

        // Bracketed/asterisk hallucination
        if message.hasPrefix("Enclosed in brackets/asterisks") {
            return .bracketedSkip
        }

        // Transcription pipeline done (reliable completion signal from on_transcription_done callback)
        if message == "TRANSCRIPTION_DONE" {
            return .transcriptionDone
        }

        // Too short
        if message.hasPrefix("Recording too short (") {
            let duration = message
                .replacingOccurrences(of: "Recording too short (", with: "")
                .replacingOccurrences(of: "). Skipping.", with: "")
            return .tooShort(duration: duration)
        }

        // Errors with title:message pattern
        if message.contains(": ") {
            let errorPrefixes = [
                "Recording failed", "Transcription failed", "Model not found",
                "Paste failed", "Recording error",
            ]
            for prefix in errorPrefixes {
                if message.hasPrefix(prefix + ": ") {
                    let errorMsg = String(message.dropFirst(prefix.count + 2))
                    return .error(title: prefix, message: errorMsg)
                }
            }
        }

        return .log(message)
    }
}
