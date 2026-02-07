import Foundation

struct PostcardLocation: Equatable {
    var country: String
    var province: String
    var detail: String

    var shortLabel: String {
        let c = country.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = province.trimmingCharacters(in: .whitespacesAndNewlines)
        if c.isEmpty && p.isEmpty { return "Unknown" }
        if c.isEmpty { return p }
        if p.isEmpty { return c }
        return "\(c), \(p)"
    }

    var fullLabel: String {
        let base = shortLabel
        let d = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if d.isEmpty || base == "Unknown" { return base }
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
}
