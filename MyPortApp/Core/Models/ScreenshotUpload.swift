import Foundation

struct ScreenshotUpload: Identifiable, Hashable, Sendable {
    let id: UUID
    let filename: String
    let mimeType: String
    let data: Data

    init(
        id: UUID = UUID(),
        filename: String,
        mimeType: String,
        data: Data
    ) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
    }
}
