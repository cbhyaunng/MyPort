import XCTest
@testable import MyPortApp

final class PortfolioAnalyticsServicesTests: XCTestCase {
    func testTimelineServiceBuildsDescendingEntriesWithDelta() {
        let snapshots = [
            makeSnapshot(
                title: "March",
                capturedAt: date(year: 2026, month: 3, day: 25),
                holdings: [
                    AssetPosition(name: "예수금", assetClass: .cashEquivalent, marketValue: 1_200_000, currency: "KRW")
                ]
            ),
            makeSnapshot(
                title: "February",
                capturedAt: date(year: 2026, month: 2, day: 25),
                holdings: [
                    AssetPosition(name: "예수금", assetClass: .cashEquivalent, marketValue: 1_000_000, currency: "KRW")
                ]
            )
        ]

        let service = PortfolioTimelineService()
        let sections = service.sections(for: snapshots, filter: .all, now: date(year: 2026, month: 3, day: 30))

        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections.first?.entries.first?.snapshot.title, "March")
        XCTAssertEqual(sections.first?.entries.first?.deltaKRWFromPrevious ?? 0, 200_000, accuracy: 0.001)
        XCTAssertNil(sections.last?.entries.first?.deltaKRWFromPrevious)
    }

    func testComparisonServiceDetectsIncreaseNewAndRemovedHoldings() {
        let baseline = makeSnapshot(
            title: "Baseline",
            capturedAt: date(year: 2026, month: 2, day: 25),
            holdings: [
                AssetPosition(name: "삼성전자", symbol: "005930", institution: "키움", assetClass: .domesticStock, marketValue: 1_000_000, currency: "KRW"),
                AssetPosition(name: "Bitcoin", symbol: "BTC", institution: "OKX", assetClass: .crypto, marketValue: 100, currency: "USDT")
            ],
            exchangeRates: [
                ExchangeRateRecord(baseCurrency: "KRW", rateToQuote: 1),
                ExchangeRateRecord(baseCurrency: "USDT", rateToQuote: 1_400)
            ]
        )
        let current = makeSnapshot(
            title: "Current",
            capturedAt: date(year: 2026, month: 3, day: 25),
            holdings: [
                AssetPosition(name: "삼성전자", symbol: "005930", institution: "키움", assetClass: .domesticStock, marketValue: 1_250_000, currency: "KRW"),
                AssetPosition(name: "Apple", symbol: "AAPL", institution: "키움", assetClass: .foreignStock, marketValue: 300, currency: "USD")
            ],
            exchangeRates: [
                ExchangeRateRecord(baseCurrency: "KRW", rateToQuote: 1),
                ExchangeRateRecord(baseCurrency: "USD", rateToQuote: 1_500)
            ]
        )

        let comparison = PortfolioComparisonService().compare(current: current, baseline: baseline)

        XCTAssertEqual(comparison.totalDeltaKRW, 560_000, accuracy: 0.001)
        XCTAssertEqual(comparison.assetClassDeltas.first(where: { $0.assetClass == .domesticStock })?.deltaKRW ?? 0, 250_000, accuracy: 0.001)
        XCTAssertEqual(comparison.holdingDeltas.first(where: { $0.symbol == "AAPL" })?.status, .new)
        XCTAssertEqual(comparison.holdingDeltas.first(where: { $0.symbol == "BTC" })?.status, .removed)
        XCTAssertEqual(comparison.holdingDeltas.first(where: { $0.symbol == "005930" })?.status, .increased)
    }

    func testAllocationServiceBuildsPercentagesFromAssetClassTotals() {
        let snapshot = makeSnapshot(
            title: "Allocation",
            capturedAt: date(year: 2026, month: 3, day: 25),
            holdings: [
                AssetPosition(name: "국내주식", assetClass: .domesticStock, marketValue: 2_000_000, currency: "KRW"),
                AssetPosition(name: "예수금", assetClass: .cashEquivalent, marketValue: 1_000_000, currency: "KRW")
            ]
        )

        let slices = PortfolioAllocationService().slices(for: snapshot)

        XCTAssertEqual(slices.count, 2)
        XCTAssertEqual(slices.first?.assetClass, .domesticStock)
        XCTAssertEqual(slices.first?.percentage ?? 0, 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(slices.reduce(0) { $0 + $1.percentage }, 1, accuracy: 0.0001)
    }

    private func makeSnapshot(
        title: String,
        capturedAt: Date,
        holdings: [AssetPosition],
        exchangeRates: [ExchangeRateRecord] = [ExchangeRateRecord(baseCurrency: "KRW", rateToQuote: 1)]
    ) -> PortfolioSnapshot {
        PortfolioSnapshot(
            title: title,
            capturedAt: capturedAt,
            holdings: holdings,
            exchangeRates: exchangeRates
        )
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        components.minute = 0
        components.calendar = Calendar(identifier: .gregorian)
        return components.date ?? .now
    }
}
