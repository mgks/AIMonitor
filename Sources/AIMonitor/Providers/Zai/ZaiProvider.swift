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

    init(http: HTTPClient, secrets: CredentialStore) {
        self.http = http
    }

    private var region: String {
        UserDefaults.standard.string(forKey: "zai.region") ?? "international"
    }

    private var quotaURL: URL {
        let host = region == "china" ? "open.bigmodel.cn" : "api.z.ai"
        return URL(string: "https://\(host)/api/monitor/usage/quota/limit")!
    }

    func fetchStatus(apiKey: String) async throws -> ProviderStatus {
        let key = apiKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else {
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
        let unit: Int?              // 3 = 5-hour, 6 = weekly, 5 = MCP tools monthly
        let number: Int?
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

        // The API returns TWO TOKENS_LIMIT entries distinguished by `unit`:
        //   unit 3 = 5-hour rolling window
        //   unit 6 = weekly window
        // There may also be a TIME_LIMIT (unit 5) for MCP tools, which we skip.
        let fiveHourLimit = limits.first { $0.type == "TOKENS_LIMIT" && $0.unit == 3 }
        let weeklyLimit = limits.first { $0.type == "TOKENS_LIMIT" && $0.unit == 6 }

        // percentage = "used" percent; remaining = 100 - used.
        let fiveHourRemaining = fiveHourLimit?.percentage.map { 100 - Double($0) }
        let weeklyRemaining = weeklyLimit?.percentage.map { 100 - Double($0) }

        // Headline: show the tighter (lower) of the two windows.
        let headline = [fiveHourRemaining, weeklyRemaining].compactMap { $0 }.min()

        var snapshot = QuotaSnapshot(
            remainingPercent: headline,
            weeklyRemainingPercent: weeklyRemaining,
            resetsAt: dateFromMs(fiveHourLimit?.nextResetTime),
            weeklyResetsAt: dateFromMs(weeklyLimit?.nextResetTime),
            windowLabel: "5h + Weekly",
            rawHeaders: response.headers
        )

        return ProviderStatus(
            providerID: id,
            displayName: displayName,
            shortName: "Z",
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
