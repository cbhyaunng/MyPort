import Foundation

struct AssetClassSummary: Identifiable {
    let assetClass: AssetClass
    let totalKRW: Double
    let itemCount: Int

    var id: String { assetClass.id }
}

struct CurrencyBreakdown: Identifiable {
    let currency: String
    let originalTotal: Double
    let rateToKRW: Double?
    let totalKRW: Double

    var id: String { currency }
}

struct PortfolioSummaryService {
    func totalKRW(for snapshot: PortfolioSnapshot) -> Double {
        snapshot.holdings.reduce(0) { partialResult, holding in
            partialResult + convertedValueToKRW(for: holding, in: snapshot)
        }
    }

    func convertedValueToKRW(for holding: AssetPosition, in snapshot: PortfolioSnapshot) -> Double {
        guard let marketValue = holding.marketValue else { return 0 }
        guard let rate = rateToKRW(for: holding.currency, in: snapshot) else { return 0 }
        return marketValue * rate
    }

    func rateToKRW(for currency: String, in snapshot: PortfolioSnapshot) -> Double? {
        let normalizedCurrency = currency.uppercased()

        if normalizedCurrency == "KRW" {
            return 1
        }

        return snapshot.exchangeRates.first {
            $0.baseCurrency == normalizedCurrency && $0.quoteCurrency == "KRW"
        }?.rateToQuote
    }

    func assetClassSummaries(for snapshot: PortfolioSnapshot) -> [AssetClassSummary] {
        let grouped = Dictionary(grouping: snapshot.holdings) { $0.assetClass }

        return AssetClass.allCases.compactMap { assetClass in
            guard let holdings = grouped[assetClass], holdings.isEmpty == false else { return nil }

            let total = holdings.reduce(0) { partialResult, holding in
                partialResult + convertedValueToKRW(for: holding, in: snapshot)
            }

            return AssetClassSummary(assetClass: assetClass, totalKRW: total, itemCount: holdings.count)
        }
    }

    func currencyBreakdowns(for snapshot: PortfolioSnapshot) -> [CurrencyBreakdown] {
        let grouped = Dictionary(grouping: snapshot.holdings) { $0.currency.uppercased() }

        return grouped.keys.sorted().compactMap { currency in
            guard let holdings = grouped[currency] else { return nil }

            let originalTotal = holdings.reduce(0) { partialResult, holding in
                partialResult + (holding.marketValue ?? 0)
            }

            let rate = rateToKRW(for: currency, in: snapshot)
            let totalKRW = holdings.reduce(0) { partialResult, holding in
                partialResult + convertedValueToKRW(for: holding, in: snapshot)
            }

            return CurrencyBreakdown(
                currency: currency,
                originalTotal: originalTotal,
                rateToKRW: rate,
                totalKRW: totalKRW
            )
        }
    }

    func holdings(for assetClass: AssetClass, in snapshot: PortfolioSnapshot) -> [AssetPosition] {
        snapshot.holdings
            .filter { $0.assetClass == assetClass }
            .sorted {
                convertedValueToKRW(for: $0, in: snapshot) > convertedValueToKRW(for: $1, in: snapshot)
            }
    }

    func topHoldings(in snapshot: PortfolioSnapshot, limit: Int = 5) -> [AssetPosition] {
        snapshot.holdings
            .sorted {
                convertedValueToKRW(for: $0, in: snapshot) > convertedValueToKRW(for: $1, in: snapshot)
            }
            .prefix(limit)
            .map { $0 }
    }
}
