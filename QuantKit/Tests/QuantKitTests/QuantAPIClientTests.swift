import Foundation
import XCTest
@testable import QuantKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Records requests and replays canned responses.
final class MockTransport: HTTPTransport, @unchecked Sendable {
    var responses: [Result<HTTPResponse, Error>]
    private(set) var requests: [URLRequest] = []
    private let lock = NSLock()

    init(_ responses: [Result<HTTPResponse, Error>]) { self.responses = responses }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        lock.lock()
        defer { lock.unlock() }
        requests.append(request)
        return try responses.removeFirst().get()
    }
}

func fixture(_ name: String) throws -> Data {
    let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json",
                                              subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

func client(_ transport: MockTransport, token: String? = "qtd_test-token") throws -> QuantAPIClient {
    try QuantAPIClient(baseURL: URL(string: "https://quant.example.com")!,
                       tokens: StaticTokenStore(token), transport: transport)
}

final class QuantAPIClientTests: XCTestCase {
    func testOverviewRequestAndDecoding() async throws {
        let transport = MockTransport([.success(HTTPResponse(status: 200, body: try fixture("overview")))])
        let overview = try await client(transport).overview()

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://quant.example.com/api/v1/mobile/overview")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer qtd_test-token")

        XCTAssertEqual(overview.bot.status, .running)
        XCTAssertTrue(overview.trader.alive)
        XCTAssertEqual(overview.trader.venue, "binance-testnet")
        XCTAssertEqual(overview.strategy?.name, "rsi_mean_reversion")
        XCTAssertEqual(overview.strategy?.gatePassed, false)
        XCTAssertEqual(overview.pnl.pnl, Decimal(string: "7")!)
        XCTAssertEqual(overview.pnl.position, Decimal(string: "0.001")!)
        XCTAssertEqual(overview.pnl.lastPrice, Decimal(string: "65000.10")!)
        XCTAssertEqual(overview.pnl.equityCurve.count, 3)
        XCTAssertEqual(overview.alerts.map(\.kind), ["kill_retry", "fill"])
        XCTAssertEqual(overview.alerts.first?.severity, .critical)
    }

    func testEmergencyStopSendsTheReason() async throws {
        let transport = MockTransport([.success(HTTPResponse(status: 200, body: try fixture("panic")))])
        let response = try await client(transport).emergencyStop(reason: "from iPhone")

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/v1/bot/panic")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(request.httpBody)
        XCTAssertEqual(String(decoding: body, as: UTF8.self), #"{"reason":"from iPhone"}"#)
        XCTAssertEqual(response.status, .panic)
    }

    func testPushTokenIsSentAsLowercaseHex() async throws {
        let transport = MockTransport([.success(HTTPResponse(
            status: 200, body: Data(#"{"device_id":"abc","push_enabled":true}"#.utf8)))])
        try await client(transport).registerPushToken(Data([0x0A, 0xFF, 0x00, 0x7B]), environment: .sandbox)

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path, "/api/v1/devices/me/push-token")
        let body = try XCTUnwrap(request.httpBody)
        XCTAssertEqual(String(decoding: body, as: UTF8.self),
                       #"{"apns_token":"0aff007b","environment":"sandbox"}"#)
    }

    func testHTTPErrorsMapToTypedErrors() async throws {
        let cases: [(Int, String, QuantAPIError)] = [
            (401, #"{"detail":"invalid token"}"#, .unauthorized),
            (403, #"{"detail":"operator token required"}"#, .forbidden),
            (409, #"{"detail":"bot is already in panic state"}"#, .conflict("bot is already in panic state")),
            (503, #"{"detail":"control API disabled: set TERMINAL_ADMIN_TOKEN to enable it"}"#, .controlDisabled),
            (500, "boom", .server(status: 500, detail: "boom")),
        ]
        for (status, body, expected) in cases {
            let transport = MockTransport([.success(HTTPResponse(status: status, body: Data(body.utf8)))])
            do {
                _ = try await client(transport).emergencyStop(reason: "x")
                XCTFail("expected \(expected)")
            } catch let error as QuantAPIError {
                XCTAssertEqual(error, expected)
            }
        }
    }

    func testNetworkFailureAndBadJSON() async throws {
        let offline = MockTransport([.failure(URLError(.notConnectedToInternet))])
        do {
            _ = try await client(offline).overview()
            XCTFail("expected a network error")
        } catch let error as QuantAPIError {
            guard case .network = error else { return XCTFail("got \(error)") }
        }
        let garbage = MockTransport([.success(HTTPResponse(status: 200, body: Data("{}".utf8)))])
        do {
            _ = try await client(garbage).overview()
            XCTFail("expected a decoding error")
        } catch let error as QuantAPIError {
            guard case .decoding = error else { return XCTFail("got \(error)") }
        }
    }

    func testNoTokenNoRequest() async throws {
        let transport = MockTransport([])
        do {
            _ = try await client(transport, token: nil).overview()
            XCTFail("expected missingToken")
        } catch let error as QuantAPIError {
            XCTAssertEqual(error, .missingToken)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testOnlyHTTPSOrPrivateDevelopmentHosts() throws {
        let store = StaticTokenStore("t")
        XCTAssertThrowsError(try QuantAPIClient(baseURL: URL(string: "http://quant.example.com")!, tokens: store))
        XCTAssertNoThrow(try QuantAPIClient(baseURL: URL(string: "https://quant.example.com")!, tokens: store))
        XCTAssertNoThrow(try QuantAPIClient(baseURL: URL(string: "http://127.0.0.1:8000")!, tokens: store))
        XCTAssertNoThrow(try QuantAPIClient(baseURL: URL(string: "http://100.101.102.103:8000")!, tokens: store))
    }

    func testPythonTimestampsParse() throws {
        let micro = try XCTUnwrap(QuantDates.parse("2026-11-18T00:07:51.465818+00:00"))
        let zulu = try XCTUnwrap(QuantDates.parse("2026-11-18T00:07:51.465Z"))
        XCTAssertEqual(micro.timeIntervalSince1970, zulu.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertNotNil(QuantDates.parse("2026-11-18T00:00:00+00:00"))
        XCTAssertNotNil(QuantDates.parse("2026-11-18T00:00:00"))
        XCTAssertNil(QuantDates.parse("yesterday"))
    }

    func testMoneyIsNeverParsedFromFloats() throws {
        let json = #"{"currency":"USDT","initial_equity":"10000","equity":"1e4","pnl":"0","return_pct":0,"position":"0","last_price":null,"equity_curve":[]}"#
        XCTAssertThrowsError(try QuantDates.decoder().decode(ProfitAndLoss.self, from: Data(json.utf8)))
    }
}
