import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var portfolioStore: PortfolioStore

    private let summaryService = PortfolioSummaryService()
    private let timelineService = PortfolioTimelineService()
    private let comparisonService = PortfolioComparisonService()

    var body: some View {
        NavigationStack {
            Group {
                if portfolioStore.isLoading && portfolioStore.snapshots.isEmpty {
                    ProgressView("서버에서 자산을 불러오는 중입니다...")
                } else if let snapshot = portfolioStore.snapshots.first {
                    let comparison = comparisonService.compare(current: snapshot, in: portfolioStore.snapshots)
                    let recentEntries = timelineService.entries(for: portfolioStore.snapshots).prefix(3)

                    List {
                        Section("연결 상태") {
                            LabeledContent("저장소", value: portfolioStore.activeRepositoryLabel)

                            if let lastRefreshedAt = portfolioStore.lastRefreshedAt {
                                LabeledContent("마지막 동기화", value: AppFormatters.date(lastRefreshedAt))
                            }
                        }

                        Section("최신 자산 스냅샷") {
                            NavigationLink {
                                SnapshotDetailView(snapshot: snapshot)
                            } label: {
                                VStack(alignment: .leading, spacing: 14) {
                                    Text(snapshot.title)
                                        .font(.headline)

                                    Text(AppFormatters.date(snapshot.capturedAt))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("총합 원화")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        Text(AppFormatters.currency(summaryService.totalKRW(for: snapshot), code: "KRW"))
                                            .font(.title2.bold())
                                    }

                                    if let comparison {
                                        VStack(alignment: .leading, spacing: 4) {
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
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }

                        Section {
                            AllocationChartView(
                                title: "자산 비중",
                                snapshot: snapshot
                            )
                        }

                        Section("자산군별 합계") {
                            ForEach(summaryService.assetClassSummaries(for: snapshot)) { summary in
                                HStack {
                                    Label(summary.assetClass.displayName, systemImage: summary.assetClass.iconName)
                                        .foregroundStyle(summary.assetClass.tint)

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text(AppFormatters.currency(summary.totalKRW, code: "KRW"))
                                            .fontWeight(.semibold)

                                        Text("\(summary.itemCount)개 항목")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }

                        if let comparison {
                            Section("직전 기록 대비 자산군 변화") {
                                ForEach(comparison.assetClassDeltas.prefix(5)) { delta in
                                    HStack {
                                        Text(delta.assetClass.displayName)
                                            .foregroundStyle(delta.assetClass.tint)

                                        Spacer()

                                        VStack(alignment: .trailing, spacing: 4) {
                                            Text(AppFormatters.signedCurrency(delta.deltaKRW, code: "KRW"))
                                                .fontWeight(.semibold)
                                                .foregroundStyle(delta.deltaKRW >= 0 ? .green : .red)

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
                            }
                        }

                        Section("최근 기록") {
                            ForEach(recentEntries) { entry in
                                NavigationLink {
                                    SnapshotDetailView(snapshot: entry.snapshot)
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(entry.snapshot.title)
                                                .font(.headline)

                                            Spacer()

                                            Text(AppFormatters.currency(entry.totalKRW, code: "KRW"))
                                                .font(.subheadline.weight(.semibold))
                                        }

                                        HStack {
                                            Text(AppFormatters.shortDate(entry.snapshot.capturedAt))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)

                                            Spacer()

                                            if let delta = entry.deltaKRWFromPrevious {
                                                Text(AppFormatters.signedCurrency(delta, code: "KRW"))
                                                    .font(.caption)
                                                    .foregroundStyle(delta >= 0 ? .green : .red)
                                            } else {
                                                Text("첫 기록")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }

                        Section("기록 당시 환율") {
                            ForEach(snapshot.exchangeRates.sorted(by: { $0.baseCurrency < $1.baseCurrency })) { rate in
                                HStack {
                                    Text("\(rate.baseCurrency)/\(rate.quoteCurrency)")

                                    Spacer()

                                    Text(AppFormatters.fxRate(rate.rateToQuote))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        Section("상위 보유 종목") {
                            ForEach(summaryService.topHoldings(in: snapshot)) { holding in
                                HoldingRowView(
                                    holding: holding,
                                    convertedValue: summaryService.convertedValueToKRW(for: holding, in: snapshot)
                                )
                            }
                        }
                    }
                    .refreshable {
                        await portfolioStore.refresh()
                    }
                } else {
                    ContentUnavailableView(
                        "저장된 자산 스냅샷이 없습니다",
                        systemImage: "tray",
                        description: Text("서버에 새 스냅샷을 저장하면 기록 당시 환율과 함께 원화 총합을 자동 계산합니다.")
                    )
                }
            }
            .navigationTitle("MyPort")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await portfolioStore.refresh()
                        }
                    } label: {
                        Label("새로고침", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
    }
}
