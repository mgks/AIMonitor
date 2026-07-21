import Foundation

/// Z.ai (GLM) provider.
///
/// Two platforms:
///   - International: api.z.ai           (console: z.ai)
///   - China:         open.bigmodel.cn   (console: open.bigmodel.cn)
///
/// Data source (Phase 1): tier 1, official Quota Limit monitor API.
///   GET /api/monitor/usage/quota/limit
///
/// Important auth quirk: the API key is sent as a raw value with NO "Bearer"
/// prefix. Sending "Bearer <key>" returns 401. Both regions share the path.
final class ZaiProvider: AIProvider {

    let id = "zai"
    let displayName = "Z.ai (GLM)"
    let symbolName = "bolt"             // placeholder glyph

    private let http: HTTPClient
    private let secrets: KeychainStore

    init(http: HTTPClient, secrets: KeychainStore) {
        self.http = http
        self.secrets = secrets
    }

    var isConfigured: Bool {
        secrets.get("zai.apiKey") != nil
    }

    private var region: String {
        UserDefaults.standard.string(forKey: "zai.region") ?? "international"
    }

    private var quotaURL: URL {
        let host = region == "china" ? "open.bigmodel.cn" : "api.z.ai"
        return URL(string: "https://\(host)/api/monitor/usage/quota/limit")!
    }

    func fetchStatus() async throws -> ProviderStatus {
        guard let key = secrets.get("zai.apiKey") else {
            throw ProviderError.notConfigured
        }

        let headers = [
            "Authorization": key,                 // raw key, NO Bearer prefix
            "Accept": "application/json"
        ]
        let response = try await http.request(quotaURL, method: "GET", headers: headers)
        return try parseQuota(response: response)
    }

    // MARK: - Response parsing

    private struct Envelope: Decodable {
        let code: Int?
        let msg: String?
        let success: Bool?
        let data: DataBlock?
    }

    private struct DataBlock: Decodable {
        let limits: [LimitInfo]?
        let level: String?
    }

    private struct LimitInfo: Decodable {
        let type: String?
        let percentage: Int?        // TOKENS_LIMIT: used percentage (0..100)
        let usage: Int?             // TIME_LIMIT: total requests in window
        let remaining: Int?         // TIME_LIMIT: remaining requests
        let currentValue: Int?
        let nextResetTime: Double?  // ms since epoch
    }

    private func parseQuota(response: HTTPResponse) throws -> ProviderStatus {
        if response.statusCode == 401 || response.statusCode == 403 {
            throw ProviderError.unauthorized
        }
        guard response.statusCode == 200 else {
            throw ProviderError.fromStatus(response.statusCode)
        }

        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: response.data)
        } catch {
            throw ProviderError.decode(error.localizedDescription)
        }

        // In-band failure: a 200 can still carry success=false.
        if let success = envelope.success, success == false {
            let msg = envelope.msg ?? "Z.ai quota API error"
            throw ProviderError.transport(msg)
        }

        let limits = envelope.data?.limits ?? []
        let timeLimit = limits.first { $0.type == "TIME_LIMIT" }
        let tokensLimit = limits.first { $0.type == "TOKENS_LIMIT" }

        // TOKENS_LIMIT.percentage is "used" percent; remaining = 100 - used.
        let tokensRemaining: Double? = tokensLimit?.percentage.map { 100 - Double($0) }
        let timeRemainingPct: Double? = {
            guard let rem = timeLimit?.remaining, let total = timeLimit?.usage, total > 0
            else { return nil }
            return Double(rem) / Double(rem + total) * 100
        }()

        // Headline: prefer tokens (the binding limit), fall back to time.
        let headline = tokensRemaining ?? timeRemainingPct

        // Two reset windows, matching the MiniMax card layout.
        let intervalReset = dateFromMs(timeLimit?.nextResetTime)
        let weeklyReset = dateFromMs(tokensLimit?.nextResetTime)

        var snapshot = QuotaSnapshot(
            remainingPercent: headline,
            resetsAt: intervalReset,
            weeklyResetsAt: weeklyReset,
            windowLabel: "5h + Weekly",
            rawHeaders: response.headers
        )
        if let rem = timeLimit?.remaining {
            snapshot.remainingRequests = rem
        }

        return ProviderStatus(
            providerID: id,
            displayName: displayName,
            shortName: "Z.ai",
            model: envelope.data?.level,
            state: QuotaThresholds.state(forPercent: headline),
            snapshot: snapshot,
            latency: response.elapsed,
            lastUpdated: Date()
        )
    }

    private func dateFromMs(_ ms: Double?) -> Date? {
        guard let ms else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }
}
