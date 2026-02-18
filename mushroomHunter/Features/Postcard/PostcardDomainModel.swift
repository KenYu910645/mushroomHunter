//
//  PostcardDomainModel.swift
//  mushroomHunter
//
//  Purpose:
//  - Declares postcard domain models and formatting utilities.
//
//  Defined in this file:
//  - Postcard listing/order/location value types and helpers.
//
import Foundation

/// Seller-provided location metadata for a postcard listing.
struct PostcardLocation: Equatable, Hashable {
    /// Country name selected in the postcard form.
    var country: String
    /// Province/city text selected in the postcard form.
    var province: String
    /// Optional free-form location detail text.
    var detail: String

    /// Compact `country, province` label shown in list cards.
    var shortLabel: String {
        let unknown = NSLocalizedString("postcard_location_unknown", comment: "")
        let c = country.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = province.trimmingCharacters(in: .whitespacesAndNewlines)
        if c.isEmpty && p.isEmpty { return unknown }
        if c.isEmpty { return p }
        if p.isEmpty { return c }
        return "\(c), \(p)"
    }

    /// Full location label including optional detail text.
    var fullLabel: String {
        let base = shortLabel
        let d = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let unknown = NSLocalizedString("postcard_location_unknown", comment: "")
        if d.isEmpty || base == unknown { return base }
        return "\(base) · \(d)"
    }
}

/// Marketplace listing owned by a seller.
struct PostcardListing: Identifiable, Equatable, Hashable {
    /// Firestore listing document id.
    let id: String
    /// Seller uid who created the listing.
    let sellerId: String
    /// Listing title shown in browse/detail screens.
    let title: String
    /// Listing price charged in honey.
    let priceHoney: Int
    /// Seller-provided listing location.
    let location: PostcardLocation
    /// Seller display name snapshot saved in listing.
    let sellerName: String
    /// Seller friend code snapshot saved in listing for detail display.
    let sellerFriendCode: String
    /// Remaining stock quantity.
    let stock: Int
    /// Optional uploaded image URL string.
    let imageUrl: String?
    /// Listing creation timestamp.
    let createdAt: Date
}

/// Sort options available in postcard browse view.
enum PostcardSortOrder: String, CaseIterable, Identifiable {
    /// Newest-first listing order.
    case newest = "Newest"
    /// Lowest-price-first listing order.
    case lowestPrice = "Lowest Price"

    /// Stable identifier for `Picker` conformance.
    var id: String { rawValue }

    /// Localized string key used by sort UI.
    var localizedKey: String {
        switch self {
        case .newest: return "postcard_sort_newest"
        case .lowestPrice: return "postcard_sort_lowest_price"
        }
    }
}

/// Lifecycle states for a postcard order.
enum PostcardOrderStatus: String {
    /// Buyer reserved stock and waits for seller shipment.
    case awaitingSellerSend = "AwaitingSellerSend"
    /// Seller marked shipped; buyer should wait for delivery.
    case inTransit = "InTransit"
    /// Buyer can confirm receipt or mark not received.
    case awaitingBuyerDecision = "AwaitingBuyerDecision"
    /// Buyer confirmed receipt; order is finished.
    case completed = "Completed"
    /// Order was cancelled before completion.
    case cancelled = "Cancelled"
}

/// Buyer info shown to seller in shipping queue.
struct PostcardShippingRecipient: Identifiable, Equatable {
    /// Order id represented by this recipient row.
    let id: String
    /// Buyer uid.
    let buyerId: String
    /// Buyer display name.
    let buyerName: String
    /// Buyer friend code used for shipment handoff.
    let buyerFriendCode: String
}

/// Latest order snapshot for current buyer and listing.
struct PostcardBuyerOrder: Identifiable, Equatable {
    /// Firestore order document id.
    let id: String
    /// Related postcard listing id.
    let postcardId: String
    /// Current order status.
    let status: PostcardOrderStatus
    /// Honey amount held when order was created.
    let holdHoney: Int
    /// Order creation timestamp.
    let createdAt: Date
}
