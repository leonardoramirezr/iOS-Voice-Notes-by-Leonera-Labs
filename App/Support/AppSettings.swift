import Foundation
import Observation
import VoiceNotesCore
import VoiceNotesSync

/// User preferences. The Groq API key lives in the Keychain; everything else in UserDefaults.
@MainActor
@Observable
final class AppSettings {
    private enum Key {
        static let chatModel = "settings.chatModel"
        static let transcriptionModel = "settings.transcriptionModel"
        static let transcriptionLanguage = "settings.transcriptionLanguage"
        static let speakReplies = "settings.speakReplies"
    }

    /// `transcriptionLanguage` value that lets Whisper detect the language.
    static let automaticLanguage = "auto"
    static let languages = [automaticLanguage, "es", "en", "pt", "fr", "it", "de"]

    private let defaults: UserDefaults
    private let groqKeyItem = KeychainItem(
        service: "com.leonardoramirezr.voicenotesbyleoneralabs.groq", account: "api-key"
    )

    var chatModel: String {
        didSet { defaults.set(chatModel, forKey: Key.chatModel) }
    }

    var transcriptionModel: String {
        didSet { defaults.set(transcriptionModel, forKey: Key.transcriptionModel) }
    }

    var transcriptionLanguage: String {
        didSet { defaults.set(transcriptionLanguage, forKey: Key.transcriptionLanguage) }
    }

    var speakReplies: Bool {
        didSet { defaults.set(speakReplies, forKey: Key.speakReplies) }
    }

    private(set) var hasGroqKey: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        chatModel = defaults.string(forKey: Key.chatModel) ?? GroqModelSettings.defaultChatModel
        transcriptionModel = defaults.string(forKey: Key.transcriptionModel) ?? GroqModelSettings.defaultTranscriptionModel
        transcriptionLanguage = defaults.string(forKey: Key.transcriptionLanguage) ?? Self.deviceLanguage
        speakReplies = defaults.object(forKey: Key.speakReplies) as? Bool ?? true
        hasGroqKey = !(groqKeyItem.readString() ?? "").isEmpty
    }

    /// The device language when Whisper should expect it, otherwise automatic detection.
    static var deviceLanguage: String {
        let code = Locale.current.language.languageCode?.identifier ?? ""
        return languages.contains(code) ? code : automaticLanguage
    }

    /// The `language` parameter for Whisper, or nil to detect it.
    var whisperLanguage: String? {
        transcriptionLanguage == Self.automaticLanguage ? nil : transcriptionLanguage
    }

    func groqAPIKey() -> String? {
        guard let key = groqKeyItem.readString(), !key.isEmpty else {
            return nil
        }
        return key
    }

    func setGroqAPIKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            groqKeyItem.delete()
        } else {
            try groqKeyItem.writeString(trimmed)
        }
        hasGroqKey = !trimmed.isEmpty
    }
}
