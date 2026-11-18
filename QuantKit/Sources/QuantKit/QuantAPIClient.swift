import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct HTTPResponse: Sendable {
    public let status: Int
    public let body: Data
    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

/// Injectable so the whole client is testable without a network.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        let (data, response): (Data, URLResponse) = try await withCheckedThrowingContinuation { continuation in
            session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let response {
                    continuation.resume(returning: (data ?? Data(), response))
                } else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                }
            }.resume()
        }
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return HTTPResponse(status: http.statusCode, body: data)
    }
}

/// Where the per-device token lives (the app uses the Keychain).
public protocol TokenStore: Sendable {
    func token() -> String?
}

public struct StaticTokenStore: TokenStore {
    private let value: String?
    public init(_ value: String?) { self.value = value }
    public func token() -> String? { value }
}

public enum QuantAPIError: Error, Equatable, Sendable {
    case missingToken
    case insecureServer
    case unauthorized
    case forbidden
    case controlDisabled
    case conflict(String)
    case server(status: Int, detail: String)
    case network(String)
    case decoding(String)
}

public enum PushEnvironment: String, Sendable { case sandbox, production }

public struct QuantAPIClient: Sendable {
    public let baseURL: URL
    private let tokens: TokenStore
    private let transport: HTTPTransport
    private let timeout: TimeInterval

    /// HTTPS is required except for loopback and private VPN addresses used in development.
    public init(baseURL: URL, tokens: TokenStore, transport: HTTPTransport = URLSessionTransport(),
                timeout: TimeInterval = 10) throws {
        guard Self.isAllowed(baseURL) else { throw QuantAPIError.insecureServer }
        self.baseURL = baseURL
        self.tokens = tokens
        self.transport = transport
        self.timeout = timeout
    }

    static func isAllowed(_ url: URL) -> Bool {
        if url.scheme == "https" { return true }
        guard url.scheme == "http", let host = url.host else { return false }
        return host == "localhost" || host == "127.0.0.1" || host.hasPrefix("100.")  // Tailscale CGNAT
    }

    public func overview() async throws -> Overview {
        try await call("GET", "/api/v1/mobile/overview")
    }

    /// The kill switch. Works even when the exchange is down: the server only records the stop.
    public func emergencyStop(reason: String) async throws -> BotActionResponse {
        try await call("POST", "/api/v1/bot/panic", body: ["reason": reason])
    }

    public func registerPushToken(_ deviceToken: Data, environment: PushEnvironment) async throws {
        let _: EmptyResponse = try await call(
            "PUT", "/api/v1/devices/me/push-token",
            body: ["apns_token": Self.hex(deviceToken), "environment": environment.rawValue])
    }

    public static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    func request(_ method: String, _ path: String, body: [String: String]? = nil) throws -> URLRequest {
        guard let token = tokens.token(), !token.isEmpty else { throw QuantAPIError.missingToken }
        var request = URLRequest(url: baseURL.appendingPathComponent(path), timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        }
        return request
    }

    private func call<T: Decodable>(_ method: String, _ path: String,
                                    body: [String: String]? = nil) async throws -> T {
        let request = try request(method, path, body: body)
        let response: HTTPResponse
        do {
            response = try await transport.send(request)
        } catch {
            throw QuantAPIError.network(String(describing: error))
        }
        switch response.status {
        case 200..<300:
            do {
                return try QuantDates.decoder().decode(T.self, from: response.body)
            } catch {
                throw QuantAPIError.decoding(String(describing: error))
            }
        case 401: throw QuantAPIError.unauthorized
        case 403: throw QuantAPIError.forbidden
        case 409: throw QuantAPIError.conflict(Self.detail(response.body))
        case 503 where Self.detail(response.body).contains("TERMINAL_ADMIN_TOKEN"):
            throw QuantAPIError.controlDisabled
        default:
            throw QuantAPIError.server(status: response.status, detail: Self.detail(response.body))
        }
    }

    static func detail(_ body: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let detail = object["detail"] as? String {
            return detail
        }
        return String(decoding: body.prefix(200), as: UTF8.self)
    }
}

struct EmptyResponse: Decodable {}
