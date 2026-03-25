import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var portfolioStore: PortfolioStore

    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("대시보드", systemImage: "chart.pie.fill")
                }

            ImportView()
                .tabItem {
                    Label("업로드", systemImage: "photo.badge.arrow.down")
                }

            SnapshotListView()
                .tabItem {
                    Label("히스토리", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                }

            SettingsView()
                .tabItem {
                    Label("설정", systemImage: "gearshape.fill")
                }
        }
        .task {
            await portfolioStore.loadIfNeeded()
        }
        .alert(
            "서버 오류",
            isPresented: Binding(
                get: { portfolioStore.errorMessage != nil },
                set: { if $0 == false { portfolioStore.dismissError() } }
            )
        ) {
            Button("확인", role: .cancel) {
                portfolioStore.dismissError()
            }
        } message: {
            Text(portfolioStore.errorMessage ?? "")
        }
    }
}
