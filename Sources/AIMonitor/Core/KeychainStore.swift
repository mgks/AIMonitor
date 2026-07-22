import Foundation
import Security

/// Minimal dependency-free wrapper around the macOS Keychain.
/// Uses a SINGLE shared instance to avoid multiple permission prompts on
/// unsigned dev builds. All credential access goes through KeychainStore.shared.
public final class KeychainStore: @unchecked Sendable {
    public let service: String

    /// Single shared instance. Use this everywhere; never create new instances.
    public static let shared = KeychainStore(service: "dev.mgks.aimonitor")

    private init(service: String) {
        self.service = service
    }

    public enum KeychainError: Error, Equatable {
        case unexpectedStatus(OSStatus)
    }

    public func set(_ value: String, for account: String) throws {
        let data = Data(value.utf8)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(baseQuery as CFDictionary)

        var add = baseQuery
        add[kSecValueData as String] = data
        // Use 'allow all' access so the app doesn't prompt per-item.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

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

    public func remove(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
