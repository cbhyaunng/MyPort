import Foundation

struct PortfolioSnapshot: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var capturedAt: Date
    var note: String
    var createdAt: Date
    var baseCurrency: String
    var holdings: [AssetPosition]
    var exchangeRates: [ExchangeRateRecord]
    var lastSyncedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        capturedAt: Date,
        note: String = "",
        createdAt: Date = .now,
        baseCurrency: String = "KRW",
        holdings: [AssetPosition] = [],
        exchangeRates: [ExchangeRateRecord] = [],
        lastSyncedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.capturedAt = capturedAt
        self.note = note
        self.createdAt = createdAt
        self.baseCurrency = baseCurrency
        self.holdings = holdings
        self.exchangeRates = exchangeRates
        self.lastSyncedAt = lastSyncedAt
    }
}
