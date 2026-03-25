import Foundation

@MainActor
final class AnalysisStore: ObservableObject {
    @Published var isWorking = false
    @Published var statusMessage: String?
    @Published var latestJob: AnalysisJob?

    private var repository: any AnalysisRepository
    private let portfolioStore: PortfolioStore

    init(bundle: RepositoryBundle, portfolioStore: PortfolioStore) {
        self.repository = bundle.analysisRepository
        self.portfolioStore = portfolioStore
    }

    func reconfigure(bundle: RepositoryBundle) {
        repository = bundle.analysisRepository
        statusMessage = nil
        latestJob = nil
    }

    func analyzeUploads(_ uploads: [ScreenshotUpload], capturedAt: Date) async -> PortfolioSnapshot? {
        isWorking = true
        defer { isWorking = false }

        do {
            statusMessage = "업로드 세션 생성 중..."
            let uploadSession = try await repository.createUploadSession(fileCount: uploads.count, capturedAt: capturedAt)

            statusMessage = "이미지 업로드 중..."
            try await repository.upload(uploads, using: uploadSession)

            statusMessage = "분석 작업 시작 중..."
            let job = try await repository.startAnalysis(uploadSessionId: uploadSession.uploadSessionId)
            latestJob = job

            statusMessage = "분석 결과 대기 중..."
            let completedJob = try await waitForCompletion(jobId: job.jobId)
            latestJob = completedJob

            if completedJob.status == .completed {
                statusMessage = "분석 완료. 스냅샷 목록을 새로고칩니다."
                await portfolioStore.refresh()
                if let snapshotId = completedJob.snapshotId {
                    statusMessage = "분석 완료. 검수 화면에서 내용을 확인해 주세요."
                    return portfolioStore.snapshot(id: snapshotId)
                }

                return nil
            }

            statusMessage = "분석 작업이 완료되지 않았습니다."
            return nil
        } catch {
            statusMessage = error.localizedDescription
            return nil
        }
    }

    private func waitForCompletion(jobId: UUID) async throws -> AnalysisJob {
        for _ in 0..<15 {
            let job = try await repository.fetchAnalysisJob(jobId: jobId)
            if job.status == .completed || job.status == .failed {
                return job
            }

            try await Task.sleep(for: .seconds(1))
        }

        return try await repository.fetchAnalysisJob(jobId: jobId)
    }
}
