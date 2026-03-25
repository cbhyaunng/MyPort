import Foundation

struct PortfolioAllocationService {
    private let summaryService: PortfolioSummaryService

    init(summaryService: PortfolioSummaryService = PortfolioSummaryService()) {
        self.summaryService = summaryService
    }

    func slices(for snapshot: PortfolioSnapshot) -> [AllocationSlice] {
        let summaries = summaryService.assetClassSummaries(for: snapshot)
        let totalKRW = summaries.reduce(0) { $0 + $1.totalKRW }

        guard totalKRW > 0 else { return [] }

        return summaries.map { summary in
            AllocationSlice(
                assetClass: summary.assetClass,
                totalKRW: summary.totalKRW,
                percentage: summary.totalKRW / totalKRW
            )
        }
        .sorted { $0.totalKRW > $1.totalKRW }
    }
}
