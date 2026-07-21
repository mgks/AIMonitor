import Foundation

/// The result of a single HTTP probe, including response headers for rate-limit parsing.
public struct HTTPResponse: Sendable {
    public let data: Data
    public let headers: [String: String]     // lowercased keys
    public let statusCode: Int
    public let elapsed: TimeInterval         // seconds

    /// Best-effort JSON decode into a dictionary. Never throws.
    public func jsonDictionary() -> [String: Any] {
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: []),
              let dict = obj as? [String: Any] else { return [:] }
        return dict
    }
}

/// Tiny dependency-free HTTP client built on URLSession.
/// An actor so all request state is isolated and Sendable-safe.
public actor HTTPClient {
    private let session: URLSession

    public init(timeout: TimeInterval = 15) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout + 5
        config.waitsForConnectivity = false
        config.httpAdditionalHeaders = ["User-Agent": "AIStat/0.1"]
        self.session = URLSession(configuration: config)
    }

    /// Perform a request and return the body, lowercased headers, status and timing.
    public func request(
        _ url: URL,
        method: String = "GET",
        headers: [String: String] = [:],
        body: Data? = nil
    ) async throws -> HTTPResponse {
        var req = URLRequest(url: url)
        req.httpMethod = method
        for (key, value) in headers { req.setValue(value, forHTTPHeaderField: key) }
        req.httpBody = body

        let start = Date()
        do {
            let (data, urlResp) = try await session.data(for: req)
            let elapsed = Date().timeIntervalSince(start)
            guard let http = urlResp as? HTTPURLResponse else {
                throw ProviderError.transport("Non-HTTP response")
            }
            // Lowercase every header key so callers can match case-insensitively.
            let lowered: [String: String] = Dictionary(
                http.allHeaderFields.map { (String(describing: $0.key).lowercased(), "\($0.value)") },
                uniquingKeysWith: { _, last in last }
            )
            return HTTPResponse(data: data, headers: lowered, statusCode: http.statusCode, elapsed: elapsed)
        } catch let err as ProviderError {
            throw err
        } catch {
            throw ProviderError.transport(error.localizedDescription)
        }
    }
}
