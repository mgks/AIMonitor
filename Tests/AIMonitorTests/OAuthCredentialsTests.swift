import XCTest
@testable import AIMonitor

/// Tests for OAuth credential parsing from the Claude and Codex CLI files.
final class OAuthCredentialsTests: XCTestCase {

    // MARK: - Claude Code (.claude/.credentials.json)

    func testClaudeNestedParsing() {
        let json: [String: Any] = [
            "claudeAiOauth": [
                "accessToken": "test-access",
                "refreshToken": "test-refresh",
                "expiresAt": 9999999999999,
                "subscriptionType": "max",
                "rateLimitTier": "default_claude_max_5x"
            ]
        ]
        let schema = CredentialSchema(
            fileSubpath: ".claude/.credentials.json",
            keychainService: "Claude Code-credentials",
            oauthObjectKey: "claudeAiOauth",
            accessTokenKey: "accessToken",
            refreshTokenKey: "refreshToken",
            expiresAtKey: "expiresAt"
        )
        let creds = OAuthReader.parse(json, schema: schema)
        XCTAssertNotNil(creds)
        XCTAssertEqual(creds?.accessToken, "test-access")
        XCTAssertEqual(creds?.refreshToken, "test-refresh")
        XCTAssertEqual(creds?.raw["subscriptionType"], "max")
        XCTAssertFalse(creds?.needsRefresh ?? true)   // far-future expiry
    }

    func testClaudeMissingTokenReturnsNil() {
        let json: [String: Any] = [
            "claudeAiOauth": [
                "accessToken": "",
                "refreshToken": "test-refresh",
                "expiresAt": 0
            ]
        ]
        let schema = CredentialSchema(
            fileSubpath: ".claude/.credentials.json",
            oauthObjectKey: "claudeAiOauth",
            accessTokenKey: "accessToken",
            refreshTokenKey: "refreshToken",
            expiresAtKey: "expiresAt"
        )
        XCTAssertNil(OAuthReader.parse(json, schema: schema))
    }

    func testClaudeExpiredTokenNeedsRefresh() {
        let json: [String: Any] = [
            "claudeAiOauth": [
                "accessToken": "test",
                "refreshToken": "test",
                "expiresAt": 1   // 1970, long expired
            ]
        ]
        let schema = CredentialSchema(
            fileSubpath: ".claude/.credentials.json",
            oauthObjectKey: "claudeAiOauth",
            accessTokenKey: "accessToken",
            refreshTokenKey: "refreshToken",
            expiresAtKey: "expiresAt"
        )
        let creds = OAuthReader.parse(json, schema: schema)
        XCTAssertTrue(creds?.needsRefresh ?? false)
        XCTAssertTrue(creds?.canRefresh ?? false)
    }

    // MARK: - Codex (.codex/auth.json)

    func testCodexFlatParsing() {
        let json: [String: Any] = [
            "access_token": "codex-access",
            "refresh_token": "codex-refresh",
            "expires_at": 9999999999,
            "id_token": "some-jwt"
        ]
        let schema = CredentialSchema(
            fileSubpath: ".codex/auth.json",
            oauthObjectKey: "",   // flat, no nesting
            accessTokenKey: "access_token",
            refreshTokenKey: "refresh_token",
            expiresAtKey: "expires_at"
        )
        let creds = OAuthReader.parse(json, schema: schema)
        XCTAssertNotNil(creds)
        XCTAssertEqual(creds?.accessToken, "codex-access")
        XCTAssertEqual(creds?.refreshToken, "codex-refresh")
    }
}
