import Foundation

struct AssetPosition: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var symbol: String
    var institution: String
    var assetClass: AssetClass
    var quantity: Double?
    var unitPrice: Double?
    var marketValue: Double?
    var currency: String
    var country: String
    var memo: String

    init(
        id: UUID = UUID(),
        name: String,
        symbol: String = "",
        institution: String = "",
        assetClass: AssetClass,
        quantity: Double? = nil,
        unitPrice: Double? = nil,
        marketValue: Double? = nil,
        currency: String,
        country: String = "",
        memo: String = ""
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.institution = institution
        self.assetClass = assetClass
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.marketValue = marketValue
        self.currency = currency.uppercased()
        self.country = country
        self.memo = memo
    }
}
