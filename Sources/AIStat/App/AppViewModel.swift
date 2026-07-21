import Foundation
import SwiftUI

/// Owns provider state, drives refresh, and exposes everything the UI binds to.
/// @MainActor because all published state is consumed by SwiftUI views.
@MainActor
public final class AppViewModel: ObservableObject {

    // Cards read from these. statuses is the last known good status per provider.
    @Published public private(set) var statuses: [String: ProviderStatus] = [:]
    @Published public private(set) var errors: [String: String] = [:]
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var lastRefresh: Date?
    @Published public var refreshInterval: TimeInterval = AppSettings.defaultRefreshInterval

    public let providers: [any AIProvider]
    private let http: HTTPClient
    private let secrets: KeychainStore
    private var scheduler: RefreshScheduler?

    public init() {
        let http = HTTPClient()
        let secrets = KeychainStore()
        self.http = http
        self.secrets = secrets
        self.providers = ProviderRegistry.makeDefault(http: http, secrets: secrets)
        self.scheduler = RefreshScheduler(interval: AppSettings.defaultRefreshInterval) { [weak self] in
            self?.refreshAll()
        }
    }

    /// Start the app: refresh immediately, then begin the periodic timer.
    public func start() {
        refreshAll()
        scheduler?.start()
    }

    /// Apply a new interval from preferences and keep the timer in sync.
    public func applyRefreshInterval(_ value: TimeInterval) {
        refreshInterval = value
        scheduler?.setInterval(value)
    }

    /// Refresh every provider concurrently. Cached data is retained on failure.
    public func refreshAll() {
        guard !isRefreshing else { return }
        isRefreshing = true

        let snapshot = providers
        Task { [weak self] in
            await withTaskGroup(of: (String, ProviderStatus?, String?).self) { group in
                for provider in snapshot {
                    group.addTask {
                        do {
                            let status = try await provider.fetchStatus()
                            return (provider.id, status, nil)
                        } catch {
                            // Keep the previous cache; surface the error text instead.
                            return (provider.id, nil, error.localizedDescription)
                        }
                    }
                }
                for await (id, status, error) in group {
                    guard let self else { continue }
                    if let status {
                        self.statuses[id] = status
                        self.errors.removeValue(forKey: id)
                    } else if self.statuses[id] == nil, let error {
                        // No cache yet: show an error placeholder so the card is not empty.
                        self.statuses[id] = Self.errorStatus(for: snapshot.first { $0.id == id }, error: error)
                        self.errors[id] = error
                    } else if let error {
                        self.errors[id] = error
                    }
                }
            }
            self?.lastRefresh = Date()
            self?.isRefreshing = false
        }
    }

    /// The worst-case percent across all providers, used for the menu bar label.
    public var worstRemainingPercent: Double? {
        statuses.values.compactMap { $0.snapshot.remainingPercent }.min()
    }

    /// The worst-case state, used for the menu bar dot colour.
    public var worstState: QuotaState {
        statuses.values.map(\.state).max(by: { $0.severity < $1.severity }) ?? .unknown
    }

    private static func errorStatus(for provider: (any AIProvider)?, error: String) -> ProviderStatus {
        ProviderStatus(
            providerID: provider?.id ?? "",
            displayName: provider?.displayName ?? "Unknown",
            state: .error,
            lastUpdated: Date(),
            lastError: error
        )
    }
}
