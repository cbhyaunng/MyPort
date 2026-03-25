import Foundation

struct RepositoryBundle {
    let portfolioRepository: any PortfolioRepository
    let analysisRepository: any AnalysisRepository
    let label: String
}

enum RepositoryFactory {
    @MainActor
    static func make(configuration: ServerConfigurationStore) -> RepositoryBundle {
        if configuration.useMockServer {
            let state = MockServerState.shared
            return RepositoryBundle(
                portfolioRepository: MockPortfolioRepository(state: state),
                analysisRepository: MockAnalysisRepository(state: state),
                label: "Mock Server"
            )
        }

        guard let baseURL = configuration.normalizedBaseURL else {
            let state = MockServerState.shared
            return RepositoryBundle(
                portfolioRepository: MockPortfolioRepository(state: state),
                analysisRepository: MockAnalysisRepository(state: state),
                label: "Mock Server (Base URL 미설정)"
            )
        }

        return RepositoryBundle(
            portfolioRepository: RemotePortfolioRepository(
                baseURL: baseURL,
                bearerToken: configuration.trimmedBearerToken
            ),
            analysisRepository: RemoteAnalysisRepository(
                baseURL: baseURL,
                bearerToken: configuration.trimmedBearerToken
            ),
            label: baseURL.absoluteString
        )
    }
}
