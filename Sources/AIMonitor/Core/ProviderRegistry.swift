import Foundation

/// Builds the active provider list. Each provider is constructed with shared
/// HTTP and secret stores so credentials and connection reuse are centralised.
public enum ProviderRegistry {

    /// The default provider set, ordered by popularity. New providers plug in here only.
    @MainActor
    public static func makeDefault(http: HTTPClient, secrets: KeychainStore) -> [any AIProvider] {
        [
            // Most popular first.
            OpenRouterProvider(http: http, secrets: secrets),
            DeepSeekProvider(http: http, secrets: secrets),
            MiniMaxProvider(http: http, secrets: secrets),
            ZaiProvider(http: http, secrets: secrets)
        ]
    }
}
