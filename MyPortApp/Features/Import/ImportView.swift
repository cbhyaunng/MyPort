import SwiftUI
import PhotosUI

struct ImportView: View {
    @EnvironmentObject private var analysisStore: AnalysisStore
    @EnvironmentObject private var portfolioStore: PortfolioStore

    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var capturedAt = Date()
    @State private var isPreparingUploads = false
    @State private var reviewSnapshot: PortfolioSnapshot?

    var body: some View {
        NavigationStack {
            Form {
                Section("스크린샷 선택") {
                    PhotosPicker(
                        selection: $selectedItems,
                        maxSelectionCount: 20,
                        matching: .images
                    ) {
                        Label("사진 선택", systemImage: "photo.on.rectangle.angled")
                    }

                    if selectedItems.isEmpty {
                        Text("선택된 이미지가 없습니다.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(selectedItems.count)장 선택됨")
                            .fontWeight(.semibold)
                    }

                    DatePicker("기록 시점", selection: $capturedAt)
                }

                Section("서버 분석") {
                    Button {
                        Task {
                            await startImport()
                        }
                    } label: {
                        if isPreparingUploads || analysisStore.isWorking {
                            ProgressView()
                        } else {
                            Label("업로드 후 분석 시작", systemImage: "icloud.and.arrow.up")
                        }
                    }
                    .disabled(selectedItems.isEmpty || isPreparingUploads || analysisStore.isWorking)

                    if let statusMessage = analysisStore.statusMessage {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let latestJob = analysisStore.latestJob {
                        LabeledContent("최근 작업 상태", value: latestJob.status.displayName)

                        if let snapshotId = latestJob.snapshotId {
                            Text("생성된 스냅샷 ID: \(snapshotId.uuidString)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            if let snapshot = portfolioStore.snapshots.first(where: { $0.id == snapshotId }) {
                                NavigationLink {
                                    SnapshotDetailView(snapshot: snapshot)
                                } label: {
                                    Label("생성된 스냅샷 보기", systemImage: "chart.pie.fill")
                                }

                                Button {
                                    reviewSnapshot = snapshot
                                } label: {
                                    Label("검수 및 수정", systemImage: "square.and.pencil")
                                }
                            }
                        }
                    }
                }

                Section("안내") {
                    Text("Mock 서버 모드에서는 선택한 이미지 수를 기준으로 분석 결과를 시뮬레이션합니다. 실제 서버 모드에서는 업로드 세션 생성, 파일 업로드, 분석 작업 조회 순서로 동작합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("실서버 모드에서는 설정 탭에서 Base URL을 입력하고 연결 테스트를 통과한 뒤 사용하는 흐름을 권장합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("업로드")
            .sheet(item: $reviewSnapshot) { snapshot in
                SnapshotEditorView(
                    snapshot: snapshot,
                    mode: .edit,
                    titleOverride: "검수 및 수정"
                )
            }
        }
    }

    private func startImport() async {
        isPreparingUploads = true
        defer { isPreparingUploads = false }

        let uploads = await buildUploads()
        guard uploads.isEmpty == false else {
            analysisStore.statusMessage = "이미지를 불러오지 못했습니다."
            return
        }

        if let snapshot = await analysisStore.analyzeUploads(uploads, capturedAt: capturedAt) {
            selectedItems = []
            reviewSnapshot = snapshot
        }
    }

    private func buildUploads() async -> [ScreenshotUpload] {
        var uploads: [ScreenshotUpload] = []

        for (index, item) in selectedItems.enumerated() {
            if let data = try? await item.loadTransferable(type: Data.self) {
                uploads.append(
                    ScreenshotUpload(
                        filename: "capture-\(index + 1).jpg",
                        mimeType: "image/jpeg",
                        data: data
                    )
                )
            }
        }

        return uploads
    }
}
