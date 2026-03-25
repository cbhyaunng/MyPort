import Foundation

private struct SnapshotListResponse: Codable {
    let items: [PortfolioSnapshot]
}

enum RemoteRepositoryError: LocalizedError {
    case invalidResponse
    case unexpectedStatusCode(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "서버 응답을 해석할 수 없습니다."
        case .unexpectedStatusCode(let code):
            return "서버 요청이 실패했습니다. HTTP \(code)"
        }
    }
}

actor RemotePortfolioRepository: PortfolioRepository {
    private let baseURL: URL
    private let bearerToken: String
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        baseURL: URL,
        bearerToken: String,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.bearerToken = bearerToken
        self.session = session

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func listSnapshots() async throws -> [PortfolioSnapshot] {
        let request = try makeRequest(path: "v1/snapshots", method: "GET")
        let data = try await perform(request)

        if data.isEmpty {
            return []
        }

        if let wrapped = try? decoder.decode(SnapshotListResponse.self, from: data) {
            return wrapped.items.sorted(by: { $0.capturedAt > $1.capturedAt })
        }

        let snapshots = try decoder.decode([PortfolioSnapshot].self, from: data)
        return snapshots.sorted(by: { $0.capturedAt > $1.capturedAt })
    }

    func createSnapshot(_ snapshot: PortfolioSnapshot) async throws -> PortfolioSnapshot {
        let body = try encoder.encode(snapshot)
        let request = try makeRequest(path: "v1/snapshots", method: "POST", body: body)
        let data = try await perform(request)

        if data.isEmpty {
            return snapshot
        }

        return try decoder.decode(PortfolioSnapshot.self, from: data)
    }

    func updateSnapshot(_ snapshot: PortfolioSnapshot) async throws -> PortfolioSnapshot {
        let body = try encoder.encode(snapshot)
        let request = try makeRequest(path: "v1/snapshots/\(snapshot.id.uuidString)", method: "PUT", body: body)
        let data = try await perform(request)

        if data.isEmpty {
            return snapshot
        }

        return try decoder.decode(PortfolioSnapshot.self, from: data)
    }

    func deleteSnapshot(id: UUID) async throws {
        let request = try makeRequest(path: "v1/snapshots/\(id.uuidString)", method: "DELETE")
        _ = try await perform(request)
    }

    private func makeRequest(path: String, method: String, body: Data? = nil) throws -> URLRequest {
        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if bearerToken.isEmpty == false {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = body
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RemoteRepositoryError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw RemoteRepositoryError.unexpectedStatusCode(httpResponse.statusCode)
        }

        return data
    }
}
