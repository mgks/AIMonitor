import Foundation

/// OpenRouter provider.
///
/// Single platform: openrouter.ai. Documents a clean credits endpoint.
///   GET /api/v1/credits   (auth: Bearer)
///   GET /api/v1/key       (auth: Bearer, for rate-limit usage breakdown)
///
/// Returns total_credits, total_usage (balance = total_credits - total_usage),
/// plus daily/weekly/monthly spend. OpenRouter uses pay-as-you-go credits,
/// so there is no 5h/weekly quota window: we show the credit balance.
final class OpenRouterProvider: AIProvider {

    let id = "openrouter"
    let displayName = "OpenRouter"
    let symbolName = "arrow.triangle.swap"

    private let http: HTTPClient

    init(http: HTTPClient, secrets: KeychainStore) {
        self.http = http
    }

    private var creditsURL: URL {
        URL(string: "https://openrouter.ai/api/v1/credits")!
    }

    private var keyURL: URL {
        URL(string: "https://openrouter.ai/api/v1/key")!
    }

    func fetchStatus(apiKey: String) async throws -> ProviderStatus {
        let key = apiKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else {
            throw ProviderError.notConfigured
        }

        let headers = [
            "Authorization": "Bearer \(key)",
            "Accept": "application/json"
        ]

        // Fetch credits and key info in parallel.
        async let creditsResp = http.request(creditsURL, method: "GET", headers: headers)
        async let keyResp = http.request(keyURL, method: "GET", headers: headers)

        let creditsData = try await creditsResp
        let keyData = try await keyResp

        return try parse(credits: creditsData, key: keyData)
    }

    // MARK: - Response parsing

    private struct CreditsEnvelope: Decodable {
        let data: CreditsData?
    }

    private struct CreditsData: Decodable {
        let totalCredits: Double?
        let totalUsage: Double?
    }

    private struct KeyEnvelope: Decodable {
        let data: KeyData?
    }

    private struct KeyData: Decodable {
        let label: String?
        let limit: Double?
        let limitRemaining: Double?
        let usage: Double?
        let usageDaily: Double?
        let usageWeekly: Double?
        let usageMonthly: Double?
        let isFreeTier: Bool?
    }

    private func parse(credits: HTTPResponse, key: HTTPResponse) throws -> ProviderStatus {
        if credits.statusCode == 401 || credits.statusCode == 403 {
            throw ProviderError.unauthorized
        }
        guard credits.statusCode == 200 else {
            throw ProviderError.fromStatus(credits.statusCode)
        }

        let creditsEnv = try JSONDecoder().decode(CreditsEnvelope.self, from: credits.data)
        let keyEnv = (try? JSONDecoder().decode(KeyEnvelope.self, from: key.data)) ?? KeyEnvelope(data: nil)

        let totalCredits = creditsEnv.data?.totalCredits ?? 0
        let totalUsage = creditsEnv.data?.totalUsage ?? 0
        let balance = max(0, totalCredits - totalUsage)

        // Percent remaining relative to total credits.
        let pct: Double? = totalCredits > 0 ? (balance / totalCredits * 100) : nil

        var snapshot = QuotaSnapshot(
            remainingPercent: pct,
            creditsRemaining: balance,
            currency: "USD",
            windowLabel: keyEnv.data?.label.map { "\($0) key" },
            rawHeaders: credits.headers
        )
        snapshot.totalTokens = Int(totalUsage)

        return ProviderStatus(
            providerID: id,
            displayName: displayName,
            shortName: "OR",
            model: keyEnv.data?.label,
            state: QuotaThresholds.state(forPercent: pct),
            snapshot: snapshot,
            latency: (credits.elapsed + key.elapsed) / 2,
            lastUpdated: Date()
        )
    }
}
