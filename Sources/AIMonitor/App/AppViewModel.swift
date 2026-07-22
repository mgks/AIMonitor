import Foundation
import SwiftUI
import UserNotifications

/// Owns provider state, drives refresh, and exposes everything the UI binds to.
/// Credential strings live directly here as @Published so SwiftUI bindings
/// propagate reliably. Keys are stored via CredentialStore (file-based, no
/// keychain prompts ever).
@MainActor
final class AppViewModel: ObservableObject {

    // MARK: - Credentials

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

    func saveKey(_ value: String, account: String) {
        CredentialStore.shared.set(value, for: account)
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
    @Published public var summaryMode: String = UserDefaults.standard.string(forKey: AppSettings.Keys.summaryMode) ?? "remaining"

    /// Tracks the last known percent per provider to detect threshold crossings.
    private var lastPercent: [String: Double] = [:]

    public let providers: [any AIProvider]
    private let http = HTTPClient()
    private var scheduler: RefreshScheduler?

    public init() {
        let cs = CredentialStore.shared
        self.minimaxKey = cs.get("minimax.apiKey") ?? ""
        self.zaiKey = cs.get("zai.apiKey") ?? ""
        self.kimiKey = cs.get("kimi.apiKey") ?? ""
        self.deepSeekKey = cs.get("deepseek.apiKey") ?? ""
        self.openRouterKey = cs.get("openrouter.apiKey") ?? ""

        self.providers = ProviderRegistry.makeDefault(http: http, secrets: CredentialStore.shared)
        self.scheduler = RefreshScheduler(interval: AppSettings.defaultRefreshInterval) { [weak self] in
            self?.refreshAll()
        }

        // Request notification permission on first launch.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
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
        return isProviderConfigured(id)
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
                        self.checkThresholds(for: id, status: status)
                    } else if let error {
                        self.errors[id] = error
                    }
                }
            }
            self?.lastRefresh = Date()
            self?.isRefreshing = false
        }
    }

    // MARK: - Notifications

    /// Check if a provider crossed a notification threshold and fire an alert.
    private func checkThresholds(for id: String, status: ProviderStatus) {
        guard let pct = status.snapshot.remainingPercent else { return }
        let prev = lastPercent[id]
        lastPercent[id] = pct

        let name = status.displayName
        let notifyUnder20 = UserDefaults.standard.bool(forKey: AppSettings.Keys.notifyUnder20)
        let notifyUnder10 = UserDefaults.standard.bool(forKey: AppSettings.Keys.notifyUnder10)
        let notifyExhausted = UserDefaults.standard.bool(forKey: AppSettings.Keys.notifyExhausted)

        // Only notify on the DOWNWARD crossing (was above, now below).
        if let prev, prev > pct {
            if pct <= 0 && notifyExhausted {
                fireNotification(title: "\(name)", body: "Quota exhausted. No requests remaining.")
            } else if pct < 10 && prev >= 10 && notifyUnder10 {
                fireNotification(title: "\(name)", body: "Only \(Int(pct))% remaining.")
            } else if pct < 20 && prev >= 20 && notifyUnder20 {
                fireNotification(title: "\(name)", body: "Under 20% remaining (\(Int(pct))%).")
            }
        }

        // Notify on upward crossing (quota reset/restored).
        let notifyReset = UserDefaults.standard.bool(forKey: AppSettings.Keys.notifyReset)
        if let prev, prev < pct, prev <= 5, pct > 20, notifyReset {
            fireNotification(title: "\(name)", body: "Quota reset. \(Int(pct))% available again.")
        }
    }

    private func fireNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Summary (single selected provider)

    var summaryProviderID: String {
        let stored = UserDefaults.standard.string(forKey: AppSettings.Keys.summaryProvider) ?? ""
        if !stored.isEmpty { return stored }
        return activeProviders.first?.id ?? ""
    }

    func setSummaryProvider(_ id: String) {
        UserDefaults.standard.set(id, forKey: AppSettings.Keys.summaryProvider)
        objectWillChange.send()
    }

    /// Toggle summaryMode and persist immediately so the menu bar updates.
    func setSummaryMode(_ mode: String) {
        summaryMode = mode
        UserDefaults.standard.set(mode, forKey: AppSettings.Keys.summaryMode)
        objectWillChange.send()
    }

    var summaryRow: SummaryRow? {
        let id = summaryProviderID
        guard !id.isEmpty,
              let status = statuses[id],
              let pct = status.snapshot.remainingPercent else { return nil }
        let displayed = summaryMode == "used" ? 100 - pct : pct
        return SummaryRow(
            id: id,
            shortName: status.shortName,
            percent: displayed,
            state: QuotaThresholds.state(forPercent: pct)
        )
    }

    struct SummaryRow: Identifiable {
        let id: String
        let shortName: String
        let percent: Double
        let state: QuotaState
    }

    public var worstState: QuotaState {
        activeProviders
            .compactMap { statuses[$0.id]?.state }
            .max(by: { $0.severity < $1.severity }) ?? .unknown
    }
}
