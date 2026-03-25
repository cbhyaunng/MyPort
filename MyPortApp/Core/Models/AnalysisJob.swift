import Foundation

enum AnalysisJobStatus: String, Codable, Hashable, Sendable {
    case queued
    case processing
    case completed
    case failed

    var displayName: String {
        switch self {
        case .queued:
            return "대기 중"
        case .processing:
            return "분석 중"
        case .completed:
            return "완료"
        case .failed:
            return "실패"
        }
    }
}

struct AnalysisJob: Identifiable, Codable, Hashable, Sendable {
    var id: UUID { jobId }
    let jobId: UUID
    var status: AnalysisJobStatus
    var snapshotId: UUID?
}
