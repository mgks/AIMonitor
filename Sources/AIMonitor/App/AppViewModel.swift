import Foundation
import SwiftUI

/// Owns provider state, drives refresh, and exposes everything the UI binds to.
/// Credential strings live directly here as @Published so SwiftUI bindings
/// ($viewModel.minimaxKey) propagate reliably. Nested ObservableObjects break
/// onChange in this SDK; flattening avoids that entirely.
@MainActor
final class AppViewModel: ObservableObject {

    // MARK: - Credentials (flat @Published for reliable SwiftUI binding)
    // All credential strings are loaded once at init from the shared KeychainStore
    // and saved back through it. One keychain prompt for all keys, not per-key.

    @Published public var minimaxKey: String = ""
    @Published public var zaiKey: String = ""
    @Published public var kimiKey: String = ""
    @Published public var deepSeekKey: String = ""
    @Published public var openRouterKey: String = ""

    public var minimaxConfigured: Bool { !minimaxKey.trimmingCharacters(in: .whitespaces).isEmpty }
    public var zaiConfigured: Bool { !zaiKey.trimmingCharacters(in: .whitespaces).isEmpty }
    public var kimiConfigured: Bool { !kimiKey.trimmingCharacters(in: .whitespaces).isEmpty }
    public var deepSeekConfigured: Bool { !deepSeekKey.trimmingCharacters(in: .whitespaces).isEmpty }
    public var openRouterConfigured: Bool { !openRouterKey.trimmingCharacters(in: .whitespaces).isEmpty }

    func isProviderConfigured(_ id: String) -> Bool {
        switch id {
        case "claude": return OAuthReader.load(CredentialSchema(
            fileSubpath: ".claude/.credentials.json",
            keychainService: "Claude Code-credentials")) != nil
        case "codex": return OAuthReader.load(CredentialSchema(
            fileSubpath: ".codex/auth.json",
            oauthObjectKey: "",
            accessTokenKey: "access_token",
            refreshTokenKey: "refresh_token",
            expiresAtKey: "expires_at")) != nil
        case "kimi": return kimiConfigured
        case "minimax": return minimaxConfigured
        case "zai": return zaiConfigured
        case "deepseek": return deepSeekConfigured
        case "openrouter": return openRouterConfigured
        default: return false
        }
    }

    /// Generic key saver used by all API-key providers.
    func saveKey(_ value: String, account: String) {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { KeychainStore.shared.remove(account) }
        else { try? KeychainStore.shared.set(trimmed, for: account) }
        refreshAll()
    }

    func saveMinimaxKey() { saveKey(minimaxKey, account: "minimax.apiKey") }
    func saveZaiKey() { saveKey(zaiKey, account: "zai.apiKey") }
    func saveKimiKey() { saveKey(kimiKey, account: "kimi.apiKey") }
    func saveDeepSeekKey() { saveKey(deepSeekKey, account: "deepseek.apiKey") }
    func saveOpenRouterKey() { saveKey(openRouterKey, account: "openrouter.apiKey") }

    // MARK: - Provider status state

    @Published public private(set) var statuses: [String: ProviderStatus] = [:]
    @Published public private(set) var errors: [String: String] = [:]
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var lastRefresh: Date?
    @Published public var refreshInterval: TimeInterval = AppSettings.defaultRefreshInterval
    @Published public var showSummary: Bool = UserDefaults.standard.bool(forKey: AppSettings.Keys.showSummary)

    public let providers: [any AIProvider]
    private let http = HTTPClient()
    private var scheduler: RefreshScheduler?

    public init() {
        // Load ALL keys once from the shared KeychainStore. One prompt total.
        let kc = KeychainStore.shared
        self.minimaxKey = kc.get("minimax.apiKey") ?? ""
        self.zaiKey = kc.get("zai.apiKey") ?? ""
        self.kimiKey = kc.get("kimi.apiKey") ?? ""
        self.deepSeekKey = kc.get("deepseek.apiKey") ?? ""
        self.openRouterKey = kc.get("openrouter.apiKey") ?? ""

        self.providers = ProviderRegistry.makeDefault(http: http, secrets: KeychainStore.shared)
        self.scheduler = RefreshScheduler(interval: AppSettings.defaultRefreshInterval) { [weak self] in
            self?.refreshAll()
        }
    }

    public func start() {
        refreshAll()
        scheduler?.start()
    }

    public func applyRefreshInterval(_ value: TimeInterval) {
        refreshInterval = value
        scheduler?.setInterval(value)
    }

    // MARK: - Active providers

    /// Providers that are both enabled in prefs AND have credentials entered.
    public var activeProviders: [any AIProvider] {
        providers.filter { isProviderActive($0.id) }
    }

    public var hasActiveProviders: Bool {
        !activeProviders.isEmpty
    }

    private static let enabledKey = "enabledProviders"

    private var enabledOverrides: [String: Bool] {
        let raw = UserDefaults.standard.string(forKey: Self.enabledKey) ?? ""
        var dict: [String: Bool] = [:]
        for pair in raw.split(separator: ",") {
            let parts = pair.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            dict[String(parts[0])] = parts[1] == "1"
        }
        return dict
    }

    func isProviderEnabled(_ id: String) -> Bool {
        if let override = enabledOverrides[id] { return override }
        return isProviderConfigured(id)   // default ON when key present
    }

    func setProviderEnabled(_ id: String, _ on: Bool) {
        var overrides = enabledOverrides
        overrides[id] = on
        let raw = overrides.sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value ? "1" : "0")" }
            .joined(separator: ",")
        UserDefaults.standard.set(raw, forKey: Self.enabledKey)
        objectWillChange.send()
        refreshAll()
    }

    func isProviderActive(_ id: String) -> Bool {
        isProviderEnabled(id) && isProviderConfigured(id)
    }

    // MARK: - Refresh

    public func refreshAll() {
        guard !isRefreshing else { return }
        let targets = activeProviders
        guard !targets.isEmpty else { return }

        // Build a key lookup from the in-memory cached keys.
        // This avoids ANY keychain access during refresh.
        let keyMap: [String: String] = [
            "minimax": minimaxKey,
            "zai": zaiKey,
            "kimi": kimiKey,
            "deepseek": deepSeekKey,
            "openrouter": openRouterKey
        ]

        isRefreshing = true
        Task { [weak self] in
            await withTaskGroup(of: (String, ProviderStatus?, String?).self) { group in
                for provider in targets {
                    let key = keyMap[provider.id] ?? ""
                    group.addTask {
                        do {
                            let status = try await provider.fetchStatus(apiKey: key)
                            return (provider.id, status, nil)
                        } catch {
                            return (provider.id, nil, error.localizedDescription)
                        }
                    }
                }
                for await (id, status, error) in group {
                    guard let self else { continue }
                    if let status {
                        self.statuses[id] = status
                        self.errors.removeValue(forKey: id)
                    } else if let error {
                        self.errors[id] = error
                    }
                }
            }
            self?.lastRefresh = Date()
            self?.isRefreshing = false
        }
    }

    // MARK: - Summary (single selected provider)

    /// Which provider to show in the menu bar summary. Defaults to first active.
    var summaryProviderID: String {
        let stored = UserDefaults.standard.string(forKey: AppSettings.Keys.summaryProvider) ?? ""
        if !stored.isEmpty { return stored }
        return activeProviders.first?.id ?? ""
    }

    func setSummaryProvider(_ id: String) {
        UserDefaults.standard.set(id, forKey: AppSettings.Keys.summaryProvider)
        objectWillChange.send()
    }

    /// The single summary row for the menu bar label.
    struct SummaryRow: Identifiable {
        let id: String
        let shortName: String
        let percent: Double
        let state: QuotaState
    }

    var summaryRow: SummaryRow? {
        let id = summaryProviderID
        guard !id.isEmpty,
              let status = statuses[id],
              let pct = status.snapshot.remainingPercent else { return nil }
        let showUsed = UserDefaults.standard.string(forKey: AppSettings.Keys.summaryMode) ?? "remaining" == "used"
        let displayed = showUsed ? 100 - pct : pct
        return SummaryRow(
            id: id,
            shortName: status.shortName,
            percent: displayed,
            state: QuotaThresholds.state(forPercent: pct)
        )
    }

    /// Legacy single headline percent (worst case), kept for compatibility.
    public var summaryPercent: Double? {
        let pcts = activeProviders.compactMap { statuses[$0.id]?.snapshot.remainingPercent }
        guard !pcts.isEmpty else { return nil }

        let showUsed = UserDefaults.standard.string(forKey: AppSettings.Keys.summaryMode) ?? "remaining" == "used"
        if showUsed {
            return pcts.map { 100 - $0 }.max()
        } else {
            return pcts.min()
        }
    }

    public var worstState: QuotaState {
        activeProviders
            .compactMap { statuses[$0.id]?.state }
            .max(by: { $0.severity < $1.severity }) ?? .unknown
    }
}
