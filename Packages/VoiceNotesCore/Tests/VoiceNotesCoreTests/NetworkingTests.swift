import Foundation
import XCTest
@testable import VoiceNotesCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Records requests and replies with canned responses.
final class FakeTransport: HTTPTransport, @unchecked Sendable {
    struct Reply {
        let status: Int
        let body: String
        var headers: [String: String] = [:]
    }

    private let lock = NSLock()
    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [Reply]) {
        self.replies = replies
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let reply: Reply = lock.withLock {
            requests.append(request)
            return replies.isEmpty ? Reply(status: 500, body: "") : replies.removeFirst()
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        return (Data(reply.body.utf8), response)
    }

    func jsonBody(at index: Int) throws -> [String: Any] {
        let body = try XCTUnwrap(requests[index].httpBody)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    }
}

private func chatReply(_ content: String, finishReason: String = "stop") -> FakeTransport.Reply {
    let escaped = String(data: try! JSONSerialization.data(withJSONObject: [content]), encoding: .utf8)!.dropFirst().dropLast()
    return .init(status: 200, body: "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\(escaped)},\"finish_reason\":\"\(finishReason)\"}]}")
}

final class GroqClientTests: XCTestCase {
    private struct Answer: Decodable, Equatable {
        let value: Int
    }

    func testChatRequestUsesStrictSchemaAndReasoningSettings() async throws {
        let transport = FakeTransport([chatReply("{\"value\":42}")])
        let client = GroqClient(apiKey: " key ", transport: transport)
        let answer = try await client.completeJSON(
            Answer.self, model: "openai/gpt-oss-120b", system: "sys", user: "usr",
            schemaName: "answer", schema: ["type": "object"]
        )
        XCTAssertEqual(answer, Answer(value: 42))
        let request = transport.requests[0]
        XCTAssertEqual(request.url?.absoluteString, "https://api.groq.com/openai/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer key")
        let body = try transport.jsonBody(at: 0)
        XCTAssertEqual(body["model"] as? String, "openai/gpt-oss-120b")
        XCTAssertEqual(body["reasoning_effort"] as? String, "low")
        XCTAssertEqual(body["include_reasoning"] as? Bool, false)
        let format = try XCTUnwrap(body["response_format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        XCTAssertEqual((format["json_schema"] as? [String: Any])?["strict"] as? Bool, true)
        XCTAssertEqual((body["messages"] as? [[String: Any]])?.map { $0["role"] as? String }, ["system", "user"])
    }

    func testNonReasoningModelOmitsReasoningFields() async throws {
        let transport = FakeTransport([chatReply("{\"value\":1}")])
        _ = try await GroqClient(apiKey: "k", transport: transport).completeJSON(
            Answer.self, model: "other/model", system: "s", user: "u", schemaName: "a", schema: [:]
        )
        let body = try transport.jsonBody(at: 0)
        XCTAssertNil(body["reasoning_effort"])
        XCTAssertNil(body["include_reasoning"])
        XCTAssertEqual(((body["response_format"] as? [String: Any])?["json_schema"] as? [String: Any])?["strict"] as? Bool, false)
    }

    func testErrorsAreMapped() async {
        let cases: [(FakeTransport.Reply, GroqError)] = [
            (.init(status: 401, body: "{\"error\":{\"message\":\"Invalid API Key\"}}"), .unauthorized),
            (.init(status: 429, body: "{}", headers: ["retry-after": "7"]), .rateLimited(retryAfter: 7)),
            (.init(status: 413, body: "{}"), .requestTooLarge),
            (.init(status: 400, body: "{\"error\":{\"message\":\"bad schema\"}}"), .badRequest("bad schema")),
        ]
        for (reply, expected) in cases {
            let client = GroqClient(apiKey: "k", transport: FakeTransport([reply]))
            do {
                _ = try await client.completeJSON(Answer.self, model: "m", system: "", user: "", schemaName: "a", schema: [:])
                XCTFail("expected \(expected)")
            } catch {
                XCTAssertEqual(error as? GroqError, expected)
            }
        }
    }

    func testServerErrorsAreRetried() async throws {
        let transport = FakeTransport([.init(status: 503, body: ""), chatReply("{\"value\":3}")])
        let client = GroqClient(apiKey: "k", transport: transport, maxServerRetries: 2, retryBaseDelay: 0)
        let answer = try await client.completeJSON(Answer.self, model: "m", system: "", user: "", schemaName: "a", schema: [:])
        XCTAssertEqual(answer.value, 3)
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testTruncatedAndInvalidAnswers() async {
        let truncated = GroqClient(apiKey: "k", transport: FakeTransport([chatReply("{\"val", finishReason: "length")]))
        do {
            _ = try await truncated.completeJSON(Answer.self, model: "m", system: "", user: "", schemaName: "a", schema: [:])
            XCTFail("expected truncation")
        } catch {
            XCTAssertEqual(error as? GroqError, .truncated)
        }
        let invalid = GroqClient(apiKey: "k", transport: FakeTransport([chatReply("not json")]))
        do {
            _ = try await invalid.completeJSON(Answer.self, model: "m", system: "", user: "", schemaName: "a", schema: [:])
            XCTFail("expected invalid response")
        } catch {
            XCTAssertEqual(error as? GroqError, .invalidResponse("not json"))
        }
    }

    func testMissingKey() async {
        do {
            _ = try await GroqClient(apiKey: "  ", transport: FakeTransport([])).listModels()
            XCTFail("expected missing key")
        } catch {
            XCTAssertEqual(error as? GroqError, .missingAPIKey)
        }
    }

    func testTranscriptionMultipart() async throws {
        let transport = FakeTransport([.init(status: 200, body: """
        {"text":" Hola mundo ","language":"spanish","segments":[{"no_speech_prob":0.01}]}
        """)])
        let client = GroqClient(apiKey: "k", transport: transport)
        let result = try await client.transcribe(
            audio: Data([1, 2, 3]), fileName: "command.m4a", mimeType: "audio/m4a",
            model: "whisper-large-v3", language: "es", prompt: "Muebles, Súper"
        )
        XCTAssertEqual(result.text, " Hola mundo ")
        XCTAssertFalse(result.isLikelySilence)
        let request = transport.requests[0]
        XCTAssertEqual(request.url?.lastPathComponent, "transcriptions")
        let contentType = try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="))
        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"model\"\r\n\r\nwhisper-large-v3\r\n"))
        XCTAssertTrue(body.contains("name=\"language\"\r\n\r\nes\r\n"))
        XCTAssertTrue(body.contains("name=\"prompt\"\r\n\r\nMuebles, Súper\r\n"))
        XCTAssertTrue(body.contains("name=\"response_format\"\r\n\r\nverbose_json\r\n"))
        XCTAssertTrue(body.contains("filename=\"command.m4a\""))
    }

    func testSilenceDetection() {
        XCTAssertTrue(Transcription(text: "  ", language: nil, segments: nil).isLikelySilence)
        XCTAssertTrue(Transcription(text: "Gracias.", language: nil, segments: [.init(noSpeechProbability: 0.9)]).isLikelySilence)
        XCTAssertFalse(Transcription(text: "Hola", language: nil, segments: [.init(noSpeechProbability: 0.2)]).isLikelySilence)
    }

    func testListModels() async throws {
        let transport = FakeTransport([.init(status: 200, body: "{\"data\":[{\"id\":\"b\"},{\"id\":\"a\"}]}")])
        let models = try await GroqClient(apiKey: "k", transport: transport).listModels()
        XCTAssertEqual(models, ["a", "b"])
        XCTAssertEqual(transport.requests[0].httpMethod, "GET")
    }
}

final class SimplenoteAuthClientTests: XCTestCase {
    func testEmailValidation() {
        XCTAssertTrue(SimplenoteAuthClient.isValidEmail("leo@example.com"))
        XCTAssertTrue(SimplenoteAuthClient.isValidEmail(" a.b+c@mail.co.uk "))
        XCTAssertFalse(SimplenoteAuthClient.isValidEmail("leo@example"))
        XCTAssertFalse(SimplenoteAuthClient.isValidEmail("leo"))
    }

    func testNormalizedCode() {
        XCTAssertEqual(SimplenoteAuthClient.normalizedCode(" ab1-c2d "), "AB1C2D")
    }

    func testRequestLoginCode() async throws {
        let transport = FakeTransport([.init(status: 200, body: "")])
        try await SimplenoteAuthClient(transport: transport).requestLoginCode(email: " Leo@Example.com ")
        let request = transport.requests[0]
        XCTAssertEqual(request.url?.absoluteString, "https://app.simplenote.com/account/request-login")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try transport.jsonBody(at: 0)
        XCTAssertEqual(body["request_source"] as? String, "iOS")
        XCTAssertEqual(body["username"] as? String, "leo@example.com")
    }

    func testCompleteLogin() async throws {
        let transport = FakeTransport([.init(status: 200, body: "{\"username\":\"leo@example.com\",\"sync_token\":\"tok\"}")])
        let login = try await SimplenoteAuthClient(transport: transport).completeLogin(email: "Leo@Example.com", code: "abc123")
        XCTAssertEqual(login, SimplenoteLogin(username: "leo@example.com", syncToken: "tok"))
        XCTAssertEqual(transport.requests[0].url?.lastPathComponent, "complete-login")
        let body = try transport.jsonBody(at: 0)
        XCTAssertEqual(body["auth_code"] as? String, "ABC123")
        XCTAssertEqual(body["username"] as? String, "Leo@Example.com")
    }

    func testErrorMapping() async {
        let cases: [(FakeTransport.Reply, SimplenoteAuthError)] = [
            (.init(status: 400, body: "{\"error\":\"invalid-code\"}"), .invalidCode),
            (.init(status: 400, body: "{\"error\":\"request-not-found\"}"), .codeExpired),
            (.init(status: 429, body: ""), .tooManyAttempts),
            (.init(status: 500, body: ""), .unexpectedStatus(500)),
            (.init(status: 200, body: "{}"), .invalidResponse),
        ]
        for (reply, expected) in cases {
            do {
                _ = try await SimplenoteAuthClient(transport: FakeTransport([reply])).completeLogin(email: "a@b.co", code: "ABCDEF")
                XCTFail("expected \(expected)")
            } catch {
                XCTAssertEqual(error as? SimplenoteAuthError, expected)
            }
        }
    }

    func testRejectsBadInputLocally() async {
        let transport = FakeTransport([])
        do {
            try await SimplenoteAuthClient(transport: transport).requestLoginCode(email: "nope")
            XCTFail("expected invalid email")
        } catch {
            XCTAssertEqual(error as? SimplenoteAuthError, .invalidEmail)
        }
        do {
            _ = try await SimplenoteAuthClient(transport: transport).completeLogin(email: "a@b.co", code: "123")
            XCTFail("expected invalid code")
        } catch {
            XCTAssertEqual(error as? SimplenoteAuthError, .invalidCode)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }
}
