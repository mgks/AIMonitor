import Foundation

/// Claude Code (Anthropic) provider.
///
/// Reads OAuth credentials from ~/.claude/.credentials.json or the macOS
/// login Keychain item "Claude Code-credentials". Auto-refreshes expired
/// tokens via the Anthropic token endpoint.
///
/// Usage endpoint (undocumented, used by Claude Code CLI):
///   GET https://api.anthropic.com/api/oauth/usage
///
/// Required headers (the User-Agent is load-bearing; without it the endpoint
/// 429s immediately):
///   Authorization: Bearer {access_token}
///   anthropic-beta: oauth-2025-04-20
///   User-Agent: claude-code/2.1.183
///   Content-Type: application/json
///
/// Returns limits[] with five_hour and seven_day rolling windows.
final class ClaudeProvider: AIProvider {

    let id = "claude"
    let displayName = "Claude Code"
    let symbolName = "c.circle"

    private let http: HTTPClient

    private static let schema = CredentialSchema(
        fileSubpath: ".claude/.credentials.json",
        keychainService: "Claude Code-credentials",
        oauthObjectKey: "claudeAiOauth",
        accessTokenKey: "accessToken",
        refreshTokenKey: "refreshToken",
        expiresAtKey: "expiresAt"
    )

    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let refreshURL = URL(string: "https://platform.claude.com/api/oauth_token")!
    private static let clientID = "9d1c250a-e61b-44a4-915c-c4050d2f7d5d"

    init(http: HTTPClient, secrets: KeychainStore) {
        self.http = http
    }

    var isConfigured: Bool {
        OAuthReader.load(Self.schema) != nil
    }

    func fetchStatus() async throws -> ProviderStatus {
        guard var creds = OAuthReader.load(Self.schema) else {
            throw ProviderError.notConfigured
        }

        // Refresh if the access token is expired or about to expire.
        if creds.needsRefresh && creds.canRefresh {
            creds = try await refreshToken(creds)
        }

        // Fetch usage with the load-bearing headers.
        let headers = [
            "Authorization": "Bearer \(creds.accessToken)",
            "anthropic-beta": "oauth-2025-04-20",
            "User-Agent": "claude-code/2.1.183",
            "Content-Type": "application/json"
        ]
        let response = try await http.request(Self.usageURL, method: "GET", headers: headers)
        return try parseUsage(response: response, creds: creds)
    }

    // MARK: - Token refresh

    private func refreshToken(_ creds: OAuthCredentials) async throws -> OAuthCredentials {
        let body: [String: Any] = [
            "grant_type": "refresh_token",
            "refresh_token": creds.refreshToken,
            "client_id": Self.clientID
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
            newCreds.expiresAtMs = Int64(Date().timeIntervalSince1970 * 1000) + Int64(expiresIn) * 1000
        }
        return newCreds
    }

    // MARK: - Usage parsing

    private struct UsageResponse: Decodable {
        let limits: [LimitEntry]?
    }

    private struct LimitEntry: Decodable {
        let window: String?       // "five_hour", "seven_day"
        let utilizationPercent: Double?
        let resetsAt: Int64?      // epoch ms
    }

    private func parseUsage(response: HTTPResponse, creds: OAuthCredentials) throws -> ProviderStatus {
        if response.statusCode == 401 || response.statusCode == 403 {
            throw ProviderError.unauthorized
        }
        guard response.statusCode == 200 else {
            throw ProviderError.fromStatus(response.statusCode)
        }

        let parsed: UsageResponse
        do {
            parsed = try JSONDecoder().decode(UsageResponse.self, from: response.data)
        } catch {
            throw ProviderError.decode(error.localizedDescription)
        }

        let limits = parsed.limits ?? []
        let fiveHour = limits.first { $0.window == "five_hour" }
        let sevenDay = limits.first { $0.window == "seven_day" }

        // utilizationPercent = used; remaining = 100 - used.
        let fiveHourRemaining = fiveHour?.utilizationPercent.map { 100 - $0 }
        let sevenDayRemaining = sevenDay?.utilizationPercent.map { 100 - $0 }
        let headline = [fiveHourRemaining, sevenDayRemaining].compactMap { $0 }.min()

        let snapshot = QuotaSnapshot(
            remainingPercent: headline,
            weeklyRemainingPercent: sevenDayRemaining,
            resetsAt: fiveHour?.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) },
            weeklyResetsAt: sevenDay?.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) },
            windowLabel: planLabel(from: creds),
            rawHeaders: response.headers
        )

        return ProviderStatus(
            providerID: id,
            displayName: displayName,
            shortName: "C",
            model: planLabel(from: creds),
            state: QuotaThresholds.state(forPercent: headline),
            snapshot: snapshot,
            latency: response.elapsed,
            lastUpdated: Date()
        )
    }

    /// Plan label like claudebar: "Max 5x", "Pro", etc.
    private func planLabel(from creds: OAuthCredentials) -> String {
        var name = (creds.raw["subscriptionType"] ?? "").capitalized
        if name.isEmpty { name = "Claude" }
        let tier = creds.raw["rateLimitTier"] ?? ""
        if tier.contains("5x") { name += " 5x" }
        else if tier.contains("20x") { name += " 20x" }
        return name
    }
}
