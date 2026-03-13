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
struct PostcardLocation: Equatable, Hashable, Codable {
    /// Country name selected in the postcard form.
    var country: String
    /// Province/city text selected in the postcard form.
    var province: String
    /// Optional free-form location detail text.
    var detail: String

    /// Compact `country, province` label shown in list cards.
    var shortLabel: String {
        let unknown = NSLocalizedString("postcard_location_unknown", comment: "")
        let c = CountryLocalization.displayName(forStoredCountryValue: country)
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
struct PostcardListing: Identifiable, Equatable, Hashable, Codable {
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
    /// Optional uploaded thumbnail image URL string for browse cards.
    let thumbnailUrl: String?
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
enum PostcardOrderStatus: String, Codable {
    /// Legacy state where buyer order waited for seller accept/reject.
    case sellerConfirmPending = "SellerConfirmPending"
    /// Active pending state where seller should ship or decline.
    case awaitingShipping = "AwaitingShipping"
    /// Seller marked shipped and buyer can confirm receipt.
    case shipped = "Shipped"
    /// Buyer confirmed receipt; order is finished.
    case completed = "Completed"
    /// System auto-completed because buyer did not confirm before deadline.
    case completedAuto = "CompletedAuto"
    /// Seller rejected the order.
    case rejected = "Rejected"
    /// Legacy timeout from the previous seller-accept step.
    case expiredBySellerTimeout = "ExpiredBySellerTimeout"
    /// Seller accepted but did not ship before deadline.
    case failedSellerNoShip = "FailedSellerNoShip"
    /// Order was cancelled before completion.
    case cancelled = "Cancelled"

    /// Creates status from Firestore raw value, including legacy migration values.
    /// - Parameter rawValue: Persisted status string.
    /// - Returns: Mapped status if supported.
    static func from(rawValue: String) -> PostcardOrderStatus? {
        if let status = PostcardOrderStatus(rawValue: rawValue) {
            return status
        }

        // Legacy status mapping from old postcard flow.
        switch rawValue {
        case "AwaitingSellerSend":
            return .awaitingShipping
        case "InTransit", "AwaitingBuyerDecision":
            return .shipped
        default:
            return nil
        }
    }
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
    /// Current order status for seller action rendering.
    let status: PostcardOrderStatus
}

/// Latest order snapshot for current buyer and listing.
struct PostcardBuyerOrder: Identifiable, Equatable, Codable {
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

/// Latest completed-order rating task shown to either buyer or seller.
struct PostcardOrderRatingContext: Identifiable, Equatable, Codable {
    /// Uses the order document id so one rating prompt maps to one order.
    let id: String
    /// Related postcard listing id.
    let postcardId: String
    /// Current completed order status.
    let status: PostcardOrderStatus
    /// Counterparty display name shown in the rating dialog title.
    let counterpartName: String
    /// True when the buyer still needs to rate the seller for this order.
    let isBuyerRatingRequired: Bool
    /// True when the seller still needs to rate the buyer for this order.
    let isSellerRatingRequired: Bool
    /// True when the buyer permanently skipped seller rating for this order.
    let isBuyerRatingDismissed: Bool
    /// True when the seller permanently skipped buyer rating for this order.
    let isSellerRatingDismissed: Bool
    /// Timestamp when the order was completed.
    let completedAt: Date
}

/// Ordered postcard summary rendered in profile with latest active order status.
struct OrderedPostcardSummary: Identifiable, Equatable, Codable {
    /// Uses listing id so profile row navigation can open postcard detail directly.
    var id: String { listing.id }
    /// Related postcard listing snapshot.
    let listing: PostcardListing
    /// Latest buyer order status for the listing.
    let status: PostcardOrderStatus
}
