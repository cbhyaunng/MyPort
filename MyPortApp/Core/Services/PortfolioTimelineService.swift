import Foundation

struct PortfolioTimelineService {
    private let summaryService: PortfolioSummaryService
    private let calendar: Calendar

    init(
        summaryService: PortfolioSummaryService = PortfolioSummaryService(),
        calendar: Calendar = .current
    ) {
        self.summaryService = summaryService
        self.calendar = calendar
    }

    func sections(
        for snapshots: [PortfolioSnapshot],
        filter: HistoryRangeFilter,
        now: Date = .now
    ) -> [TimelineSection] {
        let allEntries = entries(for: snapshots)
        let filteredEntries = filterEntries(allEntries, using: filter, now: now)
        let grouped = Dictionary(grouping: filteredEntries, by: \.monthLabel)

        return filteredEntries.reduce(into: [TimelineSection]()) { result, entry in
            guard result.contains(where: { $0.monthLabel == entry.monthLabel }) == false else { return }
            result.append(
                TimelineSection(
                    monthLabel: entry.monthLabel,
                    entries: grouped[entry.monthLabel] ?? []
                )
            )
        }
    }

    func entries(for snapshots: [PortfolioSnapshot]) -> [TimelineEntry] {
        let sortedSnapshots = snapshots.sorted(by: { $0.capturedAt > $1.capturedAt })
        var entries: [TimelineEntry] = []

        for (index, snapshot) in sortedSnapshots.enumerated() {
            let totalKRW = summaryService.totalKRW(for: snapshot)
            let previousTotalKRW = sortedSnapshots.indices.contains(index + 1)
                ? summaryService.totalKRW(for: sortedSnapshots[index + 1])
                : nil

            entries.append(
                TimelineEntry(
                    snapshot: snapshot,
                    totalKRW: totalKRW,
                    deltaKRWFromPrevious: previousTotalKRW.map { totalKRW - $0 },
                    previousTotalKRW: previousTotalKRW,
                    monthLabel: AppFormatters.monthSection(snapshot.capturedAt)
                )
            )
        }

        return entries
    }

    private func filterEntries(
        _ entries: [TimelineEntry],
        using filter: HistoryRangeFilter,
        now: Date
    ) -> [TimelineEntry] {
        guard let lowerBound = lowerBound(for: filter, now: now) else {
            return entries
        }

        return entries.filter { $0.snapshot.capturedAt >= lowerBound }
    }

    private func lowerBound(for filter: HistoryRangeFilter, now: Date) -> Date? {
        switch filter {
        case .all:
            return nil
        case .threeMonths:
            return calendar.date(byAdding: .month, value: -3, to: now)
        case .sixMonths:
            return calendar.date(byAdding: .month, value: -6, to: now)
        case .oneYear:
            return calendar.date(byAdding: .year, value: -1, to: now)
        }
    }
}
