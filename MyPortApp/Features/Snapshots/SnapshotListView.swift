import SwiftUI

struct SnapshotListView: View {
    @EnvironmentObject private var portfolioStore: PortfolioStore

    @State private var isPresentingEditor = false
    @State private var selectedFilter: HistoryRangeFilter = .all

    private let timelineService = PortfolioTimelineService()
    private let allocationService = PortfolioAllocationService()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("기간", selection: $selectedFilter) {
                        ForEach(HistoryRangeFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if timelineSections.isEmpty {
                    ContentUnavailableView(
                        "기록된 히스토리가 없습니다",
                        systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                        description: Text("새 스냅샷을 추가하면 날짜별 기록과 변화 분석을 확인할 수 있습니다.")
                    )
                } else {
                    ForEach(timelineSections) { section in
                        Section(section.monthLabel) {
                            ForEach(section.entries) { entry in
                                NavigationLink {
                                    SnapshotDetailView(snapshot: entry.snapshot)
                                } label: {
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack(alignment: .firstTextBaseline) {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(entry.snapshot.title)
                                                    .font(.headline)

                                                Text(AppFormatters.shortDate(entry.snapshot.capturedAt))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }

                                            Spacer()

                                            VStack(alignment: .trailing, spacing: 4) {
                                                Text(AppFormatters.currency(entry.totalKRW, code: "KRW"))
                                                    .font(.subheadline.weight(.semibold))

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

                                        let highlights = allocationHighlights(for: entry.snapshot)
                                        if highlights.isEmpty == false {
                                            Text(highlights)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                            .onDelete { offsets in
                                let ids = offsets.map { section.entries[$0].snapshot.id }
                                Task {
                                    for id in ids {
                                        await portfolioStore.deleteSnapshot(id: id)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("히스토리")
            .refreshable {
                await portfolioStore.refresh()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresentingEditor = true
                    } label: {
                        Label("새 스냅샷", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isPresentingEditor) {
                SnapshotEditorView()
            }
        }
    }

    private var timelineSections: [TimelineSection] {
        timelineService.sections(
            for: portfolioStore.snapshots,
            filter: selectedFilter
        )
    }

    private func allocationHighlights(for snapshot: PortfolioSnapshot) -> String {
        allocationService.slices(for: snapshot)
            .prefix(2)
            .map { slice in
                "\(slice.assetClass.displayName) \(AppFormatters.percent(slice.percentage))"
            }
            .joined(separator: " · ")
    }
}
