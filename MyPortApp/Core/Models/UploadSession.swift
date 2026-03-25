import Foundation

struct UploadTarget: Identifiable, Codable, Hashable, Sendable {
    var id: UUID { uploadId }
    let uploadId: UUID
    let uploadURL: URL
}

struct UploadSession: Codable, Hashable, Sendable {
    let uploadSessionId: UUID
    let files: [UploadTarget]
}
