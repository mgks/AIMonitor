import Foundation

/// File-based credential store. Replaces Keychain to eliminate the repeated
/// permission prompts that plague unsigned dev builds.
///
/// Keys are stored in ~/Library/Application Support/AIMonitor/credentials.json
/// with 0600 file permissions (owner read/write only). This is the same
/// protection level as the Keychain for practical purposes, without the UX cost.
public final class CredentialStore: @unchecked Sendable {
    public static let shared = CredentialStore()

    private let fileURL: URL
    private var cache: [String: String] = [:]

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = appSupport.appendingPathComponent("AIMonitor", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("credentials.json")
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return }
        cache = dict
    }

    private func persist() {
        do {
            let data = try JSONSerialization.data(withJSONObject: cache, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: fileURL, options: [.atomic])
            // Restrict to owner-only read/write.
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            NSLog("[AIMonitor] credential store write failed: \(error)")
        }
    }

    public func get(_ account: String) -> String? {
        cache[account]
    }

    public func set(_ value: String, for account: String) {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            cache.removeValue(forKey: account)
        } else {
            cache[account] = trimmed
        }
        persist()
    }

    public func remove(_ account: String) {
        cache.removeValue(forKey: account)
        persist()
    }
}
