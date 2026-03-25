import SwiftUI

struct SnapshotDetailView: View {
    @EnvironmentObject private var portfolioStore: PortfolioStore

    let snapshot: PortfolioSnapshot

    private let summaryService = PortfolioSummaryService()
    private let comparisonService = PortfolioComparisonService()

    var body: some View {
        List {
            Section("개요") {
                LabeledContent("기록 시점", value: AppFormatters.date(resolvedSnapshot.capturedAt))
                LabeledContent("총합 원화", value: AppFormatters.currency(summaryService.totalKRW(for: resolvedSnapshot), code: "KRW"))

                if let comparison {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("직전 기록 대비")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(AppFormatters.signedCurrency(comparison.totalDeltaKRW, code: "KRW"))
                            .font(.headline)
                            .foregroundStyle(comparison.totalDeltaKRW >= 0 ? .green : .red)

                        if let percent = comparison.totalDeltaPercent {
                            Text(AppFormatters.signedPercent(percent))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if resolvedSnapshot.note.isEmpty == false {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("메모")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(resolvedSnapshot.note)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                AllocationChartView(
                    title: "자산 비중",
                    snapshot: resolvedSnapshot
                )
            }

            if let baselineSnapshot, let comparison {
                Section("직전 기록 대비") {
                    LabeledContent("비교 기록일", value: AppFormatters.shortDate(baselineSnapshot.capturedAt))
                    LabeledContent("총자산 변화", value: AppFormatters.signedCurrency(comparison.totalDeltaKRW, code: "KRW"))

                    ForEach(comparison.assetClassDeltas.prefix(5)) { delta in
                        HStack {
                            Text(delta.assetClass.displayName)
                                .foregroundStyle(delta.assetClass.tint)

                            Spacer()

                            Text(AppFormatters.signedCurrency(delta.deltaKRW, code: "KRW"))
                                .foregroundStyle(delta.deltaKRW >= 0 ? .green : .red)
                        }
                    }

                    NavigationLink {
                        SnapshotComparisonView(
                            currentSnapshot: resolvedSnapshot,
                            baselineSnapshot: baselineSnapshot,
                            comparison: comparison
                        )
                    } label: {
                        Label("변화 분석 자세히 보기", systemImage: "chart.bar.xaxis")
                    }
                }
            } else {
                Section("직전 기록 대비") {
                    ContentUnavailableView(
                        "비교할 이전 기록이 없습니다",
                        systemImage: "clock.badge.exclamationmark",
                        description: Text("두 개 이상의 스냅샷이 있으면 자산 증감 분석을 확인할 수 있습니다.")
                    )
                }
            }

            Section("환율") {
                ForEach(resolvedSnapshot.exchangeRates.sorted(by: { $0.baseCurrency < $1.baseCurrency })) { rate in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("\(rate.baseCurrency)/\(rate.quoteCurrency)")
                                .fontWeight(.semibold)

                            Spacer()

                            Text(AppFormatters.fxRate(rate.rateToQuote))
                        }

                        Text("\(AppFormatters.date(rate.observedAt)) · \(rate.source)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }

            Section("통화별 합계") {
                ForEach(summaryService.currencyBreakdowns(for: resolvedSnapshot)) { breakdown in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(breakdown.currency)
                                .fontWeight(.semibold)

                            Spacer()

                            Text(AppFormatters.currency(breakdown.originalTotal, code: breakdown.currency))
                        }

                        HStack {
                            Text("환율")
                                .foregroundStyle(.secondary)

                            Spacer()

                            Text(
                                breakdown.rateToKRW.map { "1 \(breakdown.currency) = \(AppFormatters.fxRate($0)) KRW" } ?? "환율 없음"
                            )
                            .foregroundStyle(.secondary)
                        }

                        HStack {
                            Text("원화 환산")
                                .foregroundStyle(.secondary)

                            Spacer()

                            Text(AppFormatters.currency(breakdown.totalKRW, code: "KRW"))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            ForEach(summaryService.assetClassSummaries(for: resolvedSnapshot)) { summary in
                Section(summary.assetClass.displayName) {
                    ForEach(summaryService.holdings(for: summary.assetClass, in: resolvedSnapshot)) { holding in
                        HoldingRowView(
                            holding: holding,
                            convertedValue: summaryService.convertedValueToKRW(for: holding, in: resolvedSnapshot)
                        )
                    }
                }
            }
        }
        .navigationTitle(resolvedSnapshot.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var resolvedSnapshot: PortfolioSnapshot {
        portfolioStore.snapshot(id: snapshot.id) ?? snapshot
    }

    private var baselineSnapshot: PortfolioSnapshot? {
        comparisonService.baselineSnapshot(for: resolvedSnapshot, in: portfolioStore.snapshots)
    }

    private var comparison: PortfolioComparison? {
        comparisonService.compare(current: resolvedSnapshot, in: portfolioStore.snapshots)
    }
}
