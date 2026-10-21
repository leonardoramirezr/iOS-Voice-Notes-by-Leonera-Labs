import Foundation

/// The Simplenote session: the account e-mail and the Simperium sync token.
public struct Credentials: Codable, Equatable, Sendable {
    public let username: String
    public let token: String

    public init(username: String, token: String) {
        self.username = username
        self.token = token
    }
}

/// Persists the Simplenote session in the Keychain (Simperium's token mode stores nothing itself).
public struct CredentialsStore: Sendable {
    private let item: KeychainItem

    public init(service: String = "com.leonardoramirezr.voicenotesbyleoneralabs.simplenote") {
        item = KeychainItem(service: service, account: "session")
    }

    public func load() -> Credentials? {
        item.read().flatMap { try? JSONDecoder().decode(Credentials.self, from: $0) }
    }

    public func save(_ credentials: Credentials) throws {
        try item.write(JSONEncoder().encode(credentials))
    }

    public func delete() {
        item.delete()
    }
}
