import Foundation

enum SamplePortfolioFixtures {
    static func makeSnapshots() -> [PortfolioSnapshot] {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let march = calendar.date(byAdding: .month, value: 0, to: now) ?? now
        let february = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        let january = calendar.date(byAdding: .month, value: -2, to: now) ?? now

        let latest = PortfolioSnapshot(
            title: "2026년 3월 포트폴리오",
            capturedAt: march,
            note: "개발용 mock 서버 데이터",
            baseCurrency: "KRW",
            holdings: [
                AssetPosition(name: "삼성전자", symbol: "005930", institution: "키움증권", assetClass: .domesticStock, quantity: 42, marketValue: 3_721_200, currency: "KRW", country: "KR"),
                AssetPosition(name: "Apple", symbol: "AAPL", institution: "키움증권", assetClass: .foreignStock, quantity: 18, marketValue: 4_860, currency: "USD", country: "US"),
                AssetPosition(name: "SCHD", symbol: "SCHD", institution: "키움증권", assetClass: .foreignStock, quantity: 25, marketValue: 2_175, currency: "USD", country: "US"),
                AssetPosition(name: "원화 예수금", institution: "신한은행", assetClass: .cashEquivalent, marketValue: 5_400_000, currency: "KRW", country: "KR"),
                AssetPosition(name: "USDT 잔고", symbol: "USDT", institution: "OKX", assetClass: .cashEquivalent, quantity: 1_250, marketValue: 1_250, currency: "USDT", country: "SC"),
                AssetPosition(name: "Ethereum", symbol: "ETH", institution: "OKX", assetClass: .crypto, quantity: 2.8, marketValue: 8_920, currency: "USDT", country: "SC"),
                AssetPosition(name: "국채 10년", institution: "메리츠증권", assetClass: .bond, quantity: 1, marketValue: 1_200_000, currency: "KRW", country: "KR")
            ],
            exchangeRates: [
                ExchangeRateRecord(baseCurrency: "KRW", rateToQuote: 1, source: "system", observedAt: march),
                ExchangeRateRecord(baseCurrency: "USD", rateToQuote: 1_472.30, source: "manual", observedAt: march),
                ExchangeRateRecord(baseCurrency: "USDT", rateToQuote: 1_471.80, source: "manual", observedAt: march)
            ],
            lastSyncedAt: march
        )

        let previous = PortfolioSnapshot(
            title: "2026년 2월 포트폴리오",
            capturedAt: february,
            note: "이전 기록 비교용 mock 데이터",
            baseCurrency: "KRW",
            holdings: [
                AssetPosition(name: "삼성전자", symbol: "005930", institution: "키움증권", assetClass: .domesticStock, quantity: 40, marketValue: 3_380_000, currency: "KRW", country: "KR"),
                AssetPosition(name: "Apple", symbol: "AAPL", institution: "키움증권", assetClass: .foreignStock, quantity: 18, marketValue: 4_520, currency: "USD", country: "US"),
                AssetPosition(name: "SCHD", symbol: "SCHD", institution: "키움증권", assetClass: .foreignStock, quantity: 20, marketValue: 1_920, currency: "USD", country: "US"),
                AssetPosition(name: "원화 예수금", institution: "신한은행", assetClass: .cashEquivalent, marketValue: 5_950_000, currency: "KRW", country: "KR"),
                AssetPosition(name: "Bitcoin", symbol: "BTC", institution: "OKX", assetClass: .crypto, quantity: 0.045, marketValue: 3_280, currency: "USDT", country: "SC"),
                AssetPosition(name: "Ethereum", symbol: "ETH", institution: "OKX", assetClass: .crypto, quantity: 3.0, marketValue: 9_460, currency: "USDT", country: "SC"),
                AssetPosition(name: "국채 10년", institution: "메리츠증권", assetClass: .bond, quantity: 1, marketValue: 1_150_000, currency: "KRW", country: "KR")
            ],
            exchangeRates: [
                ExchangeRateRecord(baseCurrency: "KRW", rateToQuote: 1, source: "system", observedAt: february),
                ExchangeRateRecord(baseCurrency: "USD", rateToQuote: 1_458.90, source: "manual", observedAt: february),
                ExchangeRateRecord(baseCurrency: "USDT", rateToQuote: 1_457.40, source: "manual", observedAt: february)
            ],
            lastSyncedAt: february
        )

        let oldest = PortfolioSnapshot(
            title: "2026년 1월 포트폴리오",
            capturedAt: january,
            note: "장기 추세 확인용 mock 데이터",
            baseCurrency: "KRW",
            holdings: [
                AssetPosition(name: "삼성전자", symbol: "005930", institution: "키움증권", assetClass: .domesticStock, quantity: 38, marketValue: 3_050_000, currency: "KRW", country: "KR"),
                AssetPosition(name: "Apple", symbol: "AAPL", institution: "키움증권", assetClass: .foreignStock, quantity: 16, marketValue: 3_960, currency: "USD", country: "US"),
                AssetPosition(name: "원화 예수금", institution: "신한은행", assetClass: .cashEquivalent, marketValue: 6_300_000, currency: "KRW", country: "KR"),
                AssetPosition(name: "Bitcoin", symbol: "BTC", institution: "OKX", assetClass: .crypto, quantity: 0.038, marketValue: 2_760, currency: "USDT", country: "SC"),
                AssetPosition(name: "국채 10년", institution: "메리츠증권", assetClass: .bond, quantity: 1, marketValue: 1_050_000, currency: "KRW", country: "KR")
            ],
            exchangeRates: [
                ExchangeRateRecord(baseCurrency: "KRW", rateToQuote: 1, source: "system", observedAt: january),
                ExchangeRateRecord(baseCurrency: "USD", rateToQuote: 1_441.80, source: "manual", observedAt: january),
                ExchangeRateRecord(baseCurrency: "USDT", rateToQuote: 1_440.20, source: "manual", observedAt: january)
            ],
            lastSyncedAt: january
        )

        return [latest, previous, oldest]
    }
}

actor MockPortfolioRepository: PortfolioRepository {
    private let state: MockServerState

    init(state: MockServerState = .shared) {
        self.state = state
    }

    func listSnapshots() async throws -> [PortfolioSnapshot] {
        try await Task.sleep(for: .milliseconds(150))
        return await state.listSnapshots()
    }

    func createSnapshot(_ snapshot: PortfolioSnapshot) async throws -> PortfolioSnapshot {
        try await Task.sleep(for: .milliseconds(150))
        return await state.saveSnapshot(snapshot)
    }

    func updateSnapshot(_ snapshot: PortfolioSnapshot) async throws -> PortfolioSnapshot {
        try await Task.sleep(for: .milliseconds(150))
        return await state.updateSnapshot(snapshot)
    }

    func deleteSnapshot(id: UUID) async throws {
        try await Task.sleep(for: .milliseconds(100))
        await state.deleteSnapshot(id: id)
    }
}
