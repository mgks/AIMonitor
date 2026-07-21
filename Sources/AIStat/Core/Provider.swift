import Foundation

/// Static description of a provider: identity, endpoints, auth requirements.
/// Immutable and Sendable so it can be shared across tasks safely.
public struct ProviderConfiguration: Sendable, Equatable {
    public let id: String
    public let displayName: String
    public let symbolName: String            // SF Symbol used for the card glyph
    public let defaultBaseURL: URL
    public let requiresAPIKey: Bool
    public let supportsSessionToken: Bool

    public init(
        id: String,
        displayName: String,
        symbolName: String,
        defaultBaseURL: URL,
        requiresAPIKey: Bool = true,
        supportsSessionToken: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.symbolName = symbolName
        self.defaultBaseURL = defaultBaseURL
        self.requiresAPIKey = requiresAPIKey
        self.supportsSessionToken = supportsSessionToken
    }
}

/// Errors a provider can surface. Kept small and user-readable.
public enum ProviderError: LocalizedError, Sendable {
    case notConfigured
    case missingCredential(String)
    case unauthorized
    case rateLimited
    case transport(String)
    case decode(String)
    case http(Int)

    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "Provider is not configured."
        case .missingCredential(let name): return "Missing \(name)."
        case .unauthorized: return "Invalid or expired API key."
        case .rateLimited: return "Rate limited by provider."
        case .transport(let msg): return "Network error: \(msg)"
        case .decode(let msg): return "Could not parse response: \(msg)"
        case .http(let code): return "Provider returned HTTP \(code)."
        }
    }

    /// Map an HTTP status code to the most specific provider error.
    public static func fromStatus(_ code: Int) -> ProviderError {
        switch code {
        case 401, 403: return .unauthorized
        case 429: return .rateLimited
        default: return .http(code)
        }
    }
}

/// Every provider is self-contained: it owns how to fetch and parse its own
/// quota data and returns a normalised ProviderStatus. No provider knows about
/// another. Caching and display live in the view model; refresh + parse live here.
public protocol AIProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var symbolName: String { get }

    /// True when enough credentials exist to attempt a fetch.
    var isConfigured: Bool { get }

    /// Fetch fresh data from the provider and parse it into a ProviderStatus.
    /// Implementations should never crash on malformed input; throw on failure.
    func fetchStatus() async throws -> ProviderStatus
}
