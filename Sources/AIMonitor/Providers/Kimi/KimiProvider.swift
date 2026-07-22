import Foundation

/// Kimi (Moonshot) coding plan provider.
///
/// Endpoint (undocumented, community-confirmed):
///   GET https://api.kimi.com/coding/v1/usages
/// Auth: Bearer {api_key}
///
/// Returns a weekly subscription quota plus a 5h rolling rate-limit window.
final class KimiProvider: AIProvider {

    let id = "kimi"
    let displayName = "Kimi"
    let symbolName = "k.circle"

    private let http: HTTPClient
    private let secrets: KeychainStore

    init(http: HTTPClient, secrets: KeychainStore) {
        self.http = http
        self.secrets = secrets
    }

    var isConfigured: Bool {
        secrets.get("kimi.apiKey") != nil
    }

    private var usagesURL: URL {
        URL(string: "https://api.kimi.com/coding/v1/usages")!
    }

    func fetchStatus() async throws -> ProviderStatus {
        guard let key = secrets.get("kimi.apiKey") else {
            throw ProviderError.notConfigured
        }

        let headers = [
            "Authorization": "Bearer \(key)",
            "Accept": "application/json"
        ]
        let response = try await http.request(usagesURL, method: "GET", headers: headers)
        return try parseUsage(response: response)
    }

    // MARK: - Response parsing

    private struct UsagesResponse: Decodable {
        let limits: [LimitItem]?
        let usage: UsageBlock?
    }

    private struct LimitItem: Decodable {
        let detail: LimitDetail?
    }

    private struct LimitDetail: Decodable {
        let limit: Double?
        let remaining: Double?
        let resetTime: String?         // ISO 8601
    }

    private struct UsageBlock: Decodable {
        let limit: Double?
        let remaining: Double?
        let resetTime: String?         // ISO 8601
    }

    private func parseUsage(response: HTTPResponse) throws -> ProviderStatus {
        if response.statusCode == 401 || response.statusCode == 403 {
            throw ProviderError.unauthorized
        }
        guard response.statusCode == 200 else {
            throw ProviderError.fromStatus(response.statusCode)
        }

        let parsed: UsagesResponse
        do {
            parsed = try JSONDecoder().decode(UsagesResponse.self, from: response.data)
        } catch {
            throw ProviderError.decode(error.localizedDescription)
        }

        // limits[].detail = 5h window; usage = weekly window.
        let fiveHourDetail = parsed.limits?.first?.detail
        let weekly = parsed.usage

        let fiveHourPct: Double? = {
            guard let limit = fiveHourDetail?.limit, limit > 0,
                  let remaining = fiveHourDetail?.remaining else { return nil }
            return remaining / limit * 100
        }()
        let weeklyPct: Double? = {
            guard let limit = weekly?.limit, limit > 0,
                  let remaining = weekly?.remaining else { return nil }
            return remaining / limit * 100
        }()
        let headline = [fiveHourPct, weeklyPct].compactMap { $0 }.min()

        let snapshot = QuotaSnapshot(
            remainingPercent: headline,
            resetsAt: parseISO(fiveHourDetail?.resetTime),
            weeklyResetsAt: parseISO(weekly?.resetTime),
            windowLabel: "5h + Weekly",
            rawHeaders: response.headers
        )

        return ProviderStatus(
            providerID: id,
            displayName: displayName,
            shortName: "K",
            model: "Kimi",
            state: QuotaThresholds.state(forPercent: headline),
            snapshot: snapshot,
            latency: response.elapsed,
            lastUpdated: Date()
        )
    }

    private func parseISO(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        return f.date(from: s)
    }
}
