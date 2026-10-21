import AVFoundation
import NaturalLanguage

/// Reads the assistant's questions aloud.
@MainActor
final class SpeechPlayer {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String, language: String?) {
        stop()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.voice(for: text, language: language)
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    /// A voice for the reply's language, preferring the device region (for example es-MX).
    static func voice(for text: String, language: String?) -> AVSpeechSynthesisVoice? {
        var code = language?.lowercased()
        if code?.count != 2 {
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(text)
            code = recognizer.dominantLanguage?.rawValue
        }
        guard let code else {
            return nil
        }
        if let region = Locale.current.region?.identifier,
           let voice = AVSpeechSynthesisVoice(language: "\(code)-\(region)") {
            return voice
        }
        return AVSpeechSynthesisVoice(language: code)
    }
}
