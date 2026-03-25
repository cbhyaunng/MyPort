import Charts
import SwiftUI

struct AllocationChartView: View {
    let title: String
    let snapshot: PortfolioSnapshot

    private let summaryService = PortfolioSummaryService()
    private let allocationService = PortfolioAllocationService()

    var body: some View {
        let slices = allocationService.slices(for: snapshot)
        let totalKRW = summaryService.totalKRW(for: snapshot)

        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)

            if slices.isEmpty {
                ContentUnavailableView(
                    "비중 정보를 계산할 수 없습니다",
                    systemImage: "chart.pie"
                )
            } else {
                VStack(spacing: 16) {
                    VStack(spacing: 4) {
                        Text("총합 원화")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(AppFormatters.currency(totalKRW, code: "KRW"))
                            .font(.title3.bold())
                    }
                    .frame(maxWidth: .infinity)

                    Chart(slices) { slice in
                        SectorMark(
                            angle: .value("금액", slice.totalKRW),
                            innerRadius: .ratio(0.58),
                            angularInset: 2
                        )
                        .foregroundStyle(slice.assetClass.tint)
                    }
                    .chartLegend(.hidden)
                    .frame(height: 220)

                    VStack(spacing: 10) {
                        ForEach(slices) { slice in
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(slice.assetClass.tint)
                                    .frame(width: 10, height: 10)

                                Text(slice.assetClass.displayName)

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(AppFormatters.currency(slice.totalKRW, code: "KRW"))
                                        .fontWeight(.semibold)

                                    Text(AppFormatters.percent(slice.percentage))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
