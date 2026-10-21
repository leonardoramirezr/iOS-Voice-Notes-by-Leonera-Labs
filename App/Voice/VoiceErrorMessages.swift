import Foundation
import VoiceNotesCore

/// User-facing explanations of voice command failures.
enum VoiceErrorMessages {
    static func message(for error: Error) -> String {
        if let groq = error as? GroqError {
            switch groq {
            case .missingAPIKey:
                return L10n.voiceGroqKeyMissing
            case .unauthorized:
                return L10n.voiceGroqUnauthorized
            case .rateLimited:
                return L10n.voiceGroqRateLimited
            case .requestTooLarge:
                return L10n.voiceCommandTooLong
            case .transport:
                return L10n.networkError
            case .badRequest(let message):
                return L10n.voiceGroqFailed(message)
            case .server(let status):
                return L10n.voiceGroqFailed("HTTP \(status)")
            case .truncated, .emptyResponse, .invalidResponse:
                return L10n.voiceGroqFailed(String(describing: groq))
            }
        }
        if error is AudioRecorder.RecorderError {
            return L10n.voiceRecordingFailed
        }
        if let saveError = error as? NoteSaveError, case .noteMissing(let title) = saveError {
            return L10n.voiceNoteMissing(title)
        }
        return error.localizedDescription
    }
}
