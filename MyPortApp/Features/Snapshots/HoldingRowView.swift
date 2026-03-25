import SwiftUI

struct HoldingRowView: View {
    let holding: AssetPosition
    let convertedValue: Double

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: holding.assetClass.iconName)
                .foregroundStyle(holding.assetClass.tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 6) {
                Text(holding.name)
                    .font(.headline)

                if holding.symbol.isEmpty == false || holding.institution.isEmpty == false {
                    Text([holding.symbol, holding.institution]
                        .filter { $0.isEmpty == false }
                        .joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let quantity = holding.quantity {
                    Text("수량 \(AppFormatters.decimal(quantity, precision: 4))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if holding.memo.isEmpty == false {
                    Text(holding.memo)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(AppFormatters.currency(holding.marketValue ?? 0, code: holding.currency))
                    .fontWeight(.semibold)

                Text(AppFormatters.currency(convertedValue, code: "KRW"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
