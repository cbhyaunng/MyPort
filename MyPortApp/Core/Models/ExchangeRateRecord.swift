import Foundation

struct ExchangeRateRecord: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var baseCurrency: String
    var quoteCurrency: String
    var rateToQuote: Double
    var source: String
    var observedAt: Date

    init(
        id: UUID = UUID(),
        baseCurrency: String,
        quoteCurrency: String = "KRW",
        rateToQuote: Double,
        source: String = "manual",
        observedAt: Date = .now
    ) {
        self.id = id
        self.baseCurrency = baseCurrency.uppercased()
        self.quoteCurrency = quoteCurrency.uppercased()
        self.rateToQuote = rateToQuote
        self.source = source
        self.observedAt = observedAt
    }
}
