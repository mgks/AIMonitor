import Foundation

/// Aggregate health of a provider as AIMonitor understands it.
/// Drives the colour of the menu bar dot and the card's status line.
public enum QuotaState: String, Codable, Sendable {
    case healthy     // plenty of quota remaining
    case warning     // approaching limits
    case critical    // nearly exhausted
    case exhausted   // no quota remaining
    case unknown     // not enough data yet
    case error       // last refresh failed

    /// Sort weight: worst state first, used to pick the menu bar colour.
    public var severity: Int {
        switch self {
        case .error, .exhausted: return 4
        case .critical: return 3
        case .warning: return 2
        case .healthy: return 1
        case .unknown: return 0
        }
    }
}

/// A single normalised quota signal produced by a provider.
/// Built from official APIs, rate-limit headers, or balance endpoints.
public struct QuotaSnapshot: Codable, Sendable, Equatable {
    public var remainingPercent: Double?      // 0...100
    public var remainingRequests: Int?
    public var totalRequests: Int?
    public var remainingTokens: Int?
    public var totalTokens: Int?
    public var creditsRemaining: Double?      // account balance in provider currency
    public var currency: String?              // ISO code, e.g. "USD"
    public var resetsAt: Date?                // 5h / interval window reset
    public var weeklyResetsAt: Date?          // weekly window reset (if any)
    public var windowLabel: String?           // "5h window", "Weekly", "120 RPM"
    public var rawHeaders: [String: String]   // captured rate-limit headers for debugging

    public init(
        remainingPercent: Double? = nil,
        remainingRequests: Int? = nil,
        totalRequests: Int? = nil,
        remainingTokens: Int? = nil,
        totalTokens: Int? = nil,
        creditsRemaining: Double? = nil,
        currency: String? = nil,
        resetsAt: Date? = nil,
        weeklyResetsAt: Date? = nil,
        windowLabel: String? = nil,
        rawHeaders: [String: String] = [:]
    ) {
        self.remainingPercent = remainingPercent
        self.remainingRequests = remainingRequests
        self.totalRequests = totalRequests
        self.remainingTokens = remainingTokens
        self.totalTokens = totalTokens
        self.creditsRemaining = creditsRemaining
        self.currency = currency
        self.resetsAt = resetsAt
        self.windowLabel = windowLabel
        self.rawHeaders = rawHeaders
    }

    /// Build a snapshot from standard OpenAI-style rate-limit response headers.
    /// All header keys must already be lowercased.
    public static func fromRateLimitHeaders(_ headers: [String: String]) -> QuotaSnapshot {
        func str(_ k: String) -> String? { headers[k.lowercased()] }
        func int(_ k: String) -> Int? { str(k).flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } }

        let remReq = int("x-ratelimit-remaining-requests")
        let limReq = int("x-ratelimit-limit-requests")
        let remTok = int("x-ratelimit-remaining-tokens")
        let limTok = int("x-ratelimit-limit-tokens")

        let pct: Double? = {
            if let r = remReq, let l = limReq, l > 0 { return Double(r) / Double(l) * 100 }
            if let r = remTok, let l = limTok, l > 0 { return Double(r) / Double(l) * 100 }
            return nil
        }()

        let resetString = str("x-ratelimit-reset-requests") ?? str("x-ratelimit-reset-tokens")
        let resetDate = resetString.flatMap { parseResetDuration($0) }

        // Keep the quota-relevant headers for the debug view.
        let quotaHeaders = headers.filter {
            $0.key.hasPrefix("x-ratelimit") || $0.key.contains("quota") || $0.key.contains("remaining")
        }

        var snap = QuotaSnapshot(
            remainingPercent: pct,
            remainingRequests: remReq,
            totalRequests: limReq,
            remainingTokens: remTok,
            totalTokens: limTok,
            resetsAt: resetDate,
            rawHeaders: quotaHeaders
        )
        if limReq != nil { snap.windowLabel = "Requests" }
        else if limTok != nil { snap.windowLabel = "Tokens" }
        return snap
    }

    /// Parse OpenAI-style reset durations: "1s", "500ms", "6m0s", "1h".
    private static func parseResetDuration(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return nil }

        // Plain seconds, possibly a decimal: "1.5"
        if let secs = Double(trimmed) { return Date().addingTimeInterval(secs) }

        // "500ms"
        if trimmed.hasSuffix("ms"), let ms = Double(trimmed.dropLast(2)) {
            return Date().addingTimeInterval(ms / 1000)
        }

        // Walk the string for h/m/s tokens.
        var seconds: Double = 0
        var num = ""
        for ch in trimmed {
            if ch.isNumber || ch == "." { num.append(ch); continue }
            switch ch {
            case "h": seconds += (Double(num) ?? 0) * 3600
            case "m": seconds += (Double(num) ?? 0) * 60
            case "s": seconds += (Double(num) ?? 0)
            default: break
            }
            num = ""
        }
        return seconds > 0 ? Date().addingTimeInterval(seconds) : nil
    }
}

/// The full status a provider card renders from. Maps directly to the spec's data model.
public struct ProviderStatus: Codable, Sendable, Equatable {
    public var providerID: String
    public var displayName: String
    public var shortName: String             // compact label for menu bar summary
    public var model: String?
    public var state: QuotaState
    public var snapshot: QuotaSnapshot
    public var latency: TimeInterval?       // seconds for the last fetch
    public var lastUpdated: Date?
    public var lastError: String?

    public init(
        providerID: String,
        displayName: String,
        shortName: String = "",
        model: String? = nil,
        state: QuotaState = .unknown,
        snapshot: QuotaSnapshot = QuotaSnapshot(),
        latency: TimeInterval? = nil,
        lastUpdated: Date? = nil,
        lastError: String? = nil
    ) {
        self.providerID = providerID
        self.displayName = displayName
        self.shortName = shortName.isEmpty ? displayName : shortName
        self.model = model
        self.state = state
        self.snapshot = snapshot
        self.latency = latency
        self.lastUpdated = lastUpdated
        self.lastError = lastError
    }
}

/// Shared thresholds for turning a percentage into a state.
public enum QuotaThresholds {
    public static let warning: Double = 50     // below -> warning colour
    public static let critical: Double = 20    // below -> critical colour

    public static func state(forPercent pct: Double?) -> QuotaState {
        guard let pct else { return .unknown }
        if pct <= 0 { return .exhausted }
        if pct < critical { return .critical }
        if pct < warning { return .warning }
        return .healthy
    }
}
