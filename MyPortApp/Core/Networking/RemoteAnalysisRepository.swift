import Foundation

private struct CreateUploadSessionRequest: Codable {
    let fileCount: Int
    let capturedAt: Date
}

private struct StartAnalysisRequest: Codable {
    let uploadSessionId: UUID
}

enum RemoteAnalysisRepositoryError: LocalizedError {
    case uploadTargetMismatch
    case invalidResponse
    case unexpectedStatusCode(Int)

    var errorDescription: String? {
        switch self {
        case .uploadTargetMismatch:
            return "업로드 세션과 선택한 이미지 수가 일치하지 않습니다."
        case .invalidResponse:
            return "분석 서버 응답을 해석할 수 없습니다."
        case .unexpectedStatusCode(let code):
            return "분석 서버 요청이 실패했습니다. HTTP \(code)"
        }
    }
}

actor RemoteAnalysisRepository: AnalysisRepository {
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

    func createUploadSession(fileCount: Int, capturedAt: Date) async throws -> UploadSession {
        let body = try encoder.encode(CreateUploadSessionRequest(fileCount: fileCount, capturedAt: capturedAt))
        let request = try makeJSONRequest(path: "v1/uploads", method: "POST", body: body)
        let data = try await performJSONRequest(request)
        return try decoder.decode(UploadSession.self, from: data)
    }

    func upload(_ uploads: [ScreenshotUpload], using session: UploadSession) async throws {
        guard uploads.count == session.files.count else {
            throw RemoteAnalysisRepositoryError.uploadTargetMismatch
        }

        for (upload, target) in zip(uploads, session.files) {
            var request = URLRequest(url: target.uploadURL)
            request.httpMethod = "PUT"
            request.setValue(upload.mimeType, forHTTPHeaderField: "Content-Type")
            let (_, response) = try await self.session.upload(for: request, from: upload.data)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw RemoteAnalysisRepositoryError.invalidResponse
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                throw RemoteAnalysisRepositoryError.unexpectedStatusCode(httpResponse.statusCode)
            }
        }
    }

    func startAnalysis(uploadSessionId: UUID) async throws -> AnalysisJob {
        let body = try encoder.encode(StartAnalysisRequest(uploadSessionId: uploadSessionId))
        let request = try makeJSONRequest(path: "v1/analysis-jobs", method: "POST", body: body)
        let data = try await performJSONRequest(request)
        return try decoder.decode(AnalysisJob.self, from: data)
    }

    func fetchAnalysisJob(jobId: UUID) async throws -> AnalysisJob {
        let request = try makeJSONRequest(path: "v1/analysis-jobs/\(jobId.uuidString)", method: "GET")
        let data = try await performJSONRequest(request)
        return try decoder.decode(AnalysisJob.self, from: data)
    }

    private func makeJSONRequest(path: String, method: String, body: Data? = nil) throws -> URLRequest {
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

    private func performJSONRequest(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RemoteAnalysisRepositoryError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw RemoteAnalysisRepositoryError.unexpectedStatusCode(httpResponse.statusCode)
        }

        return data
    }
}
