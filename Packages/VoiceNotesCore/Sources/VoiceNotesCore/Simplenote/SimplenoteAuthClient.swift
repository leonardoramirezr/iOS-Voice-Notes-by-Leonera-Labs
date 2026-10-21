import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The result of a successful Simplenote login: the account name and the Simperium sync token.
public struct SimplenoteLogin: Equatable, Sendable {
    public let username: String
    public let syncToken: String

    public init(username: String, syncToken: String) {
        self.username = username
        self.syncToken = syncToken
    }
}

public enum SimplenoteAuthError: Error, Equatable, Sendable {
    case invalidEmail
    case invalidCode
    case codeExpired
    case tooManyAttempts
    /// Any other HTTP error, with the server's reason when it sent one.
    case unexpectedStatus(Int, detail: String?)
    case invalidResponse
    case network(String)
}

/// Simplenote's passwordless login, the default login of the official app: the server emails a 6-character
/// code and exchanges it for a sync token. No Simperium API key is involved.
public struct SimplenoteAuthClient: Sendable {
    public static let baseURL = URL(string: "https://app.simplenote.com/")!
    /// Sync tokens are scoped by request source; the iOS app uses "iOS".
    public static let requestSource = "iOS"
    /// The server only accepts a request-login without a reCAPTCHA token from clients whose User-Agent starts
    /// with "Simplenote/" (like the official apps); any other agent gets an HTML "400 Bad Request".
    public static let userAgent = "Simplenote/4.54 VoiceNotes (iOS)"
    public static let codeLength = 6

    private let transport: HTTPTransport

    public init(transport: HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    public static func isValidEmail(_ email: String) -> Bool {
        let pattern = "^.+@([A-Za-z0-9-]+\\.)+[A-Za-z]{2}[A-Za-z]*$"
        let text = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return false
        }
        return expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// The code as the server expects it: letters and digits only, uppercased.
    public static func normalizedCode(_ code: String) -> String {
        String(code.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init)).uppercased()
    }

    /// Asks Simplenote to email a login code.
    public func requestLoginCode(email: String) async throws {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidEmail(trimmed) else {
            throw SimplenoteAuthError.invalidEmail
        }
        _ = try await post("account/request-login", body: [
            "request_source": Self.requestSource,
            "username": trimmed.lowercased(),
        ])
    }

    /// Exchanges the emailed code for a sync token.
    public func completeLogin(email: String, code: String) async throws -> SimplenoteLogin {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = Self.normalizedCode(code)
        guard normalized.count == Self.codeLength else {
            throw SimplenoteAuthError.invalidCode
        }
        let data = try await post("account/complete-login", body: ["auth_code": normalized, "username": trimmed])
        struct Response: Decodable {
            let username: String?
            let syncToken: String?

            enum CodingKeys: String, CodingKey {
                case username
                case syncToken = "sync_token"
            }
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              let token = response.syncToken, !token.isEmpty else {
            throw SimplenoteAuthError.invalidResponse
        }
        let username = response.username.flatMap { $0.isEmpty ? nil : $0 } ?? trimmed
        return SimplenoteLogin(username: username, syncToken: token)
    }

    private func post(_ path: String, body: [String: String]) async throws -> Data {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch {
            throw SimplenoteAuthError.network(error.localizedDescription)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw Self.error(status: response.statusCode, data: data)
        }
        return data
    }

    static func error(status: Int, data: Data) -> SimplenoteAuthError {
        let code = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
        switch (status, code) {
        case (429, _):
            return .tooManyAttempts
        case (_, "request-not-found"?):
            return .codeExpired
        case (_, "invalid-code"?):
            return .invalidCode
        default:
            return .unexpectedStatus(status, detail: serverDetail(code: code, data: data))
        }
    }

    /// A short, readable reason from an error body: its JSON `error`/`message`, or its text without HTML tags.
    static func serverDetail(code: String?, data: Data) -> String? {
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let text = code ?? (json?["message"] as? String) ?? String(decoding: data, as: UTF8.self)
        let stripped = text
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !stripped.isEmpty else {
            return nil
        }
        return stripped.count > 200 ? String(stripped.prefix(200)) + "…" : stripped
    }
}
