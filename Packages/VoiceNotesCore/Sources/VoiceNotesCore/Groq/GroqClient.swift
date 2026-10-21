import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Client for the Groq OpenAI-compatible API: Whisper transcription and chat completions with JSON schemas.
public struct GroqClient: Sendable {
    public static let baseURL = URL(string: "https://api.groq.com/openai/v1/")!

    private let apiKey: String
    private let transport: HTTPTransport
    private let maxServerRetries: Int
    private let retryBaseDelay: TimeInterval

    public init(
        apiKey: String,
        transport: HTTPTransport = URLSessionTransport(),
        maxServerRetries: Int = 2,
        retryBaseDelay: TimeInterval = 0.5
    ) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.transport = transport
        self.maxServerRetries = maxServerRetries
        self.retryBaseDelay = retryBaseDelay
    }

    /// Runs a chat completion whose answer must match `schema`, and decodes it as `T`.
    public func completeJSON<T: Decodable>(
        _ type: T.Type,
        model: String,
        system: String,
        user: String,
        schemaName: String,
        schema: JSONValue,
        reasoningEffort: String = "low",
        maxCompletionTokens: Int = 4096,
        temperature: Double = 0.2
    ) async throws -> T {
        let reasoning = GroqModelSettings.isReasoningModel(model)
        let body = ChatCompletionRequest(
            model: model,
            messages: [.init(role: "system", content: system), .init(role: "user", content: user)],
            responseFormat: .init(jsonSchema: .init(
                name: schemaName, strict: GroqModelSettings.supportsStrictSchemas(model), schema: schema
            )),
            temperature: temperature,
            maxCompletionTokens: maxCompletionTokens,
            reasoningEffort: reasoning ? reasoningEffort : nil,
            includeReasoning: reasoning ? false : nil
        )
        var request = try makeRequest(path: "chat/completions", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONCoding.encoder().encode(body)

        let data = try await send(request)
        let response: ChatCompletionResponse
        do {
            response = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        } catch {
            throw GroqError.invalidResponse(String(decoding: data.prefix(300), as: UTF8.self))
        }
        guard let choice = response.choices.first else {
            throw GroqError.emptyResponse
        }
        if choice.finishReason == "length" {
            throw GroqError.truncated
        }
        guard let content = choice.message.content, !content.isEmpty else {
            throw GroqError.emptyResponse
        }
        do {
            return try JSONDecoder().decode(T.self, from: Data(content.utf8))
        } catch {
            throw GroqError.invalidResponse(String(content.prefix(300)))
        }
    }

    /// Transcribes audio with Whisper. `language` is an ISO 639-1 code; `prompt` helps with spelling.
    public func transcribe(
        audio: Data,
        fileName: String,
        mimeType: String,
        model: String,
        language: String?,
        prompt: String?
    ) async throws -> Transcription {
        var form = MultipartFormData()
        form.addField("model", model)
        form.addField("response_format", "verbose_json")
        form.addField("temperature", "0")
        if let language, !language.isEmpty {
            form.addField("language", language)
        }
        if let prompt, !prompt.isEmpty {
            form.addField("prompt", prompt)
        }
        form.addFile("file", fileName: fileName, mimeType: mimeType, data: audio)

        var request = try makeRequest(path: "audio/transcriptions", method: "POST")
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.finalized()
        request.timeoutInterval = 120

        let data = try await send(request)
        do {
            return try JSONDecoder().decode(Transcription.self, from: data)
        } catch {
            throw GroqError.invalidResponse(String(decoding: data.prefix(300), as: UTF8.self))
        }
    }

    /// Lists the model ids available to the key; also used to check that a key works.
    public func listModels() async throws -> [String] {
        let data = try await send(try makeRequest(path: "models", method: "GET"))
        do {
            return try JSONDecoder().decode(ModelList.self, from: data).data.map(\.id).sorted()
        } catch {
            throw GroqError.invalidResponse(String(decoding: data.prefix(300), as: UTF8.self))
        }
    }

    // MARK: - Transport

    private func makeRequest(path: String, method: String) throws -> URLRequest {
        guard !apiKey.isEmpty else {
            throw GroqError.missingAPIKey
        }
        var request = URLRequest(url: Self.baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 60
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        var attempt = 0
        while true {
            let data: Data
            let response: HTTPURLResponse
            do {
                (data, response) = try await transport.send(request)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw GroqError.transport(error.localizedDescription)
            }
            switch response.statusCode {
            case 200..<300:
                return data
            case 500..<600 where attempt < maxServerRetries:
                attempt += 1
                try await Task.sleep(nanoseconds: UInt64(retryBaseDelay * Double(attempt) * 1_000_000_000))
            default:
                throw Self.error(status: response.statusCode, data: data, response: response)
            }
        }
    }

    static func error(status: Int, data: Data, response: HTTPURLResponse) -> GroqError {
        let message = (try? JSONDecoder().decode(GroqErrorEnvelope.self, from: data))?.error.message
        switch status {
        case 401, 403:
            return .unauthorized
        case 413:
            return .requestTooLarge
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "retry-after").flatMap(TimeInterval.init)
            return .rateLimited(retryAfter: retryAfter)
        case 500..<600:
            return .server(status: status)
        default:
            return .badRequest(message ?? "HTTP \(status)")
        }
    }
}
