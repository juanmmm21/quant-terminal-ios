import Foundation

/// `GET /api/v1/mobile/overview` — everything the app shows, in one call.
public struct Overview: Decodable, Equatable, Sendable {
    public let generatedAt: Date
    public let bot: BotState
    public let trader: TraderState
    public let strategy: StrategyInfo?
    public let pnl: ProfitAndLoss
    public let alerts: [AlertItem]
    public let disclaimer: String
}

public struct BotState: Decodable, Equatable, Sendable {
    public enum Status: String, Decodable, Sendable { case running, paused, panic }
    public let status: Status
    public let message: String?
    public let updatedAt: Date
}

public struct TraderState: Decodable, Equatable, Sendable {
    public let alive: Bool
    public let heartbeatAgeSeconds: Double?
    public let venue: String?
    public let lastAction: String?
    public let haltedReason: String?
    public let killPending: Bool
}

public struct StrategyInfo: Decodable, Equatable, Sendable {
    public let name: String
    public let timeframe: String
    public let symbol: String?
    public let gatePassed: Bool?
    public let promotedAt: Date?
}

public struct EquityPoint: Decodable, Equatable, Sendable, Identifiable {
    public let at: Date
    public let equity: Decimal
    public var id: Date { at }

    enum CodingKeys: String, CodingKey { case at, equity }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        at = try container.decode(Date.self, forKey: .at)
        equity = try DecimalString.decode(container, .equity)
    }
}

/// Money arrives as decimal strings and stays `Decimal`: never `Double`.
public struct ProfitAndLoss: Decodable, Equatable, Sendable {
    public let currency: String
    public let initialEquity: Decimal
    public let equity: Decimal
    public let pnl: Decimal
    public let returnPct: Double
    public let position: Decimal
    public let lastPrice: Decimal?
    public let equityCurve: [EquityPoint]

    enum CodingKeys: String, CodingKey {
        case currency, initialEquity, equity, pnl, returnPct, position, lastPrice, equityCurve
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        currency = try c.decode(String.self, forKey: .currency)
        initialEquity = try DecimalString.decode(c, .initialEquity)
        equity = try DecimalString.decode(c, .equity)
        pnl = try DecimalString.decode(c, .pnl)
        returnPct = try c.decode(Double.self, forKey: .returnPct)
        position = try DecimalString.decode(c, .position)
        lastPrice = try c.decodeIfPresent(String.self, forKey: .lastPrice)
            .map { try DecimalString.parse($0, key: CodingKeys.lastPrice.stringValue) }
        equityCurve = try c.decode([EquityPoint].self, forKey: .equityCurve)
    }
}

public struct AlertItem: Decodable, Equatable, Sendable, Identifiable {
    public enum Severity: String, Decodable, Sendable, Comparable {
        case info, warning, critical
        private var rank: Int { [.info: 0, .warning: 1, .critical: 2][self] ?? 0 }
        public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rank < rhs.rank }
    }

    public let alertId: String
    public let at: String
    public let kind: String
    public let severity: Severity
    public let title: String
    public let body: String
    public var id: String { alertId }
}

public struct BotActionResponse: Decodable, Equatable, Sendable {
    public let status: BotState.Status
    public let updatedAt: Date
    public let action: String
    public let message: String
}

enum DecimalString {
    static func parse(_ text: String, key: String) throws -> Decimal {
        guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
              text.range(of: #"^-?[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil
        else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "\(key) is not a decimal string: \(text)"))
        }
        return value
    }

    static func decode<K: CodingKey>(_ container: KeyedDecodingContainer<K>, _ key: K) throws -> Decimal {
        try parse(try container.decode(String.self, forKey: key), key: key.stringValue)
    }
}
