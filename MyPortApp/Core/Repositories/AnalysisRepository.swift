import Foundation

protocol AnalysisRepository: Sendable {
    func createUploadSession(fileCount: Int, capturedAt: Date) async throws -> UploadSession
    func upload(_ uploads: [ScreenshotUpload], using session: UploadSession) async throws
    func startAnalysis(uploadSessionId: UUID) async throws -> AnalysisJob
    func fetchAnalysisJob(jobId: UUID) async throws -> AnalysisJob
}
