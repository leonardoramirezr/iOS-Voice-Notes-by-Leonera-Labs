import Foundation
import Security

/// A generic-password Keychain item that is only readable on this device after the first unlock.
public struct KeychainItem: Sendable {
    public let service: String
    public let account: String

    public init(service: String, account: String) {
        self.service = service
        self.account = account
    }

    public struct Failure: Error, Equatable {
        public let status: OSStatus
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func read() -> Data? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
            return nil
        }
        return result as? Data
    }

    public func write(_ data: Data) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let addStatus = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw Failure(status: addStatus)
            }
        } else if status != errSecSuccess {
            throw Failure(status: status)
        }
    }

    public func delete() {
        SecItemDelete(query as CFDictionary)
    }

    public func readString() -> String? {
        read().flatMap { String(data: $0, encoding: .utf8) }
    }

    public func writeString(_ value: String) throws {
        try write(Data(value.utf8))
    }
}
