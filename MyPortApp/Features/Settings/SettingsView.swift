import SwiftUI

struct SettingsView: View {
    @AppStorage("myport.lockEnabled") private var lockEnabled = true
    @AppStorage("myport.remoteAIEnabled") private var remoteAIEnabled = false
    @EnvironmentObject private var serverConfiguration: ServerConfigurationStore
    @EnvironmentObject private var portfolioStore: PortfolioStore
    @EnvironmentObject private var analysisStore: AnalysisStore
    @State private var isApplying = false
    @State private var isTestingConnection = false
    @State private var connectionStatusMessage: String?
    @State private var connectionCheckSucceeded = false

    var body: some View {
        NavigationStack {
            Form {
                Section("보안") {
                    Toggle("앱 잠금 사용", isOn: $lockEnabled)
                    LabeledContent("토큰 저장", value: "Keychain")
                }

                Section("서버 연결") {
                    Toggle("Mock 서버 사용", isOn: $serverConfiguration.useMockServer)

                    if serverConfiguration.useMockServer == false {
                        TextField("API Base URL", text: $serverConfiguration.baseURLString)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)

                        SecureField("Bearer Token", text: $serverConfiguration.bearerToken)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Button("로컬 서버 주소 채우기") {
                            serverConfiguration.baseURLString = "http://127.0.0.1:8787"
                        }

                        Button {
                            Task {
                                await testConnection()
                            }
                        } label: {
                            if isTestingConnection {
                                ProgressView()
                            } else {
                                Text("서버 연결 테스트")
                            }
                        }
                        .disabled(isTestingConnection)

                        if let connectionStatusMessage {
                            Text(connectionStatusMessage)
                                .font(.caption)
                                .foregroundStyle(connectionCheckSucceeded ? .green : .secondary)
                        }
                    }

                    Button {
                        Task {
                            isApplying = true
                            let bundle = RepositoryFactory.make(configuration: serverConfiguration)
                            portfolioStore.reconfigure(bundle: bundle)
                            analysisStore.reconfigure(bundle: bundle)
                            await portfolioStore.refresh()
                            isApplying = false
                        }
                    } label: {
                        if isApplying {
                            ProgressView()
                        } else {
                            Text("설정 반영 및 다시 연결")
                        }
                    }

                    LabeledContent("현재 저장소", value: portfolioStore.activeRepositoryLabel)
                }

                Section("분석 설정") {
                    Toggle("외부 AI 보정 허용", isOn: $remoteAIEnabled)
                    Text("기본 구조는 서버 저장을 기준으로 하며, 외부 AI 보정은 서버 측 OCR 후처리 단계에서 선택적으로 붙일 수 있도록 자리만 마련해 둔 상태입니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("앱 상태") {
                    Text("현재 골격은 서버 조회, 스냅샷 저장, 기록 당시 환율 보관, 통화별 원화 환산 총합 확인까지 포함합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Base URL 같은 비민감 설정은 UserDefaults에, 인증 토큰은 Keychain에 저장됩니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("시뮬레이터는 `127.0.0.1` 로컬 서버를 바로 볼 수 있지만, 실제 아이폰은 같은 Wi-Fi에서 Mac의 사설 IP 주소를 사용해야 합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("설정")
            .onChange(of: serverConfiguration.useMockServer) { _, isUsingMock in
                if isUsingMock {
                    connectionStatusMessage = "Mock 서버 모드에서는 연결 테스트가 필요하지 않습니다."
                    connectionCheckSucceeded = true
                } else {
                    connectionStatusMessage = nil
                    connectionCheckSucceeded = false
                }
            }
        }
    }

    @MainActor
    private func testConnection() async {
        guard let baseURL = serverConfiguration.normalizedBaseURL else {
            connectionStatusMessage = "먼저 API Base URL을 입력해 주세요."
            connectionCheckSucceeded = false
            return
        }

        isTestingConnection = true
        defer { isTestingConnection = false }

        do {
            let healthURL = baseURL.appending(path: "healthz")
            let (data, response) = try await URLSession.shared.data(from: healthURL)

            guard let httpResponse = response as? HTTPURLResponse else {
                connectionStatusMessage = "서버 응답을 확인할 수 없습니다."
                connectionCheckSucceeded = false
                return
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                connectionStatusMessage = "연결 테스트 실패 · HTTP \(httpResponse.statusCode)"
                connectionCheckSucceeded = false
                return
            }

            let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let serverBaseURL = payload?["baseURL"] as? String ?? baseURL.absoluteString
            connectionStatusMessage = "연결 성공 · \(serverBaseURL)"
            connectionCheckSucceeded = true
        } catch {
            connectionStatusMessage = "연결 실패 · \(error.localizedDescription)"
            connectionCheckSucceeded = false
        }
    }
}
