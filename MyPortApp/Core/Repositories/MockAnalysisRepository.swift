import Foundation

actor MockAnalysisRepository: AnalysisRepository {
    private let state: MockServerState

    init(state: MockServerState = .shared) {
        self.state = state
    }

    func createUploadSession(fileCount: Int, capturedAt: Date) async throws -> UploadSession {
        try await Task.sleep(for: .milliseconds(120))
        return await state.createUploadSession(fileCount: fileCount, capturedAt: capturedAt)
    }

    func upload(_ uploads: [ScreenshotUpload], using session: UploadSession) async throws {
        try await Task.sleep(for: .milliseconds(150))
        await state.markUploads(uploadSessionId: session.uploadSessionId, uploadedCount: uploads.count)
    }

    func startAnalysis(uploadSessionId: UUID) async throws -> AnalysisJob {
        try await Task.sleep(for: .milliseconds(150))
        return await state.startAnalysis(uploadSessionId: uploadSessionId)
    }

    func fetchAnalysisJob(jobId: UUID) async throws -> AnalysisJob {
        try await Task.sleep(for: .milliseconds(350))
        return await state.fetchAnalysisJob(jobId: jobId)
    }
}
