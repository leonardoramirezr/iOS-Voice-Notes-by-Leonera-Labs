import Foundation
import Observation
import VoiceNotesCore

/// Simplenote's passwordless login: email first, then the 6-character code sent by email.
@MainActor
@Observable
final class LoginModel {
    enum Step {
        case email
        case code
    }

    var email: String
    var code = ""
    private(set) var step: Step = .email
    private(set) var isWorking = false
    private(set) var errorMessage: String?
    private let client = SimplenoteAuthClient()

    init(email: String = "") {
        self.email = email
    }

    var canSendCode: Bool {
        SimplenoteAuthClient.isValidEmail(email) && !isWorking
    }

    var canLogIn: Bool {
        SimplenoteAuthClient.normalizedCode(code).count == SimplenoteAuthClient.codeLength && !isWorking
    }

    func sendCode() async {
        guard canSendCode else {
            errorMessage = L10n.loginInvalidEmail
            return
        }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await client.requestLoginCode(email: email)
            code = ""
            step = .code
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// Returns the session when the code is accepted.
    func logIn() async -> SimplenoteLogin? {
        guard canLogIn else {
            errorMessage = L10n.loginInvalidCode
            return nil
        }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            return try await client.completeLogin(email: email, code: code)
        } catch {
            errorMessage = Self.message(for: error)
            return nil
        }
    }

    func useDifferentEmail() {
        step = .email
        code = ""
        errorMessage = nil
    }

    /// A readable message that says what went wrong, with the technical reason when there is one.
    static func message(for error: Error) -> String {
        switch error as? SimplenoteAuthError {
        case .invalidEmail:
            return L10n.loginInvalidEmail
        case .invalidCode:
            return L10n.loginInvalidCode
        case .codeExpired:
            return L10n.loginCodeExpired
        case .tooManyAttempts:
            return L10n.loginTooManyAttempts
        case .network(let reason):
            return withDetails(L10n.networkError, reason)
        case .unexpectedStatus(let status, let detail):
            return withDetails(L10n.loginServerError(status), detail)
        case .invalidResponse:
            return L10n.loginUnexpectedResponse
        case nil:
            return withDetails(L10n.loginFailed, error.localizedDescription)
        }
    }

    private static func withDetails(_ message: String, _ details: String?) -> String {
        guard let details, !details.isEmpty else {
            return message
        }
        return message + "\n" + L10n.errorDetails(details)
    }
}
