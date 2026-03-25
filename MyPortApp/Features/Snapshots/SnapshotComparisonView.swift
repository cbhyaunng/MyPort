import SwiftUI

struct SnapshotComparisonView: View {
    let currentSnapshot: PortfolioSnapshot
    let baselineSnapshot: PortfolioSnapshot
    let comparison: PortfolioComparison

    var body: some View {
        List {
            Section("비교 기준") {
                LabeledContent("현재 기록", value: AppFormatters.shortDate(currentSnapshot.capturedAt))
                LabeledContent("비교 기록", value: AppFormatters.shortDate(baselineSnapshot.capturedAt))
            }

            Section("총자산 변화") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(AppFormatters.signedCurrency(comparison.totalDeltaKRW, code: "KRW"))
                        .font(.title2.bold())
                        .foregroundStyle(deltaTint(for: comparison.totalDeltaKRW))

                    Text(
                        comparison.totalDeltaPercent.map(AppFormatters.signedPercent)
                        ?? "이전 기록이 없어 비율을 계산할 수 없습니다."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    LabeledContent("현재 총자산", value: AppFormatters.currency(comparison.currentTotalKRW, code: "KRW"))
                    LabeledContent("이전 총자산", value: AppFormatters.currency(comparison.baselineTotalKRW, code: "KRW"))
                }
                .padding(.vertical, 4)
            }

            Section("자산군별 변화") {
                ForEach(comparison.assetClassDeltas) { delta in
                    HStack {
                        Label(delta.assetClass.displayName, systemImage: delta.assetClass.iconName)
                            .foregroundStyle(delta.assetClass.tint)

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text(AppFormatters.signedCurrency(delta.deltaKRW, code: "KRW"))
                                .fontWeight(.semibold)
                                .foregroundStyle(deltaTint(for: delta.deltaKRW))

                            Text(
                                delta.deltaPercent.map(AppFormatters.signedPercent)
                                ?? "\(AppFormatters.currency(delta.currentTotalKRW, code: "KRW")) / 신규"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if increasedHoldings.isEmpty == false {
                Section("상승 상위") {
                    ForEach(increasedHoldings) { delta in
                        HoldingDeltaRow(delta: delta)
                    }
                }
            }

            if decreasedHoldings.isEmpty == false {
                Section("하락 상위") {
                    ForEach(decreasedHoldings) { delta in
                        HoldingDeltaRow(delta: delta)
                    }
                }
            }

            if newHoldings.isEmpty == false {
                Section("신규 편입") {
                    ForEach(newHoldings) { delta in
                        HoldingDeltaRow(delta: delta)
                    }
                }
            }

            if removedHoldings.isEmpty == false {
                Section("사라진 종목") {
                    ForEach(removedHoldings) { delta in
                        HoldingDeltaRow(delta: delta)
                    }
                }
            }
        }
        .navigationTitle("변화 분석")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var increasedHoldings: [HoldingDelta] {
        comparison.holdingDeltas
            .filter { $0.status == .increased }
            .prefix(5)
            .map { $0 }
    }

    private var decreasedHoldings: [HoldingDelta] {
        comparison.holdingDeltas
            .filter { $0.status == .decreased }
            .prefix(5)
            .map { $0 }
    }

    private var newHoldings: [HoldingDelta] {
        comparison.holdingDeltas.filter { $0.status == .new }
    }

    private var removedHoldings: [HoldingDelta] {
        comparison.holdingDeltas.filter { $0.status == .removed }
    }

    private func deltaTint(for delta: Double) -> Color {
        if delta > 0 {
            return .green
        }

        if delta < 0 {
            return .red
        }

        return .secondary
    }
}

private struct HoldingDeltaRow: View {
    let delta: HoldingDelta

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: delta.assetClass.iconName)
                .foregroundStyle(delta.assetClass.tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 6) {
                Text(delta.name)
                    .font(.headline)

                if detailLine.isEmpty == false {
                    Text(detailLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(statusLabel)
                    .font(.caption2)
                    .foregroundStyle(statusTint)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(AppFormatters.signedCurrency(delta.deltaKRW, code: "KRW"))
                    .fontWeight(.semibold)
                    .foregroundStyle(statusTint)

                Text(
                    delta.deltaPercent.map(AppFormatters.signedPercent)
                    ?? "비율 없음"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var detailLine: String {
        [delta.symbol, delta.institution]
            .filter { $0.isEmpty == false }
            .joined(separator: " · ")
    }

    private var statusLabel: String {
        switch delta.status {
        case .increased:
            return "보유 증가"
        case .decreased:
            return "보유 감소"
        case .new:
            return "신규 편입"
        case .removed:
            return "전량 제외"
        case .unchanged:
            return "변화 없음"
        }
    }

    private var statusTint: Color {
        switch delta.status {
        case .increased, .new:
            return .green
        case .decreased, .removed:
            return .red
        case .unchanged:
            return .secondary
        }
    }
}
