import Foundation
import SwiftUI

/// Owns provider state, drives refresh, and exposes everything the UI binds to.
/// Credential strings live directly here as @Published so SwiftUI bindings
/// ($viewModel.minimaxKey) propagate reliably. Nested ObservableObjects break
/// onChange in this SDK; flattening avoids that entirely.
@MainActor
final class AppViewModel: ObservableObject {

    // MARK: - Credentials (flat @Published for reliable SwiftUI binding)

    @Published public var minimaxKey: String = ""
    @Published public var zaiKey: String = ""

    private let secrets = KeychainStore()

    public var minimaxConfigured: Bool { !minimaxKey.trimmingCharacters(in: .whitespaces).isEmpty }
    public var zaiConfigured: Bool { !zaiKey.trimmingCharacters(in: .whitespaces).isEmpty }

    func isProviderConfigured(_ id: String) -> Bool {
        switch id {
        case "minimax": return minimaxConfigured
        case "zai": return zaiConfigured
        default: return false
        }
    }

    /// Save a key to Keychain. Called from the UI on every change.
    func saveMinimaxKey() {
        let trimmed = minimaxKey.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { secrets.remove("minimax.apiKey") }
        else { try? secrets.set(trimmed, for: "minimax.apiKey") }
        refreshAll()
    }

    func saveZaiKey() {
        let trimmed = zaiKey.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { secrets.remove("zai.apiKey") }
        else { try? secrets.set(trimmed, for: "zai.apiKey") }
        refreshAll()
    }

    // MARK: - Provider status state

    @Published public private(set) var statuses: [String: ProviderStatus] = [:]
    @Published public private(set) var errors: [String: String] = [:]
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var lastRefresh: Date?
    @Published public var refreshInterval: TimeInterval = AppSettings.defaultRefreshInterval

    public let providers: [any AIProvider]
    private let http = HTTPClient()
    private var scheduler: RefreshScheduler?

    public init() {
        // Load existing keys from Keychain so they appear on launch.
        let kc = KeychainStore()
        self.minimaxKey = kc.get("minimax.apiKey") ?? ""
        self.zaiKey = kc.get("zai.apiKey") ?? ""

        self.providers = ProviderRegistry.makeDefault(http: http, secrets: KeychainStore())
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

        isRefreshing = true
        Task { [weak self] in
            await withTaskGroup(of: (String, ProviderStatus?, String?).self) { group in
                for provider in targets {
                    group.addTask {
                        do {
                            let status = try await provider.fetchStatus()
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

    // MARK: - Summary

    /// Providers opted into the menu bar summary. Stored as a comma list.
    private static let summaryKey = "summaryProviders"

    var summaryProviders: Set<String> {
        let raw = UserDefaults.standard.string(forKey: Self.summaryKey) ?? ""
        return Set(raw.split(separator: ",").map(String.init))
    }

    func isProviderInSummary(_ id: String) -> Bool {
        // Default: all active providers show in summary.
        if UserDefaults.standard.object(forKey: Self.summaryKey) == nil {
            return isProviderActive(id)
        }
        return summaryProviders.contains(id)
    }

    func setProviderInSummary(_ id: String, _ on: Bool) {
        var set = summaryProviders
        if on { set.insert(id) } else { set.remove(id) }
        UserDefaults.standard.set(set.sorted().joined(separator: ","), forKey: Self.summaryKey)
        objectWillChange.send()
    }

    /// Summary rows for the menu bar label: short name + percent for each
    /// active provider opted into the summary.
    struct SummaryRow: Identifiable {
        let id: String
        let shortName: String
        let percent: Double
        let state: QuotaState
    }

    var summaryRows: [SummaryRow] {
        let showUsed = UserDefaults.standard.string(forKey: AppSettings.Keys.summaryMode) ?? "remaining" == "used"
        return activeProviders.filter { isProviderInSummary($0.id) }.compactMap { provider in
            guard let pct = statuses[provider.id]?.snapshot.remainingPercent else { return nil }
            let displayed = showUsed ? 100 - pct : pct
            let name = statuses[provider.id]?.shortName ?? provider.displayName
            return SummaryRow(
                id: provider.id,
                shortName: name,
                percent: displayed,
                state: QuotaThresholds.state(forPercent: pct)
            )
        }
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
