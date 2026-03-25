import SwiftUI

private struct DraftExchangeRate: Identifiable {
    var id: UUID
    var baseCurrency: String
    var rateToKRW: String

    init(
        id: UUID = UUID(),
        baseCurrency: String,
        rateToKRW: String
    ) {
        self.id = id
        self.baseCurrency = baseCurrency
        self.rateToKRW = rateToKRW
    }

    init(rate: ExchangeRateRecord) {
        self.id = rate.id
        self.baseCurrency = rate.baseCurrency
        self.rateToKRW = AppFormatters.fxRate(rate.rateToQuote)
    }

    var parsedRate: Double? {
        Double(rateToKRW.replacingOccurrences(of: ",", with: ""))
    }

    static var defaults: [DraftExchangeRate] {
        [
            DraftExchangeRate(baseCurrency: "USD", rateToKRW: "1472.30"),
            DraftExchangeRate(baseCurrency: "USDT", rateToKRW: "1471.80")
        ]
    }
}

private struct DraftHolding: Identifiable {
    var id: UUID
    var name: String = ""
    var symbol: String = ""
    var institution: String = ""
    var assetClass: AssetClass = .domesticStock
    var quantity: String = ""
    var marketValue: String = ""
    var currency: String = "KRW"
    var country: String = ""

    init(
        id: UUID = UUID(),
        name: String = "",
        symbol: String = "",
        institution: String = "",
        assetClass: AssetClass = .domesticStock,
        quantity: String = "",
        marketValue: String = "",
        currency: String = "KRW",
        country: String = ""
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.institution = institution
        self.assetClass = assetClass
        self.quantity = quantity
        self.marketValue = marketValue
        self.currency = currency
        self.country = country
    }

    init(holding: AssetPosition) {
        self.id = holding.id
        self.name = holding.name
        self.symbol = holding.symbol
        self.institution = holding.institution
        self.assetClass = holding.assetClass
        self.quantity = holding.quantity.map { AppFormatters.decimal($0, precision: 4) } ?? ""
        self.marketValue = holding.marketValue.map { AppFormatters.decimal($0, precision: holding.currency == "KRW" ? 0 : 2) } ?? ""
        self.currency = holding.currency
        self.country = holding.country
    }

    var parsedQuantity: Double? {
        let sanitized = quantity.replacingOccurrences(of: ",", with: "")
        return sanitized.isEmpty ? nil : Double(sanitized)
    }

    var parsedMarketValue: Double? {
        let sanitized = marketValue.replacingOccurrences(of: ",", with: "")
        return sanitized.isEmpty ? nil : Double(sanitized)
    }

    func makeModel() -> AssetPosition? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty == false, let parsedMarketValue else { return nil }

        return AssetPosition(
            id: id,
            name: trimmedName,
            symbol: symbol.trimmingCharacters(in: .whitespacesAndNewlines),
            institution: institution.trimmingCharacters(in: .whitespacesAndNewlines),
            assetClass: assetClass,
            quantity: parsedQuantity,
            marketValue: parsedMarketValue,
            currency: currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
            country: country.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

enum SnapshotEditorMode {
    case create
    case edit
}

struct SnapshotEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var portfolioStore: PortfolioStore

    private let mode: SnapshotEditorMode
    private let originalSnapshot: PortfolioSnapshot?
    private let titleOverride: String?

    @State private var title = ""
    @State private var capturedAt = Date()
    @State private var note = ""
    @State private var exchangeRates = DraftExchangeRate.defaults
    @State private var holdings = [DraftHolding()]
    @State private var isSubmitting = false

    init(
        snapshot: PortfolioSnapshot? = nil,
        mode: SnapshotEditorMode = .create,
        titleOverride: String? = nil
    ) {
        self.mode = mode
        self.originalSnapshot = snapshot
        self.titleOverride = titleOverride

        let customRates = snapshot?.exchangeRates
            .filter { $0.baseCurrency != "KRW" }
            .map(DraftExchangeRate.init(rate:)) ?? DraftExchangeRate.defaults
        let draftHoldings = snapshot?.holdings.map(DraftHolding.init(holding:)) ?? [DraftHolding()]

        _title = State(initialValue: snapshot?.title ?? "")
        _capturedAt = State(initialValue: snapshot?.capturedAt ?? Date())
        _note = State(initialValue: snapshot?.note ?? "")
        _exchangeRates = State(initialValue: customRates.isEmpty ? DraftExchangeRate.defaults : customRates)
        _holdings = State(initialValue: draftHoldings.isEmpty ? [DraftHolding()] : draftHoldings)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("기록 정보") {
                    TextField("스냅샷 제목", text: $title)
                    DatePicker("기록 시점", selection: $capturedAt)
                    TextField("메모", text: $note, axis: .vertical)
                }

                Section {
                    ForEach(exchangeRates.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("통화 코드", text: $exchangeRates[index].baseCurrency)
                                .textInputAutocapitalization(.characters)

                            TextField("1통화당 KRW 환율", text: $exchangeRates[index].rateToKRW)
                                .keyboardType(.decimalPad)

                            if exchangeRates.count > 1 {
                                Button("환율 행 삭제", role: .destructive) {
                                    exchangeRates.remove(at: index)
                                }
                                .font(.caption)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Button {
                        exchangeRates.append(DraftExchangeRate(baseCurrency: "", rateToKRW: ""))
                    } label: {
                        Label("환율 추가", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("환율")
                } footer: {
                    Text("기록 당시 환율을 서버에 함께 저장해 두면 통화별 자산을 원화 기준으로 다시 확인할 수 있습니다.")
                }

                Section("보유 자산") {
                    ForEach(holdings.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("자산명", text: $holdings[index].name)
                            TextField("심볼", text: $holdings[index].symbol)
                            TextField("기관명", text: $holdings[index].institution)

                            Picker("자산군", selection: $holdings[index].assetClass) {
                                ForEach(AssetClass.allCases.filter { $0 != .unknown }) { assetClass in
                                    Text(assetClass.displayName).tag(assetClass)
                                }
                            }

                            TextField("수량", text: $holdings[index].quantity)
                                .keyboardType(.decimalPad)

                            TextField("평가금액", text: $holdings[index].marketValue)
                                .keyboardType(.decimalPad)

                            TextField("통화", text: $holdings[index].currency)
                                .textInputAutocapitalization(.characters)

                            TextField("국가 코드", text: $holdings[index].country)
                                .textInputAutocapitalization(.characters)

                            if holdings.count > 1 {
                                Button("자산 행 삭제", role: .destructive) {
                                    holdings.remove(at: index)
                                }
                                .font(.caption)
                            }
                        }
                        .padding(.vertical, 6)
                    }

                    Button {
                        holdings.append(DraftHolding())
                    } label: {
                        Label("자산 추가", systemImage: "plus.circle.fill")
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(submitButtonTitle) {
                        Task {
                            await saveSnapshot()
                        }
                    }
                    .disabled(canSave == false || isSubmitting)
                }
            }
        }
    }

    private var canSave: Bool {
        holdings.contains { draft in
            draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false && draft.parsedMarketValue != nil
        }
    }

    private func saveSnapshot() async {
        isSubmitting = true
        defer { isSubmitting = false }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultKRWRate = ExchangeRateRecord(
            baseCurrency: "KRW",
            quoteCurrency: "KRW",
            rateToQuote: 1,
            source: "system",
            observedAt: capturedAt
        )

        let customRates = exchangeRates.compactMap { draft -> ExchangeRateRecord? in
            let currency = draft.baseCurrency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard currency.isEmpty == false, currency != "KRW", let rate = draft.parsedRate else { return nil }

            return ExchangeRateRecord(
                id: draft.id,
                baseCurrency: currency,
                quoteCurrency: "KRW",
                rateToQuote: rate,
                source: "manual",
                observedAt: capturedAt
            )
        }

        let snapshot = PortfolioSnapshot(
            id: originalSnapshot?.id ?? UUID(),
            title: trimmedTitle.isEmpty ? AppFormatters.date(capturedAt) : trimmedTitle,
            capturedAt: capturedAt,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: originalSnapshot?.createdAt ?? .now,
            baseCurrency: "KRW",
            holdings: holdings.compactMap { $0.makeModel() },
            exchangeRates: [defaultKRWRate] + customRates,
            lastSyncedAt: originalSnapshot?.lastSyncedAt
        )

        let didSave: Bool
        switch mode {
        case .create:
            didSave = await portfolioStore.createSnapshot(snapshot)
        case .edit:
            didSave = await portfolioStore.updateSnapshot(snapshot)
        }

        if didSave {
            dismiss()
        }
    }

    private var navigationTitle: String {
        if let titleOverride {
            return titleOverride
        }

        switch mode {
        case .create:
            return "새 스냅샷"
        case .edit:
            return "스냅샷 수정"
        }
    }

    private var submitButtonTitle: String {
        switch mode {
        case .create:
            return "저장"
        case .edit:
            return "수정 저장"
        }
    }
}
