import Foundation

@MainActor
final class PortfolioStore: ObservableObject {
    @Published private(set) var snapshots: [PortfolioSnapshot] = []
    @Published private(set) var activeRepositoryLabel: String
    @Published private(set) var lastRefreshedAt: Date?
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?

    private var repository: any PortfolioRepository
    private var hasLoadedOnce = false

    init(bundle: RepositoryBundle) {
        self.repository = bundle.portfolioRepository
        self.activeRepositoryLabel = bundle.label
    }

    func loadIfNeeded() async {
        guard hasLoadedOnce == false else { return }
        await refresh()
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            snapshots = try await repository.listSnapshots()
            lastRefreshedAt = .now
            errorMessage = nil
            hasLoadedOnce = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createSnapshot(_ snapshot: PortfolioSnapshot) async -> Bool {
        isSaving = true
        defer { isSaving = false }

        do {
            let created = try await repository.createSnapshot(snapshot)
            snapshots.append(created)
            snapshots.sort(by: { $0.capturedAt > $1.capturedAt })
            errorMessage = nil
            lastRefreshedAt = .now
            hasLoadedOnce = true
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func updateSnapshot(_ snapshot: PortfolioSnapshot) async -> Bool {
        isSaving = true
        defer { isSaving = false }

        do {
            let updated = try await repository.updateSnapshot(snapshot)
            snapshots.removeAll { $0.id == updated.id }
            snapshots.append(updated)
            snapshots.sort(by: { $0.capturedAt > $1.capturedAt })
            errorMessage = nil
            lastRefreshedAt = .now
            hasLoadedOnce = true
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteSnapshot(at offsets: IndexSet) async {
        let ids = offsets.map { snapshots[$0].id }

        do {
            for id in ids {
                try await repository.deleteSnapshot(id: id)
            }

            snapshots.removeAll { ids.contains($0.id) }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteSnapshot(id: UUID) async {
        do {
            try await repository.deleteSnapshot(id: id)
            snapshots.removeAll { $0.id == id }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func snapshot(id: UUID) -> PortfolioSnapshot? {
        snapshots.first { $0.id == id }
    }

    func reconfigure(bundle: RepositoryBundle) {
        repository = bundle.portfolioRepository
        activeRepositoryLabel = bundle.label
        hasLoadedOnce = false
        lastRefreshedAt = nil
        snapshots = []
    }

    func dismissError() {
        errorMessage = nil
    }
}
