import Foundation

struct PostcardLocation: Equatable {
    var country: String
    var province: String
    var detail: String

    var shortLabel: String {
        let unknown = NSLocalizedString("postcard_location_unknown", comment: "")
        let c = country.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = province.trimmingCharacters(in: .whitespacesAndNewlines)
        if c.isEmpty && p.isEmpty { return unknown }
        if c.isEmpty { return p }
        if p.isEmpty { return c }
        return "\(c), \(p)"
    }

    var fullLabel: String {
        let base = shortLabel
        let d = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let unknown = NSLocalizedString("postcard_location_unknown", comment: "")
        if d.isEmpty || base == unknown { return base }
        return "\(base) · \(d)"
    }
}

struct PostcardListing: Identifiable, Equatable {
    let id: String
    let title: String
    let priceHoney: Int
    let location: PostcardLocation
    let sellerName: String
    let stock: Int
    let imageUrl: String?
    let createdAt: Date
}

enum PostcardSortOrder: String, CaseIterable, Identifiable {
    case newest = "Newest"
    case lowestPrice = "Lowest Price"

    var id: String { rawValue }

    var localizedKey: String {
        switch self {
        case .newest: return "postcard_sort_newest"
        case .lowestPrice: return "postcard_sort_lowest_price"
        }
    }
}
