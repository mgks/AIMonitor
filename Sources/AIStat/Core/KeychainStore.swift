import Foundation
import Security

/// Minimal dependency-free wrapper around the macOS Keychain.
/// Stores API keys and optional session cookies per provider account.
/// A value type (struct) so it is Sendable and safe to share across tasks.
public struct KeychainStore: Sendable {
    public let service: String

    public init(service: String = "dev.mgks.aistat") {
        self.service = service
    }

    public enum KeychainError: Error, Equatable {
        case unexpectedStatus(OSStatus)
    }

    /// Store a secret, overwriting any existing value for the same account.
    public func set(_ value: String, for account: String) throws {
        let data = Data(value.utf8)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        // Remove any prior entry so the write is an overwrite.
        SecItemDelete(baseQuery as CFDictionary)

        var add = baseQuery
        add[kSecValueData as String] = data
        // Readable after first unlock; survives reboot for background refresh.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    /// Read a secret. Returns nil if absent rather than throwing.
    public func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Delete a secret. No-op if absent.
    public func remove(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
