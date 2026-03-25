import Foundation

struct PortfolioComparisonService {
    private let summaryService: PortfolioSummaryService
    private let epsilon: Double

    init(
        summaryService: PortfolioSummaryService = PortfolioSummaryService(),
        epsilon: Double = 0.5
    ) {
        self.summaryService = summaryService
        self.epsilon = epsilon
    }

    func baselineSnapshot(
        for snapshot: PortfolioSnapshot,
        in snapshots: [PortfolioSnapshot]
    ) -> PortfolioSnapshot? {
        let sortedSnapshots = snapshots.sorted(by: { $0.capturedAt > $1.capturedAt })

        guard let index = sortedSnapshots.firstIndex(where: { $0.id == snapshot.id }) else {
            return nil
        }

        let baselineIndex = sortedSnapshots.index(after: index)
        guard sortedSnapshots.indices.contains(baselineIndex) else { return nil }
        return sortedSnapshots[baselineIndex]
    }

    func compare(
        current snapshot: PortfolioSnapshot,
        in snapshots: [PortfolioSnapshot]
    ) -> PortfolioComparison? {
        guard let baseline = baselineSnapshot(for: snapshot, in: snapshots) else {
            return nil
        }

        return compare(current: snapshot, baseline: baseline)
    }

    func compare(
        current: PortfolioSnapshot,
        baseline: PortfolioSnapshot
    ) -> PortfolioComparison {
        let currentTotalKRW = summaryService.totalKRW(for: current)
        let baselineTotalKRW = summaryService.totalKRW(for: baseline)
        let totalDeltaKRW = currentTotalKRW - baselineTotalKRW

        return PortfolioComparison(
            currentSnapshotId: current.id,
            baselineSnapshotId: baseline.id,
            currentTotalKRW: currentTotalKRW,
            baselineTotalKRW: baselineTotalKRW,
            totalDeltaKRW: totalDeltaKRW,
            totalDeltaPercent: percentageDelta(current: currentTotalKRW, baseline: baselineTotalKRW),
            assetClassDeltas: assetClassDeltas(current: current, baseline: baseline),
            holdingDeltas: holdingDeltas(current: current, baseline: baseline)
        )
    }

    private func assetClassDeltas(
        current: PortfolioSnapshot,
        baseline: PortfolioSnapshot
    ) -> [AssetClassDelta] {
        let currentSummaries = Dictionary(uniqueKeysWithValues: summaryService.assetClassSummaries(for: current).map { ($0.assetClass, $0.totalKRW) })
        let baselineSummaries = Dictionary(uniqueKeysWithValues: summaryService.assetClassSummaries(for: baseline).map { ($0.assetClass, $0.totalKRW) })

        return AssetClass.allCases.compactMap { assetClass in
            let currentTotalKRW = currentSummaries[assetClass] ?? 0
            let baselineTotalKRW = baselineSummaries[assetClass] ?? 0

            guard abs(currentTotalKRW) > epsilon || abs(baselineTotalKRW) > epsilon else {
                return nil
            }

            return AssetClassDelta(
                assetClass: assetClass,
                currentTotalKRW: currentTotalKRW,
                baselineTotalKRW: baselineTotalKRW,
                deltaKRW: currentTotalKRW - baselineTotalKRW,
                deltaPercent: percentageDelta(current: currentTotalKRW, baseline: baselineTotalKRW)
            )
        }
        .sorted { abs($0.deltaKRW) > abs($1.deltaKRW) }
    }

    private func holdingDeltas(
        current: PortfolioSnapshot,
        baseline: PortfolioSnapshot
    ) -> [HoldingDelta] {
        let currentHoldings = aggregatedHoldings(for: current)
        let baselineHoldings = aggregatedHoldings(for: baseline)
        let keys = Set(currentHoldings.keys).union(baselineHoldings.keys)

        return keys.compactMap { key in
            let currentHolding = currentHoldings[key]
            let baselineHolding = baselineHoldings[key]
            let currentValueKRW = currentHolding?.marketValueKRW ?? 0
            let baselineValueKRW = baselineHolding?.marketValueKRW ?? 0

            guard abs(currentValueKRW) > epsilon || abs(baselineValueKRW) > epsilon else {
                return nil
            }

            let deltaKRW = currentValueKRW - baselineValueKRW
            let resolved = currentHolding ?? baselineHolding

            guard let resolved else { return nil }

            return HoldingDelta(
                holdingKey: key,
                name: resolved.name,
                symbol: resolved.symbol,
                institution: resolved.institution,
                assetClass: resolved.assetClass,
                currency: resolved.currency,
                currentValueKRW: currentValueKRW,
                baselineValueKRW: baselineValueKRW,
                deltaKRW: deltaKRW,
                deltaPercent: percentageDelta(current: currentValueKRW, baseline: baselineValueKRW),
                currentQuantity: currentHolding?.quantity,
                baselineQuantity: baselineHolding?.quantity,
                status: status(currentValueKRW: currentValueKRW, baselineValueKRW: baselineValueKRW, deltaKRW: deltaKRW)
            )
        }
        .sorted { abs($0.deltaKRW) > abs($1.deltaKRW) }
    }

    private func aggregatedHoldings(for snapshot: PortfolioSnapshot) -> [String: AggregatedHolding] {
        snapshot.holdings.reduce(into: [String: AggregatedHolding]()) { result, holding in
            let key = holding.comparisonKey
            let convertedValue = summaryService.convertedValueToKRW(for: holding, in: snapshot)

            if var existing = result[key] {
                existing.marketValueKRW += convertedValue
                existing.quantity = sum(existing.quantity, holding.quantity)
                result[key] = existing
            } else {
                result[key] = AggregatedHolding(
                    key: key,
                    name: holding.name,
                    symbol: holding.symbol,
                    institution: holding.institution,
                    assetClass: holding.assetClass,
                    currency: holding.currency,
                    quantity: holding.quantity,
                    marketValueKRW: convertedValue
                )
            }
        }
    }

    private func sum(_ lhs: Double?, _ rhs: Double?) -> Double? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return lhs + rhs
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        case (nil, nil):
            return nil
        }
    }

    private func percentageDelta(current: Double, baseline: Double) -> Double? {
        guard abs(baseline) > epsilon else { return nil }
        return (current - baseline) / baseline
    }

    private func status(
        currentValueKRW: Double,
        baselineValueKRW: Double,
        deltaKRW: Double
    ) -> HoldingDeltaStatus {
        if abs(baselineValueKRW) <= epsilon {
            return .new
        }

        if abs(currentValueKRW) <= epsilon {
            return .removed
        }

        if abs(deltaKRW) <= epsilon {
            return .unchanged
        }

        return deltaKRW > 0 ? .increased : .decreased
    }
}

private struct AggregatedHolding {
    let key: String
    let name: String
    let symbol: String
    let institution: String
    let assetClass: AssetClass
    let currency: String
    var quantity: Double?
    var marketValueKRW: Double
}

private extension AssetPosition {
    var comparisonKey: String {
        let identity = symbol.isEmpty ? name.lowercased() : symbol.uppercased()
        return [
            identity,
            institution.lowercased(),
            assetClass.rawValue,
            currency.uppercased()
        ].joined(separator: "::")
    }
}
