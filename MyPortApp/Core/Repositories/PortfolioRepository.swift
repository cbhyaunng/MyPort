import Foundation

protocol PortfolioRepository: Sendable {
    func listSnapshots() async throws -> [PortfolioSnapshot]
    func createSnapshot(_ snapshot: PortfolioSnapshot) async throws -> PortfolioSnapshot
    func updateSnapshot(_ snapshot: PortfolioSnapshot) async throws -> PortfolioSnapshot
    func deleteSnapshot(id: UUID) async throws
}
