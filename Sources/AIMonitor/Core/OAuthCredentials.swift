import Foundation
#if canImport(Security)
import Security
#endif

/// Universal OAuth credentials reader for providers that store their tokens
/// in a JSON file on disk (e.g. ~/.claude/.credentials.json, ~/.codex/auth.json).
/// Each provider defines its file location and JSON shape via a CredentialSchema.
///
/// On macOS, some providers (notably Claude Code) may store credentials in the
/// login Keychain instead of the file. We check the file first, then Keychain.
public struct OAuthCredentials: Codable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAtMs: Int64        // epoch milliseconds
    public var raw: [String: String]     // extra fields preserved for write-back

    public var expiresAt: Date { Date(timeIntervalSince1970: TimeInterval(expiresAtMs) / 1000) }
    public var needsRefresh: Bool {
        expiresAt <= Date().addingTimeInterval(300)   // 5-min buffer
    }
    public var canRefresh: Bool { !refreshToken.isEmpty }

    public init(accessToken: String, refreshToken: String, expiresAtMs: Int64) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAtMs = expiresAtMs
        self.raw = [:]
    }
}

/// Describes where a provider stores its OAuth tokens and how to extract them.
public struct CredentialSchema: Sendable {
    public let fileSubpath: String          // e.g. ".claude/.credentials.json"
    public let keychainService: String?     // Keychain item service, or nil
    /// JSON path to the OAuth object (keys into the parsed JSON tree).
    public let oauthObjectKey: String       // e.g. "claudeAiOauth"
    public let accessTokenKey: String       // e.g. "accessToken"
    public let refreshTokenKey: String      // e.g. "refreshToken"
    public let expiresAtKey: String         // e.g. "expiresAt"

    public init(fileSubpath: String,
                keychainService: String? = nil,
                oauthObjectKey: String = "claudeAiOauth",
                accessTokenKey: String = "accessToken",
                refreshTokenKey: String = "refreshToken",
                expiresAtKey: String = "expiresAt") {
        self.fileSubpath = fileSubpath
        self.keychainService = keychainService
        self.oauthObjectKey = oauthObjectKey
        self.accessTokenKey = accessTokenKey
        self.refreshTokenKey = refreshTokenKey
        self.expiresAtKey = expiresAtKey
    }
}

/// Reads OAuth credentials for a provider from file or Keychain.
public enum OAuthReader {

    /// Try to load credentials. Checks file first, then Keychain on macOS.
    public static func load(_ schema: CredentialSchema) -> OAuthCredentials? {
        if let fromFile = loadFromFile(schema) { return fromFile }
        if let kc = schema.keychainService, let fromKC = loadFromKeychain(schema, service: kc) {
            return fromKC
        }
        return nil
    }

    /// Read from the JSON file at ~/.<fileSubpath>.
    static func loadFromFile(_ schema: CredentialSchema) -> OAuthCredentials? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = "\(home)/\(schema.fileSubpath)"
        guard FileManager.default.fileExists(atPath: path),
              let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return parse(json, schema: schema)
    }

    /// Read from macOS Keychain (generic password item matching the service).
    static func loadFromKeychain(_ schema: CredentialSchema, service: String) -> OAuthCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return parse(json, schema: schema)
    }

    /// Extract OAuthCredentials from a parsed JSON tree.
    static func parse(_ json: [String: Any], schema: CredentialSchema) -> OAuthCredentials? {
        // Some files nest the OAuth object under a key (e.g. claudeAiOauth);
        // others are flat. Check both.
        let target: [String: Any]?
        if let nested = json[schema.oauthObjectKey] as? [String: Any] {
            target = nested
        } else if json[schema.accessTokenKey] != nil {
            target = json
        } else {
            target = nil
        }
        guard let obj = target,
              let accessToken = obj[schema.accessTokenKey] as? String,
              !accessToken.isEmpty
        else { return nil }

        let refreshToken = obj[schema.refreshTokenKey] as? String ?? ""
        // expiresAt may be a number (ms) or a numeric string.
        let expiresAt: Int64
        if let n = obj[schema.expiresAtKey] as? Int64 {
            expiresAt = n
        } else if let n = obj[schema.expiresAtKey] as? Int {
            expiresAt = Int64(n)
        } else if let n = obj[schema.expiresAtKey] as? Double {
            expiresAt = Int64(n)
        } else if let s = obj[schema.expiresAtKey] as? String, let n = Int64(s) {
            expiresAt = n
        } else {
            expiresAt = 0
        }

        var creds = OAuthCredentials(accessToken: accessToken,
                                     refreshToken: refreshToken,
                                     expiresAtMs: expiresAt)
        // Preserve known fields for plan label extraction.
        if let sub = obj["subscriptionType"] as? String { creds.raw["subscriptionType"] = sub }
        if let tier = obj["rateLimitTier"] as? String { creds.raw["rateLimitTier"] = tier }
        return creds
    }
}
