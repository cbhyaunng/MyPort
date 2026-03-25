import SwiftUI

enum AssetClass: String, Codable, CaseIterable, Identifiable, Sendable {
    case domesticStock
    case foreignStock
    case cashEquivalent
    case crypto
    case bond
    case unknown

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .domesticStock:
            return "국내주식"
        case .foreignStock:
            return "해외주식"
        case .cashEquivalent:
            return "현금성자산"
        case .crypto:
            return "코인"
        case .bond:
            return "채권"
        case .unknown:
            return "미분류"
        }
    }

    var iconName: String {
        switch self {
        case .domesticStock:
            return "building.columns.fill"
        case .foreignStock:
            return "globe.asia.australia.fill"
        case .cashEquivalent:
            return "banknote.fill"
        case .crypto:
            return "bitcoinsign.circle.fill"
        case .bond:
            return "doc.text.fill"
        case .unknown:
            return "questionmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .domesticStock:
            return .blue
        case .foreignStock:
            return .indigo
        case .cashEquivalent:
            return .green
        case .crypto:
            return .orange
        case .bond:
            return .teal
        case .unknown:
            return .gray
        }
    }
}
