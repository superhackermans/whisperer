import Foundation
import Combine

enum WhispererStatus: Equatable {
    case idle
    case recording
    case transcribing
    case error(String)
}

final class AppState: ObservableObject {
    @Published var status: WhispererStatus = .idle
    @Published var currentModel: String?
    @Published var lastTranscription: String?
    @Published var isSubprocessRunning: Bool = false
    @Published var debugMessages: [String] = []

    /// Max debug messages to retain in memory
    private let maxDebugMessages = 500

    func appendDebug(_ message: String) {
        DispatchQueue.main.async {
            self.debugMessages.append(message)
            if self.debugMessages.count > self.maxDebugMessages {
                self.debugMessages.removeFirst(self.debugMessages.count - self.maxDebugMessages)
            }
        }
    }
}
