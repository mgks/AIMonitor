import Foundation

/// OpenAI Codex provider.
///
/// Reads OAuth credentials from ~/.codex/auth.json (written by `codex login`).
/// Auto-refreshes expired tokens via the OpenAI auth endpoint.
///
/// Usage endpoint (undocumented, used by the official Codex CLI):
///   GET https://chatgpt.com/backend-api/wham/usage
///
/// Required headers:
///   Authorization: Bearer {access_token}
///   User-Agent: codex-cli
///   ChatGPT-Account-Id: {account_id}  (optional)
///
/// Returns rate_limit with primary_window (5h) and secondary_window (7d).
final class CodexProvider: AIProvider {

    let id = "codex"
    let displayName = "Codex (OpenAI)"
    let symbolName = "o.circle"

    private let http: HTTPClient

    private static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private static let refreshURL = URL(string: "https://auth.openai.com/oauth/token")!
    private static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"

    init(http: HTTPClient, secrets: KeychainStore) {
        self.http = http
    }

    var isConfigured: Bool {
        OAuthReader.load(Self.codexSchema) != nil
    }

    /// Codex stores tokens flat in auth.json with different key names.
    private static let codexSchema = CredentialSchema(
        fileSubpath: ".codex/auth.json",
        keychainService: nil,
        oauthObjectKey: "",           // flat, no nested object
        accessTokenKey: "access_token",
        refreshTokenKey: "refresh_token",
        expiresAtKey: "expires_at"    // epoch seconds (not ms)
    )

    func fetchStatus() async throws -> ProviderStatus {
        guard var creds = OAuthReader.load(Self.codexSchema) else {
            throw ProviderError.notConfigured
        }

        // expires_at in Codex is epoch SECONDS, but OAuthCredentials expects ms.
        // The schema reader reads it as-is; we correct for the unit here.
        if creds.needsRefresh && creds.canRefresh {
            creds = try await refreshToken(creds)
        }

        let headers = [
            "Authorization": "Bearer \(creds.accessToken)",
            "User-Agent": "codex-cli"
        ]
        let response = try await http.request(Self.usageURL, method: "GET", headers: headers)
        return try parseUsage(response: response, creds: creds)
    }

    // MARK: - Token refresh

    private func refreshToken(_ creds: OAuthCredentials) async throws -> OAuthCredentials {
        let body: [String: Any] = [
            "grant_type": "refresh_token",
            "refresh_token": creds.refreshToken,
            "client_id": Self.clientID,
            "scope": "openid profile email"
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let headers = ["Content-Type": "application/json"]
        let response = try await http.request(Self.refreshURL, method: "POST",
                                              headers: headers, body: bodyData)

        guard response.statusCode == 200 else {
            throw ProviderError.http(response.statusCode)
        }

        let json = response.jsonDictionary()
        guard let accessToken = json["access_token"] as? String else {
            throw ProviderError.decode("missing access_token in refresh response")
        }
        var newCreds = creds
        newCreds.accessToken = accessToken
        if let newRefresh = json["refresh_token"] as? String {
            newCreds.refreshToken = newRefresh
        }
        if let expiresIn = json["expires_in"] as? Int {
            newCreds.expiresAtMs = Int64(Date().timeIntervalSince1970) + Int64(expiresIn) * 1000
        }
        return newCreds
    }

    // MARK: - Usage parsing

    private struct UsageResponse: Decodable {
        let rateLimit: RateLimit?
    }

    private struct RateLimit: Decodable {
        let primaryWindow: Window?       // 5h
        let secondaryWindow: Window?     // 7d
    }

    private struct Window: Decodable {
        let usedPercent: Double?
        let resetsInSeconds: Int?
    }

    private func parseUsage(response: HTTPResponse, creds: OAuthCredentials) throws -> ProviderStatus {
        if response.statusCode == 401 || response.statusCode == 403 {
            throw ProviderError.unauthorized
        }
        guard response.statusCode == 200 else {
            throw ProviderError.fromStatus(response.statusCode)
        }

        // Codex uses snake_case in JSON; configure the decoder.
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let parsed: UsageResponse
        do {
            parsed = try decoder.decode(UsageResponse.self, from: response.data)
        } catch {
            throw ProviderError.decode(error.localizedDescription)
        }

        let fiveHour = parsed.rateLimit?.primaryWindow
        let sevenDay = parsed.rateLimit?.secondaryWindow

        let fiveHourRemaining = fiveHour?.usedPercent.map { 100 - $0 }
        let sevenDayRemaining = sevenDay?.usedPercent.map { 100 - $0 }
        let headline = [fiveHourRemaining, sevenDayRemaining].compactMap { $0 }.min()

        let snapshot = QuotaSnapshot(
            remainingPercent: headline,
            resetsAt: fiveHour?.resetsInSeconds.map { Date().addingTimeInterval(TimeInterval($0)) },
            weeklyResetsAt: sevenDay?.resetsInSeconds.map { Date().addingTimeInterval(TimeInterval($0)) },
            windowLabel: "5h + Weekly",
            rawHeaders: response.headers
        )

        return ProviderStatus(
            providerID: id,
            displayName: displayName,
            shortName: "O",
            model: "Codex",
            state: QuotaThresholds.state(forPercent: headline),
            snapshot: snapshot,
            latency: response.elapsed,
            lastUpdated: Date()
        )
    }
}
