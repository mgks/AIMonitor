import Foundation

/// Builds the active provider list. Each provider is constructed with shared
/// HTTP and secret stores so credentials and connection reuse are centralised.
public enum ProviderRegistry {

    /// The default provider set, ordered by popularity. New providers plug in here only.
    @MainActor
    public static func makeDefault(http: HTTPClient, secrets: CredentialStore) -> [any AIProvider] {
        [
            // OAuth-based coding plans (most popular, read CLI credentials).
            ClaudeProvider(http: http, secrets: secrets),
            CodexProvider(http: http, secrets: secrets),
            // API-key coding plans.
            KimiProvider(http: http, secrets: secrets),
            MiniMaxProvider(http: http, secrets: secrets),
            ZaiProvider(http: http, secrets: secrets),
            // Pay-as-you-go balance providers.
            DeepSeekProvider(http: http, secrets: secrets),
            OpenRouterProvider(http: http, secrets: secrets)
        ]
    }
}
