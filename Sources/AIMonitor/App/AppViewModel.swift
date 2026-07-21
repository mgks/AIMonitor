import Foundation
import SwiftUI

/// Persistent credential storage. Loads keys eagerly from Keychain at init
/// so they survive view recreation (fixes the "wiped on tab switch" bug).
/// Lives as a single shared object inside AppViewModel.
@MainActor
final class CredentialsStore: ObservableObject {
    @Published var minimaxKey: String = ""
    @Published var zaiKey: String = ""

    private let secrets = KeychainStore()

    init() {
        minimaxKey = secrets.get("minimax.apiKey") ?? ""
        zaiKey = secrets.get("zai.apiKey") ?? ""
    }

    func saveMinimax() {
        if minimaxKey.isEmpty { secrets.remove("minimax.apiKey") }
        else { try? secrets.set(minimaxKey, for: "minimax.apiKey") }
    }

    func saveZai() {
        if zaiKey.isEmpty { secrets.remove("zai.apiKey") }
        else { try? secrets.set(zaiKey, for: "zai.apiKey") }
    }

    var minimaxConfigured: Bool { !minimaxKey.trimmingCharacters(in: .whitespaces).isEmpty }
    var zaiConfigured: Bool { !zaiKey.trimmingCharacters(in: .whitespaces).isEmpty }

    func isConfigured(_ id: String) -> Bool {
        switch id {
        case "minimax": return minimaxConfigured
        case "zai": return zaiConfigured
        default: return false
        }
    }
}

/// Owns provider state, drives refresh, and exposes everything the UI binds to.
@MainActor
final class AppViewModel: ObservableObject {

    @Published public private(set) var statuses: [String: ProviderStatus] = [:]
    @Published public private(set) var errors: [String: String] = [:]
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var lastRefresh: Date?
    @Published public var refreshInterval: TimeInterval = AppSettings.defaultRefreshInterval

    public let providers: [any AIProvider]
    public var credentials = CredentialsStore()

    private let http = HTTPClient()
    private let secrets = KeychainStore()
    private var scheduler: RefreshScheduler?

    public init() {
        self.providers = ProviderRegistry.makeDefault(http: http, secrets: secrets)
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

    /// Providers that are both enabled in prefs AND have credentials entered.
    public var activeProviders: [any AIProvider] {
        providers.filter { isProviderActive($0.id) }
    }

    /// True if at least one provider is enabled and configured.
    public var hasActiveProviders: Bool {
        !activeProviders.isEmpty
    }

    func isProviderEnabled(_ id: String) -> Bool {
        UserDefaults.standard.bool(forKey: "enabled.\(id)")
    }

    func setProviderEnabled(_ id: String, _ on: Bool) {
        UserDefaults.standard.set(on, forKey: "enabled.\(id)")
        objectWillChange.send()
    }

    func isProviderActive(_ id: String) -> Bool {
        isProviderEnabled(id) && credentials.isConfigured(id)
    }

    /// Refresh only active providers. Cached data is retained on failure.
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

    /// The headline percentage for the menu bar summary.
    /// Remaining mode: minimum remaining % across active providers.
    /// Used mode: maximum used % across active providers.
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
