import SwiftUI

@MainActor
@main
struct MyPortApp: App {
    @StateObject private var serverConfiguration: ServerConfigurationStore
    @StateObject private var portfolioStore: PortfolioStore
    @StateObject private var analysisStore: AnalysisStore

    init() {
        let configuration = ServerConfigurationStore()
        let bundle = RepositoryFactory.make(configuration: configuration)
        let portfolioStore = PortfolioStore(bundle: bundle)

        _serverConfiguration = StateObject(wrappedValue: configuration)
        _portfolioStore = StateObject(wrappedValue: portfolioStore)
        _analysisStore = StateObject(wrappedValue: AnalysisStore(bundle: bundle, portfolioStore: portfolioStore))
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(serverConfiguration)
                .environmentObject(portfolioStore)
                .environmentObject(analysisStore)
        }
    }
}
