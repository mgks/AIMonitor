import Foundation

/// MiniMax provider.
///
/// Two fully separate platforms with distinct domains:
///   - International: api.minimax.io  (console: platform.minimax.io)
///   - China:         api.minimaxi.com (console: platform.minimaxi.com)  (note the extra "i")
///
/// Data source (Phase 1): tier 1, official Coding Plan Remains API.
///   GET /v1/api/openplatform/coding_plan/remains   (auth: Bearer)
///
/// Returns model_remains[], each with a 5-hour interval window and an
/// optional weekly window. We surface the "general" bucket as the headline
/// number, matching upstream behaviour.
final class MiniMaxProvider: AIProvider {

    let id = "minimax"
    let displayName = "MiniMax"
    let symbolName = "waveform"          // placeholder glyph until official art lands

    private let http: HTTPClient
    private let secrets: KeychainStore

    init(http: HTTPClient, secrets: KeychainStore) {
        self.http = http
        self.secrets = secrets
    }

    var isConfigured: Bool {
        secrets.get("minimax.apiKey") != nil
    }

    // Region is non-secret so it lives in UserDefaults via AppStorage.
    private var region: String {
        UserDefaults.standard.string(forKey: "minimax.region") ?? "international"
    }

    /// Coding Plan Remains endpoint. Both regions share the same path.
    private var remainsURL: URL {
        let host = region == "china" ? "api.minimaxi.com" : "api.minimax.io"
        return URL(string: "https://\(host)/v1/api/openplatform/coding_plan/remains")!
    }

    func fetchStatus() async throws -> ProviderStatus {
        guard let key = secrets.get("minimax.apiKey") else {
            throw ProviderError.notConfigured
        }

        let headers = [
            "Authorization": "Bearer \(key)",
            "Accept": "application/json"
        ]
        let response = try await http.request(remainsURL, method: "GET", headers: headers)
        return try parseRemains(response: response)
    }

    // MARK: - Response parsing

    /// Coding Plan Remains wire types. Fields are optional because the API
    /// may omit the weekly bucket when the plan has no weekly limit.
    private struct RemainsEnvelope: Decodable {
        let baseResp: BaseResp?
        let modelRemains: [ModelRemain]?

        enum CodingKeys: String, CodingKey {
            case baseResp = "base_resp"
            case modelRemains = "model_remains"
        }
    }

    private struct BaseResp: Decodable {
        let statusCode: Int?
        let statusMsg: String?

        enum CodingKeys: String, CodingKey {
            case statusCode = "status_code"
            case statusMsg = "status_msg"
        }
    }

    private struct ModelRemain: Decodable {
        let modelName: String?
        let currentIntervalRemainingPercent: Double?
        let currentWeeklyRemainingPercent: Double?
        // 1 = weekly limit is active; other values mean this plan has none.
        let currentWeeklyStatus: Int?
        let endTime: Double?            // ms since epoch
        let weeklyEndTime: Double?

        enum CodingKeys: String, CodingKey {
            case modelName = "model_name"
            case currentIntervalRemainingPercent = "current_interval_remaining_percent"
            case currentWeeklyRemainingPercent = "current_weekly_remaining_percent"
            case currentWeeklyStatus = "current_weekly_status"
            case endTime = "end_time"
            case weeklyEndTime = "weekly_end_time"
        }
    }

    private func parseRemains(response: HTTPResponse) throws -> ProviderStatus {
        if response.statusCode == 401 || response.statusCode == 403 {
            throw ProviderError.unauthorized
        }
        guard response.statusCode == 200 else {
            throw ProviderError.fromStatus(response.statusCode)
        }

        let envelope: RemainsEnvelope
        do {
            envelope = try JSONDecoder().decode(RemainsEnvelope.self, from: response.data)
        } catch {
            throw ProviderError.decode(error.localizedDescription)
        }

        // API-level business error (status_code != 0), e.g. no coding plan.
        if let code = envelope.baseResp?.statusCode, code != 0 {
            let msg = envelope.baseResp?.statusMsg ?? "MiniMax API error \(code)"
            if code == 1004 {
                throw ProviderError.missingCredential("coding plan access")
            }
            throw ProviderError.transport(msg)
        }

        guard let remains = envelope.modelRemains, !remains.isEmpty else {
            throw ProviderError.decode("empty model_remains")
        }

        // Prefer the "general" bucket; fall back to the first if absent.
        let bucket = remains.first { $0.modelName == "general" } ?? remains[0]

        let intervalPct = bucket.currentIntervalRemainingPercent
        let weeklyActive = bucket.currentWeeklyStatus == 1
        let weeklyPct = weeklyActive ? bucket.currentWeeklyRemainingPercent : nil

        // Headline percent: show the tighter of the two windows.
        let headline = [intervalPct, weeklyPct].compactMap { $0 }.min() ?? intervalPct

        let snapshot = QuotaSnapshot(
            remainingPercent: headline,
            resetsAt: dateFromMs(bucket.endTime),
            weeklyResetsAt: weeklyActive ? dateFromMs(bucket.weeklyEndTime) : nil,
            windowLabel: windowLabel(hasWeekly: weeklyActive),
            rawHeaders: response.headers
        )

        return ProviderStatus(
            providerID: id,
            displayName: displayName,
            shortName: "MiniMax",
            model: bucket.modelName ?? "general",
            state: QuotaThresholds.state(forPercent: headline),
            snapshot: snapshot,
            latency: response.elapsed,
            lastUpdated: Date()
        )
    }

    private func windowLabel(hasWeekly: Bool) -> String {
        hasWeekly ? "5h + Weekly" : "5-hour"
    }

    private func dateFromMs(_ ms: Double?) -> Date? {
        guard let ms else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }
}
