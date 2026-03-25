import Foundation

struct TimelineEntry: Identifiable, Hashable {
    let snapshot: PortfolioSnapshot
    let totalKRW: Double
    let deltaKRWFromPrevious: Double?
    let previousTotalKRW: Double?
    let monthLabel: String

    var id: UUID { snapshot.id }
}

struct TimelineSection: Identifiable, Hashable {
    let monthLabel: String
    let entries: [TimelineEntry]

    var id: String { monthLabel }
}

enum HistoryRangeFilter: String, CaseIterable, Identifiable {
    case all
    case threeMonths
    case sixMonths
    case oneYear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "전체"
        case .threeMonths:
            return "3개월"
        case .sixMonths:
            return "6개월"
        case .oneYear:
            return "1년"
        }
    }
}

struct PortfolioComparison: Hashable {
    let currentSnapshotId: UUID
    let baselineSnapshotId: UUID
    let currentTotalKRW: Double
    let baselineTotalKRW: Double
    let totalDeltaKRW: Double
    let totalDeltaPercent: Double?
    let assetClassDeltas: [AssetClassDelta]
    let holdingDeltas: [HoldingDelta]
}

struct AssetClassDelta: Identifiable, Hashable {
    let assetClass: AssetClass
    let currentTotalKRW: Double
    let baselineTotalKRW: Double
    let deltaKRW: Double
    let deltaPercent: Double?

    var id: String { assetClass.id }
}

enum HoldingDeltaStatus: String, Hashable {
    case increased
    case decreased
    case new
    case removed
    case unchanged
}

struct HoldingDelta: Identifiable, Hashable {
    let holdingKey: String
    let name: String
    let symbol: String
    let institution: String
    let assetClass: AssetClass
    let currency: String
    let currentValueKRW: Double
    let baselineValueKRW: Double
    let deltaKRW: Double
    let deltaPercent: Double?
    let currentQuantity: Double?
    let baselineQuantity: Double?
    let status: HoldingDeltaStatus

    var id: String { holdingKey }
}

struct AllocationSlice: Identifiable, Hashable {
    let assetClass: AssetClass
    let totalKRW: Double
    let percentage: Double

    var id: String { assetClass.id }
}
