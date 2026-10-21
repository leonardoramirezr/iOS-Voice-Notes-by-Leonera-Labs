import Foundation

/// Errors returned by the Groq API, mapped to what the app can explain to the user.
public enum GroqError: Error, Equatable, Sendable {
    case missingAPIKey
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case requestTooLarge
    case badRequest(String)
    case server(status: Int)
    case truncated
    case emptyResponse
    case invalidResponse(String)
    case transport(String)
}

/// A Whisper transcription (`verbose_json`).
public struct Transcription: Decodable, Equatable, Sendable {
    public struct Segment: Decodable, Equatable, Sendable {
        public let noSpeechProbability: Double?

        public init(noSpeechProbability: Double?) {
            self.noSpeechProbability = noSpeechProbability
        }

        enum CodingKeys: String, CodingKey {
            case noSpeechProbability = "no_speech_prob"
        }
    }

    public let text: String
    public let language: String?
    public let segments: [Segment]?

    public init(text: String, language: String?, segments: [Segment]?) {
        self.text = text
        self.language = language
        self.segments = segments
    }

    /// True when nothing was said: Whisper tends to invent short phrases for silence.
    public var isLikelySilence: Bool {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        guard let segments, !segments.isEmpty else {
            return false
        }
        return segments.allSatisfy { ($0.noSpeechProbability ?? 0) > 0.6 }
    }
}

/// Model settings for the voice pipeline.
public struct GroqModelSettings: Equatable, Sendable {
    public static let defaultChatModel = "openai/gpt-oss-120b"
    public static let defaultTranscriptionModel = "whisper-large-v3"
    public static let chatModels = ["openai/gpt-oss-120b", "openai/gpt-oss-20b"]
    public static let transcriptionModels = ["whisper-large-v3", "whisper-large-v3-turbo"]

    public var chatModel: String
    public var transcriptionModel: String

    public init(chatModel: String = defaultChatModel, transcriptionModel: String = defaultTranscriptionModel) {
        self.chatModel = chatModel
        self.transcriptionModel = transcriptionModel
    }

    /// Models with constrained decoding for `strict` JSON schemas.
    public static func supportsStrictSchemas(_ model: String) -> Bool {
        ["openai/gpt-oss-", "qwen/", "meta-models/muse"].contains { model.hasPrefix($0) }
    }

    /// Reasoning models that accept `reasoning_effort` and `include_reasoning`.
    public static func isReasoningModel(_ model: String) -> Bool {
        model.hasPrefix("openai/gpt-oss-")
    }
}

struct ChatCompletionRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct ResponseFormat: Encodable {
        struct Schema: Encodable {
            let name: String
            let strict: Bool
            let schema: JSONValue
        }

        let type = "json_schema"
        let jsonSchema: Schema

        enum CodingKeys: String, CodingKey {
            case type
            case jsonSchema = "json_schema"
        }
    }

    let model: String
    let messages: [Message]
    let responseFormat: ResponseFormat
    let temperature: Double
    let maxCompletionTokens: Int
    let reasoningEffort: String?
    let includeReasoning: Bool?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case responseFormat = "response_format"
        case temperature
        case maxCompletionTokens = "max_completion_tokens"
        case reasoningEffort = "reasoning_effort"
        case includeReasoning = "include_reasoning"
    }
}

struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }

        let message: Message
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }

    let choices: [Choice]
}

struct GroqErrorEnvelope: Decodable {
    struct Body: Decodable {
        let message: String?
        let code: String?
    }

    let error: Body
}

struct ModelList: Decodable {
    struct Model: Decodable {
        let id: String
    }

    let data: [Model]
}
