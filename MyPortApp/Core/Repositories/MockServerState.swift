import Foundation

actor MockServerState {
    static let shared = MockServerState()

    private struct MockUploadSessionRecord {
        let fileCount: Int
        let capturedAt: Date
        var uploadedCount: Int
    }

    private struct MockAnalysisJobRecord {
        var job: AnalysisJob
        let uploadSessionId: UUID
    }

    private var snapshots: [PortfolioSnapshot]
    private var uploadSessions: [UUID: MockUploadSessionRecord] = [:]
    private var analysisJobs: [UUID: MockAnalysisJobRecord] = [:]

    private init(seedSnapshots: [PortfolioSnapshot] = SamplePortfolioFixtures.makeSnapshots()) {
        self.snapshots = seedSnapshots.sorted(by: { $0.capturedAt > $1.capturedAt })
    }

    func listSnapshots() -> [PortfolioSnapshot] {
        snapshots.sorted(by: { $0.capturedAt > $1.capturedAt })
    }

    func saveSnapshot(_ snapshot: PortfolioSnapshot) -> PortfolioSnapshot {
        var stored = snapshot
        stored.lastSyncedAt = .now
        snapshots.append(stored)
        snapshots.sort(by: { $0.capturedAt > $1.capturedAt })
        return stored
    }

    func updateSnapshot(_ snapshot: PortfolioSnapshot) -> PortfolioSnapshot {
        var stored = snapshot
        stored.lastSyncedAt = .now
        snapshots.removeAll { $0.id == stored.id }
        snapshots.append(stored)
        snapshots.sort(by: { $0.capturedAt > $1.capturedAt })
        return stored
    }

    func deleteSnapshot(id: UUID) {
        snapshots.removeAll { $0.id == id }
    }

    func createUploadSession(fileCount: Int, capturedAt: Date) -> UploadSession {
        let sessionId = UUID()
        uploadSessions[sessionId] = MockUploadSessionRecord(
            fileCount: fileCount,
            capturedAt: capturedAt,
            uploadedCount: 0
        )

        let targets = (0..<fileCount).map { _ in
            UploadTarget(
                uploadId: UUID(),
                uploadURL: URL(string: "https://mock.myport.local/upload/\(UUID().uuidString)")!
            )
        }

        return UploadSession(uploadSessionId: sessionId, files: targets)
    }

    func markUploads(uploadSessionId: UUID, uploadedCount: Int) {
        guard var record = uploadSessions[uploadSessionId] else { return }
        record.uploadedCount = uploadedCount
        uploadSessions[uploadSessionId] = record
    }

    func startAnalysis(uploadSessionId: UUID) -> AnalysisJob {
        let job = AnalysisJob(jobId: UUID(), status: .processing, snapshotId: nil)
        analysisJobs[job.jobId] = MockAnalysisJobRecord(job: job, uploadSessionId: uploadSessionId)
        return job
    }

    func fetchAnalysisJob(jobId: UUID) -> AnalysisJob {
        guard var record = analysisJobs[jobId] else {
            return AnalysisJob(jobId: jobId, status: .failed, snapshotId: nil)
        }

        if record.job.status != .completed {
            let snapshot = buildAnalysisSnapshot(for: record.uploadSessionId)
            let stored = saveSnapshot(snapshot)
            record.job.status = .completed
            record.job.snapshotId = stored.id
            analysisJobs[jobId] = record
        }

        return record.job
    }

    private func buildAnalysisSnapshot(for uploadSessionId: UUID) -> PortfolioSnapshot {
        let record = uploadSessions[uploadSessionId]
        let capturedAt = record?.capturedAt ?? .now
        let fileCount = record?.fileCount ?? 0

        let baseHoldings = SamplePortfolioFixtures.makeSnapshots().first?.holdings ?? []
        let baseRates = SamplePortfolioFixtures.makeSnapshots().first?.exchangeRates ?? []

        return PortfolioSnapshot(
            title: "스크린샷 분석 \(AppFormatters.date(capturedAt))",
            capturedAt: capturedAt,
            note: "\(fileCount)장 스크린샷을 mock 서버에서 분석한 결과",
            baseCurrency: "KRW",
            holdings: baseHoldings,
            exchangeRates: baseRates,
            lastSyncedAt: .now
        )
    }
}
