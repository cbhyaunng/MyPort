import XCTest
@testable import MyPortApp

final class PortfolioSummaryServiceTests: XCTestCase {
    func testTotalKRWUsesRecordedExchangeRates() {
        let snapshot = PortfolioSnapshot(
            title: "Test Snapshot",
            capturedAt: .now,
            holdings: [
                AssetPosition(name: "국내 예수금", assetClass: .cashEquivalent, marketValue: 1_000_000, currency: "KRW"),
                AssetPosition(name: "Apple", symbol: "AAPL", assetClass: .foreignStock, marketValue: 100, currency: "USD"),
                AssetPosition(name: "ETH", symbol: "ETH", assetClass: .crypto, marketValue: 50, currency: "USDT")
            ],
            exchangeRates: [
                ExchangeRateRecord(baseCurrency: "KRW", rateToQuote: 1),
                ExchangeRateRecord(baseCurrency: "USD", rateToQuote: 1_400),
                ExchangeRateRecord(baseCurrency: "USDT", rateToQuote: 1_395)
            ]
        )

        let service = PortfolioSummaryService()

        XCTAssertEqual(service.totalKRW(for: snapshot), 1_209_750, accuracy: 0.001)
    }
}
