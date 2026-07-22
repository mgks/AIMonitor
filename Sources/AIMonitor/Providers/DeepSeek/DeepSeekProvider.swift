import Foundation

/// DeepSeek provider.
///
/// Single platform: api.deepseek.com. Documents a clean balance endpoint.
///   GET /user/balance   (auth: Bearer)
///
/// Returns is_available + balance_infos[] with currency, total_balance,
/// granted_balance, topped_up_balance. DeepSeek is pay-as-you-go, so we
/// show the account balance rather than a quota window.
final class DeepSeekProvider: AIProvider {

    let id = "deepseek"
    let displayName = "DeepSeek"
    let symbolName = "magnifyingglass"

    private let http: HTTPClient
    private let secrets: KeychainStore

    init(http: HTTPClient, secrets: KeychainStore) {
        self.http = http
        self.secrets = secrets
    }

    var isConfigured: Bool {
        secrets.get("deepseek.apiKey") != nil
    }

    private var balanceURL: URL {
        URL(string: "https://api.deepseek.com/user/balance")!
    }

    func fetchStatus() async throws -> ProviderStatus {
        guard let key = secrets.get("deepseek.apiKey") else {
            throw ProviderError.notConfigured
        }

        let headers = [
            "Authorization": "Bearer \(key)",
            "Accept": "application/json"
        ]
        let response = try await http.request(balanceURL, method: "GET", headers: headers)
        return try parseBalance(response: response)
    }

    // MARK: - Response parsing

    private struct Envelope: Decodable {
        let isAvailable: Bool?
        let balanceInfos: [BalanceInfo]?
    }

    private struct BalanceInfo: Decodable {
        let currency: String?
        let totalBalance: String?
        let grantedBalance: String?
        let toppedUpBalance: String?
    }

    private func parseBalance(response: HTTPResponse) throws -> ProviderStatus {
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

        // Sum all currency balances. Prefer USD, fall back to CNY.
        let infos = envelope.balanceInfos ?? []
        let usd = infos.first { $0.currency == "USD" }
        let fallback = infos.first
        let chosen = usd ?? fallback
        let balance = Double(chosen?.totalBalance ?? "0") ?? 0
        let currency = chosen?.currency ?? "USD"
        let isAvailable = envelope.isAvailable ?? true

        var snapshot = QuotaSnapshot(
            creditsRemaining: balance,
            currency: currency,
            windowLabel: currency,
            rawHeaders: response.headers
        )

        // No quota percentage; healthy = balance > 0 and account available.
        let state: QuotaState = {
            if !isAvailable { return .error }
            if balance <= 0 { return .exhausted }
            return .healthy
        }()

        return ProviderStatus(
            providerID: id,
            displayName: displayName,
            shortName: "DS",
            model: currency,
            state: state,
            snapshot: snapshot,
            latency: response.elapsed,
            lastUpdated: Date()
        )
    }
}
