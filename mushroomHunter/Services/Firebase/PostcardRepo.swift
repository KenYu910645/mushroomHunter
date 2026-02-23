//
//  PostcardRepo.swift
//  mushroomHunter
//
//  Purpose:
//  - Repository for postcard browse/listing/order lifecycle flows.
//
//  Related flow:
//  - Postcard tab browse/search, seller create/edit/delete, buyer purchase, seller ship,
//  - buyer receive/confirm, profile-owned postcard queries.
//
//  Field access legend:
//  [R] Represent Read
//  [X] Represent dont care
//  [W] Represent write
//
//  Postcard listing document (`postcards/{postcardId}`):
//  [R] - `postcardId`: Reads document id for model identity and navigation.
//  [W] - `title`: Writes on create/edit; reads for listing/buy payloads.
//  [W] - `priceHoney`: Writes on create/edit; reads for purchase validation.
//  [W] - `sellerId`: Writes on create; reads for ownership/forbidden checks.
//  [W] - `sellerName`: Writes on create and refreshes on edit; reads for UI/order payload.
//  [W] - `sellerFriendCode`: Writes on create/edit and reads for detail display to avoid extra user reads.
//  [W] - `sellerFcmToken`: Writes on create/edit and reads for order push token snapshot.
//  [W] - `stock`: Writes on create/edit and decrements/increments during order lifecycle.
//  [W] - `imageUrl`: Writes on create/edit; reads for display/order payload.
//  [W] - `thumbnailUrl`: Writes on create/edit; reads for browse thumbnail payload.
//  [W] - `location`: Writes nested location on create/edit; reads for display/order payload.
//  [W] - `searchTokens`: Writes index tokens on create/edit; reads for token-based search query.
//  [W] - `createdAt`: Writes create timestamp; reads for ordering recent/my listings.
//  [W] - `updatedAt`: Writes update timestamp on every listing mutation.
//
//  Postcard order document (`postcardOrders/{orderId}`):
//  [R] - `orderId`: Reads document id for order tracking.
//  [W] - `postcardId`: Writes linked listing id; reads for ordered-postcard lookup.
//  [W] - `postcardTitle`: Writes title snapshot at buy time.
//  [W] - `postcardImageUrl`: Writes image URL snapshot at buy time.
//  [W] - `location`: Writes location snapshot at buy time.
//  [W] - `status`: Writes order state transitions and reads for filtering/validation.
//  [W] - `buyerId`: Writes buyer id and reads for profile/order authorization filters.
//  [W] - `buyerName`: Writes buyer name snapshot.
//  [W] - `buyerFriendCode`: Writes buyer friend code snapshot for seller shipping list.
//  [W] - `buyerFcmToken`: Writes buyer push token snapshot from buyer profile.
//  [W] - `sellerId`: Writes seller id and reads for seller authorization filters.
//  [W] - `sellerName`: Writes seller name snapshot.
//  [W] - `sellerFcmToken`: Writes seller push token snapshot from listing.
//  [W] - `priceHoney`: Writes transaction price snapshot.
//  [W] - `holdHoney`: Writes escrow/hold value and releases on completion/cancel paths.
//  [W] - `sellerShippingDeadlineAt`: Writes seller shipping deadline from order creation.
//  [W] - `buyerReminderAt`: Writes buyer reminder deadline.
//  [W] - `buyerConfirmDeadlineAt`: Writes buyer auto-complete deadline.
//  [W] - `trackingCode`: Writes shipment tracking code on seller ship flow.
//  [W] - `createdAt`: Writes order creation timestamp and reads for profile ordering.
//  [W] - `updatedAt`: Writes update timestamp on every order mutation.
//
//  User wallet/profile document (`users/{uid}`):
//  [R] - `friendCode`: Reads for order buyer snapshot and shipping legacy fallback.
//  [W] - `honey`: Reads/writes wallet balance during buy/settlement flows.
//  [R] - `displayName`: Reads buyer/seller display snapshots for orders.
//  [W] - `updatedAt`: Writes timestamp when wallet is mutated by order transactions.
//
import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

enum PostcardRepoError: LocalizedError {
    case notSignedIn
    case listingNotFound
    case invalidListing
    case outOfStock
    case notEnoughHoney
    case cannotBuyOwnListing
    case activeOrderExists
    case forbidden
    case invalidOrderState

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Please sign in first."
        case .listingNotFound: return "Postcard listing not found."
        case .invalidListing: return "Postcard listing is invalid."
        case .outOfStock: return "This postcard is out of stock."
        case .notEnoughHoney: return "Not enough honey."
        case .cannotBuyOwnListing: return "You cannot buy your own postcard."
        case .activeOrderExists: return "You already have an active order for this postcard."
        case .forbidden: return "You don't have access to this action."
        case .invalidOrderState: return "Order is not in a shippable state."
        }
    }
}

final class FbPostcardRepo {
    /// Cursor wrapper for browse pagination.
    struct ListingPageCursor {
        /// Firestore document used as cursor anchor.
        let snapshot: QueryDocumentSnapshot
    }

    /// Paged listing result used by browse/search.
    struct ListingPage {
        /// Listings decoded from the current page.
        let listings: [PostcardListing]
        /// Cursor for loading the next page; `nil` when exhausted.
        let nextCursor: ListingPageCursor?
        /// Indicates whether backend likely has another page.
        let isHasMore: Bool
    }

    private let db = Firestore.firestore()
    private let sellerShippingDeadlineHours = AppConfig.Postcard.sellerShippingDeadlineHours
    private let buyerReceiveReminderHours = AppConfig.Postcard.buyerReceiveReminderHours
    private let buyerConfirmDeadlineHours = AppConfig.Postcard.buyerConfirmDeadlineHours

    func fetchRecent(limit: Int = AppConfig.Postcard.browseListFetchLimit) async throws -> [PostcardListing] { // Handles fetchRecent flow.
        let page = try await fetchRecentPage(limit: limit)
        return page.listings
    }

    func fetchMyListings(userId: String, limit: Int = AppConfig.Postcard.profileListFetchLimit) async throws -> [PostcardListing] { // Handles fetchMyListings flow.
        let q = db.collection("postcards")
            .whereField("sellerId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)

        let snap: QuerySnapshot
        do {
            snap = try await q.getDocuments(source: .server)
        } catch {
            snap = try await q.getDocuments(source: .default)
        }
        return snap.documents.map(decodeListing)
    }

    /// Loads postcard listing ids that currently have unprocessed seller orders.
    /// - Parameters:
    ///   - userId: Seller uid for the current profile.
    ///   - limit: Max order docs to scan for pending queue status.
    /// - Returns: Set of postcard ids that should be marked as order-received in profile.
    func fetchSellerPendingOrderPostcardIds(
        userId: String,
        limit: Int = AppConfig.Postcard.profileListFetchLimit * 5
    ) async throws -> Set<String> { // Handles fetchSellerPendingOrderPostcardIds flow.
        let pendingCountByPostcardId = try await fetchSellerPendingOrderCountsByPostcardId(
            userId: userId,
            limit: limit
        )
        return Set(pendingCountByPostcardId.keys)
    }

    /// Loads pending seller-order counts grouped by postcard listing id.
    /// - Parameters:
    ///   - userId: Seller uid for the current profile.
    ///   - limit: Max order docs to scan for pending queue status.
    /// - Returns: Dictionary keyed by postcard id with pending seller-order counts.
    func fetchSellerPendingOrderCountsByPostcardId(
        userId: String,
        limit: Int = 250
    ) async throws -> [String: Int] {
        let pendingStatuses = [
            PostcardOrderStatus.sellerConfirmPending.rawValue,
            PostcardOrderStatus.awaitingShipping.rawValue,
            "AwaitingSellerSend"
        ]
        let query = db.collection("postcardOrders")
            .whereField("sellerId", isEqualTo: userId)
            .whereField("status", in: pendingStatuses)
            .limit(to: limit)

        let docs = try await fetchDocuments(query: query)
        return docs.reduce(into: [String: Int]()) { partial, doc in
            let postcardId = (doc.data()["postcardId"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard postcardId.isEmpty == false else { return }
            partial[postcardId, default: 0] += 1
        }
    }

    /// Counts buyer orders that are waiting for buyer receipt confirmation.
    /// - Parameters:
    ///   - userId: Buyer uid for the current profile.
    ///   - limit: Max active order docs to scan for buyer-side receive actions.
    /// - Returns: Number of orders currently waiting buyer confirmation.
    func fetchBuyerPendingReceiveCount(
        userId: String,
        limit: Int = 250
    ) async throws -> Int {
        let waitingStatuses = [
            PostcardOrderStatus.shipped.rawValue,
            "InTransit",
            "AwaitingBuyerDecision"
        ]
        let query = db.collection("postcardOrders")
            .whereField("buyerId", isEqualTo: userId)
            .whereField("status", in: waitingStatuses)
            .limit(to: limit)
        return try await fetchDocuments(query: query).count
    }

    func fetchMyOrderedPostcards(userId: String, limit: Int = AppConfig.Postcard.profileListFetchLimit) async throws -> [OrderedPostcardSummary] { // Handles fetchMyOrderedPostcards flow.
        let activeStatuses = [
            PostcardOrderStatus.awaitingShipping.rawValue,
            PostcardOrderStatus.shipped.rawValue,
            PostcardOrderStatus.sellerConfirmPending.rawValue,
            "AwaitingSellerSend",
            "InTransit",
            "AwaitingBuyerDecision"
        ]
        let query = db.collection("postcardOrders")
            .whereField("buyerId", isEqualTo: userId)
            .whereField("status", in: activeStatuses)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
        let orderDocs = try await fetchDocuments(query: query)

        let orderedPostcardInfos = orderDocs
            .compactMap { doc -> (postcardId: String, status: PostcardOrderStatus)? in
                let id = (doc.data()["postcardId"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let statusRaw = (doc.data()["status"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard id.isEmpty == false,
                    let status = PostcardOrderStatus.from(rawValue: statusRaw) else { return nil }
                return (postcardId: id, status: status)
            }
        if orderedPostcardInfos.isEmpty { return [] }

        let uniqueIds = Array(Set(orderedPostcardInfos.map { $0.postcardId }))
        var listingById: [String: PostcardListing] = [:]

        for chunk in uniqueIds.chunked(into: 10) {
            let listingSnap: QuerySnapshot
            let query = db.collection("postcards").whereField(FieldPath.documentID(), in: chunk)
            do {
                listingSnap = try await query.getDocuments(source: .server)
            } catch {
                listingSnap = try await query.getDocuments(source: .default)
            }
            for doc in listingSnap.documents {
                listingById[doc.documentID] = decodeListing(doc)
            }
        }

        return orderedPostcardInfos.compactMap { postcardInfo in
            guard let listing = listingById[postcardInfo.postcardId] else { return nil }
            return OrderedPostcardSummary(listing: listing, status: postcardInfo.status)
        }
    }

    func searchByToken(_ token: String, limit: Int = AppConfig.Postcard.browseListFetchLimit) async throws -> [PostcardListing] { // Handles searchByToken flow.
        let page = try await searchByTokenPage(token, limit: limit)
        return page.listings
    }

    func fetchRecentPage(
        limit: Int = AppConfig.Postcard.browseListFetchLimit,
        cursor: ListingPageCursor? = nil
    ) async throws -> ListingPage { // Handles paged recent fetch flow.
        var q: Query = db.collection("postcards")
            .order(by: "createdAt", descending: true)
            .limit(to: limit)

        if let cursor {
            q = q.start(afterDocument: cursor.snapshot)
        }

        let docs = try await fetchDocuments(query: q)
        let nextCursor = docs.last.map { ListingPageCursor(snapshot: $0) }
        let isHasMore = docs.count >= limit
        return ListingPage(
            listings: docs.map(decodeListing),
            nextCursor: nextCursor,
            isHasMore: isHasMore
        )
    }

    func searchByTokenPage(
        _ token: String,
        limit: Int = AppConfig.Postcard.browseListFetchLimit,
        cursor: ListingPageCursor? = nil
    ) async throws -> ListingPage { // Handles paged token search flow.
        let q = db.collection("postcards")
            .whereField("searchTokens", arrayContains: token)
            .order(by: "createdAt", descending: true)
        var pagedQuery: Query = q.limit(to: limit)
        if let cursor {
            pagedQuery = pagedQuery.start(afterDocument: cursor.snapshot)
        }
        let docs = try await fetchDocuments(query: pagedQuery)
        let nextCursor = docs.last.map { ListingPageCursor(snapshot: $0) }
        let isHasMore = docs.count >= limit
        return ListingPage(
            listings: docs.map(decodeListing),
            nextCursor: nextCursor,
            isHasMore: isHasMore
        )
    }

    func fetchPostcard(postcardId: String) async throws -> PostcardListing? { // Handles fetchPostcard flow.
        let ref = db.collection("postcards").document(postcardId)
        let snap: DocumentSnapshot
        do {
            snap = try await ref.getDocument(source: .server)
        } catch {
            snap = try await ref.getDocument(source: .default)
        }

        guard let data = snap.data() else { return nil }
        return decodeListing(id: snap.documentID, data: data)
    }

    func createPostcard(
        title: String,
        priceHoney: Int,
        location: PostcardLocation,
        stock: Int,
        sellerId: String,
        sellerName: String,
        sellerFriendCode: String,
        sellerFcmToken: String,
        imageUrl: String,
        thumbnailUrl: String
    ) async throws {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSellerId = sellerId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSeller = sellerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSellerFriendCode = sellerFriendCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSellerFcmToken = sellerFcmToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanThumbnailUrl = thumbnailUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCountry = location.country.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanProvince = location.province.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDetail = location.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = SearchTokenBuilder.indexTokens(
            from: [cleanTitle, cleanSeller, cleanCountry, cleanProvince, cleanDetail]
        )

        try await db.collection("postcards").addDocument(data: [
            "title": cleanTitle,
            "priceHoney": priceHoney,
            "sellerId": cleanSellerId,
            "sellerName": cleanSeller,
            "sellerFriendCode": cleanSellerFriendCode,
            "sellerFcmToken": cleanSellerFcmToken,
            "stock": stock,
            "imageUrl": imageUrl,
            "thumbnailUrl": cleanThumbnailUrl,
            "location": [
                "country": cleanCountry,
                "province": cleanProvince,
                "detail": cleanDetail
            ],
            "searchTokens": tokens,
            "createdAt": Timestamp(date: Date()),
            "updatedAt": Timestamp(date: Date())
        ])
    }

    func updatePostcard(
        postcardId: String,
        title: String,
        priceHoney: Int,
        location: PostcardLocation,
        stock: Int,
        sellerName: String,
        sellerFriendCode: String,
        sellerFcmToken: String,
        imageUrl: String? = nil,
        thumbnailUrl: String? = nil
    ) async throws {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSeller = sellerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSellerFriendCode = sellerFriendCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSellerFcmToken = sellerFcmToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCountry = location.country.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanProvince = location.province.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDetail = location.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = SearchTokenBuilder.indexTokens(
            from: [cleanTitle, cleanSeller, cleanCountry, cleanProvince, cleanDetail]
        )

        var payload: [String: Any] = [
            "title": cleanTitle,
            "priceHoney": priceHoney,
            "sellerName": cleanSeller,
            "sellerFriendCode": cleanSellerFriendCode,
            "sellerFcmToken": cleanSellerFcmToken,
            "stock": stock,
            "location": [
                "country": cleanCountry,
                "province": cleanProvince,
                "detail": cleanDetail
            ],
            "searchTokens": tokens,
            "updatedAt": Timestamp(date: Date())
        ]
        if let imageUrl {
            payload["imageUrl"] = imageUrl
        }
        if let thumbnailUrl {
            payload["thumbnailUrl"] = thumbnailUrl
        }

        try await db.collection("postcards").document(postcardId).setData(payload, merge: true)
    }

    func deletePostcard(postcardId: String) async throws { // Handles deletePostcard flow.
        let ref = db.collection("postcards").document(postcardId)
        let snap = try await ref.getDocument()
        let fullImageUrl = snap.data()?["imageUrl"] as? String
        let thumbnailImageUrl = snap.data()?["thumbnailUrl"] as? String

        try await ref.delete()
        await deleteStorageImage(urlString: fullImageUrl)
        await deleteStorageImage(urlString: thumbnailImageUrl)
    }

    @discardableResult
    func buyPostcard(postcardId: String) async throws -> String { // Handles buyPostcard flow.
        guard let buyerId = Auth.auth().currentUser?.uid else {
            throw PostcardRepoError.notSignedIn
        }
        let activeStatuses = [
            PostcardOrderStatus.sellerConfirmPending.rawValue,
            PostcardOrderStatus.awaitingShipping.rawValue,
            PostcardOrderStatus.shipped.rawValue,
            "AwaitingSellerSend",
            "InTransit",
            "AwaitingBuyerDecision"
        ]
        let activeOrderQuery = db.collection("postcardOrders")
            .whereField("buyerId", isEqualTo: buyerId)
            .whereField("postcardId", isEqualTo: postcardId)
            .whereField("status", in: activeStatuses)
            .limit(to: 1)
        let existingOrderDocs = try await fetchDocuments(query: activeOrderQuery)
        if existingOrderDocs.isEmpty == false {
            throw PostcardRepoError.activeOrderExists
        }

        let orderRef = db.collection("postcardOrders").document()
        let postcardRef = db.collection("postcards").document(postcardId)
        let buyerRef = db.collection("users").document(buyerId)

        let nowDate = Date()
        let now = Timestamp(date: nowDate)
        let sellerShippingDeadlineAt = Timestamp(
            date: nowDate.addingTimeInterval(TimeInterval(sellerShippingDeadlineHours * 3600))
        )

        _ = try await db.runTransaction { tx, errorPointer in
            let postcardSnap: DocumentSnapshot
            let buyerSnap: DocumentSnapshot
            do {
                postcardSnap = try tx.getDocument(postcardRef)
                buyerSnap = try tx.getDocument(buyerRef)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }

            guard let postcard = postcardSnap.data() else {
                errorPointer?.pointee = self.makeError(PostcardRepoError.listingNotFound)
                return nil
            }

            let stock = postcard["stock"] as? Int ?? 0
            let priceHoney = postcard["priceHoney"] as? Int ?? 0
            let sellerId = postcard["sellerId"] as? String ?? ""
            let sellerName = postcard["sellerName"] as? String ?? "Unknown"
            let sellerFcmToken = postcard["sellerFcmToken"] as? String ?? ""
            let title = postcard["title"] as? String ?? "Untitled"

            guard stock > 0 else {
                errorPointer?.pointee = self.makeError(PostcardRepoError.outOfStock)
                return nil
            }
            guard priceHoney > 0, !sellerId.isEmpty else {
                errorPointer?.pointee = self.makeError(PostcardRepoError.invalidListing)
                return nil
            }
            guard sellerId != buyerId else {
                errorPointer?.pointee = self.makeError(PostcardRepoError.cannotBuyOwnListing)
                return nil
            }

            let buyerHoney = buyerSnap.data()?["honey"] as? Int ?? 0
            guard buyerHoney >= priceHoney else {
                errorPointer?.pointee = self.makeError(PostcardRepoError.notEnoughHoney)
                return nil
            }

            tx.updateData([
                "stock": stock - 1,
                "updatedAt": now
            ], forDocument: postcardRef)

            tx.setData([
                "honey": buyerHoney - priceHoney,
                "updatedAt": now
            ], forDocument: buyerRef, merge: true)

            let location = postcard["location"] as? [String: Any] ?? [:]
            let imageUrl = postcard["imageUrl"] as? String ?? ""
            let buyerName = buyerSnap.data()?["displayName"] as? String ?? "Unknown"
            let buyerFriendCode = buyerSnap.data()?["friendCode"] as? String ?? ""
            let buyerFcmToken = buyerSnap.data()?["fcmToken"] as? String ?? ""

            tx.setData([
                "postcardId": postcardId,
                "postcardTitle": title,
                "postcardImageUrl": imageUrl,
                "location": location,
                "status": PostcardOrderStatus.awaitingShipping.rawValue,
                "buyerId": buyerId,
                "buyerName": buyerName,
                "buyerFriendCode": buyerFriendCode,
                "buyerFcmToken": buyerFcmToken,
                "sellerId": sellerId,
                "sellerName": sellerName,
                "sellerFcmToken": sellerFcmToken,
                "priceHoney": priceHoney,
                "holdHoney": priceHoney,
                "sellerShippingDeadlineAt": sellerShippingDeadlineAt,
                "buyerReminderAt": NSNull(),
                "buyerConfirmDeadlineAt": NSNull(),
                "timeouts": [
                    "sellerShippingDeadlineHours": self.sellerShippingDeadlineHours,
                    "buyerReceiveReminderHours": self.buyerReceiveReminderHours,
                    "buyerConfirmDeadlineHours": self.buyerConfirmDeadlineHours
                ],
                "createdAt": now,
                "updatedAt": now
            ], forDocument: orderRef)

            return nil
        }

        return orderRef.documentID
    }

    func fetchShippingRecipients(postcardId: String) async throws -> [PostcardShippingRecipient] { // Handles fetchShippingRecipients flow.
        guard let sellerId = Auth.auth().currentUser?.uid else {
            throw PostcardRepoError.notSignedIn
        }

        let pendingStatuses = [
            PostcardOrderStatus.awaitingShipping.rawValue,
            PostcardOrderStatus.sellerConfirmPending.rawValue,
            "AwaitingSellerSend"
        ]
        let query = db.collection("postcardOrders")
            .whereField("postcardId", isEqualTo: postcardId)
            .whereField("sellerId", isEqualTo: sellerId)
            .whereField("status", in: pendingStatuses)

        let candidates = try await fetchDocuments(query: query).map { doc in
            (doc.documentID, doc.data())
        }

        if candidates.isEmpty { return [] }

        let buyerIds = Array(Set(candidates.compactMap { $0.1["buyerId"] as? String }).filter { !$0.isEmpty })
        var buyerFriendCodes: [String: String] = [:]
        let isAllFriendCodesCached = candidates.allSatisfy { candidate in
            let friendCode = (candidate.1["buyerFriendCode"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return !friendCode.isEmpty
        }

        if !buyerIds.isEmpty && !isAllFriendCodesCached {
            // Firestore "in" supports up to 10 IDs per query.
            for chunk in buyerIds.chunked(into: 10) {
                let usersSnap = try await db.collection("users")
                    .whereField(FieldPath.documentID(), in: chunk)
                    .getDocuments(source: .server)
                for userDoc in usersSnap.documents {
                    let code = userDoc.data()["friendCode"] as? String ?? ""
                    buyerFriendCodes[userDoc.documentID] = code
                }
            }
        }

        return candidates.map { (orderId, data) in
            let buyerId = data["buyerId"] as? String ?? ""
            let buyerName = data["buyerName"] as? String ?? "Unknown"
            let cachedFriendCode = (data["buyerFriendCode"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return PostcardShippingRecipient(
                id: orderId,
                buyerId: buyerId,
                buyerName: buyerName,
                buyerFriendCode: cachedFriendCode.isEmpty ? (buyerFriendCodes[buyerId] ?? "") : cachedFriendCode,
                status: PostcardOrderStatus.from(rawValue: data["status"] as? String ?? "")
                    ?? .awaitingShipping
            )
        }
        .sorted { $0.buyerName.localizedCaseInsensitiveCompare($1.buyerName) == .orderedAscending }
    }

    func markPostcardSent(orderId: String) async throws { // Handles markPostcardSent flow.
        guard let sellerId = Auth.auth().currentUser?.uid else {
            throw PostcardRepoError.notSignedIn
        }

        let orderRef = db.collection("postcardOrders").document(orderId)
        let nowDate = Date()
        let now = Timestamp(date: nowDate)

        _ = try await db.runTransaction { tx, errorPointer in
            let orderSnap: DocumentSnapshot
            do {
                orderSnap = try tx.getDocument(orderRef)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }

            guard let order = orderSnap.data() else {
                errorPointer?.pointee = self.makeError(PostcardRepoError.listingNotFound)
                return nil
            }

            let orderSellerId = order["sellerId"] as? String ?? ""
            guard orderSellerId == sellerId else {
                errorPointer?.pointee = self.makeError(PostcardRepoError.forbidden)
                return nil
            }

            let statusRaw = order["status"] as? String ?? ""
            guard statusRaw == PostcardOrderStatus.awaitingShipping.rawValue ||
                statusRaw == "AwaitingSellerSend" else {
                errorPointer?.pointee = self.makeError(PostcardRepoError.invalidOrderState)
                return nil
            }

            let timeoutMap = order["timeouts"] as? [String: Any] ?? [:]
            let buyerReminderHours = timeoutMap["buyerReceiveReminderHours"] as? Int ?? self.buyerReceiveReminderHours
            let buyerConfirmHours = timeoutMap["buyerConfirmDeadlineHours"] as? Int ?? self.buyerConfirmDeadlineHours

            tx.updateData([
                "status": PostcardOrderStatus.shipped.rawValue,
                "sentAt": now,
                "buyerReminderAt": Timestamp(
                    date: nowDate.addingTimeInterval(TimeInterval(max(1, buyerReminderHours) * 3600))
                ),
                "buyerConfirmDeadlineAt": Timestamp(
                    date: nowDate.addingTimeInterval(TimeInterval(max(1, buyerConfirmHours) * 3600))
                ),
                "updatedAt": now
            ], forDocument: orderRef)

            return nil
        }
    }

    func fetchLatestBuyerOrder(postcardId: String) async throws -> PostcardBuyerOrder? { // Handles fetchLatestBuyerOrder flow.
        guard let buyerId = Auth.auth().currentUser?.uid else {
            throw PostcardRepoError.notSignedIn
        }

        let activeStatuses = [
            PostcardOrderStatus.awaitingShipping.rawValue,
            PostcardOrderStatus.shipped.rawValue,
            PostcardOrderStatus.sellerConfirmPending.rawValue,
            "AwaitingSellerSend",
            "InTransit",
            "AwaitingBuyerDecision"
        ]
        let query = db.collection("postcardOrders")
            .whereField("buyerId", isEqualTo: buyerId)
            .whereField("postcardId", isEqualTo: postcardId)
            .whereField("status", in: activeStatuses)
            .order(by: "createdAt", descending: true)
            .limit(to: 1)
        let docs = try await fetchDocuments(query: query)
        guard let latestDoc = docs.first else { return nil }
        return decodeBuyerOrder(latestDoc)
    }

    func confirmPostcardReceived(orderId: String) async throws { // Handles confirmPostcardReceived flow.
        guard let buyerId = Auth.auth().currentUser?.uid else {
            throw PostcardRepoError.notSignedIn
        }

        let orderRef = db.collection("postcardOrders").document(orderId)
        let buyerRef = db.collection("users").document(buyerId)
        let now = Timestamp(date: Date())

        _ = try await db.runTransaction { tx, errorPointer in
            let orderSnap: DocumentSnapshot
            do {
                orderSnap = try tx.getDocument(orderRef)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }

            guard let order = orderSnap.data() else {
                errorPointer?.pointee = self.makeError(PostcardRepoError.listingNotFound)
                return nil
            }

            let orderBuyerId = order["buyerId"] as? String ?? ""
            guard orderBuyerId == buyerId else {
                errorPointer?.pointee = self.makeError(PostcardRepoError.forbidden)
                return nil
            }

            let statusRaw = order["status"] as? String ?? ""
            guard statusRaw == PostcardOrderStatus.shipped.rawValue ||
                statusRaw == "InTransit" ||
                statusRaw == "AwaitingBuyerDecision" else {
                errorPointer?.pointee = self.makeError(PostcardRepoError.invalidOrderState)
                return nil
            }

            let sellerId = order["sellerId"] as? String ?? ""
            let holdHoney = order["holdHoney"] as? Int ?? 0
            guard !sellerId.isEmpty, holdHoney > 0 else {
                errorPointer?.pointee = self.makeError(PostcardRepoError.invalidListing)
                return nil
            }

            let sellerRef = self.db.collection("users").document(sellerId)
            let sellerSnap: DocumentSnapshot
            do {
                sellerSnap = try tx.getDocument(sellerRef)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }

            let sellerHoney = sellerSnap.data()?["honey"] as? Int ?? 0
            tx.setData([
                "honey": sellerHoney + holdHoney,
                "updatedAt": now,
            ], forDocument: sellerRef, merge: true)

            tx.updateData([
                "status": PostcardOrderStatus.completed.rawValue,
                "updatedAt": now,
                "completedAt": now,
            ], forDocument: orderRef)

            tx.setData([
                "updatedAt": now,
            ], forDocument: buyerRef, merge: true)

            return nil
        }
    }

    func sellerRejectOrder(orderId: String) async throws { // Handles sellerRejectOrder flow.
        guard let sellerId = Auth.auth().currentUser?.uid else {
            throw PostcardRepoError.notSignedIn
        }

        let orderRef = db.collection("postcardOrders").document(orderId)
        let now = Timestamp(date: Date())

        _ = try await db.runTransaction { tx, errorPointer in
            let orderSnap: DocumentSnapshot
            do {
                orderSnap = try tx.getDocument(orderRef)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }

            guard let order = orderSnap.data() else {
                errorPointer?.pointee = self.makeError(PostcardRepoError.listingNotFound)
                return nil
            }

            let orderSellerId = order["sellerId"] as? String ?? ""
            guard orderSellerId == sellerId else {
                errorPointer?.pointee = self.makeError(PostcardRepoError.forbidden)
                return nil
            }

            let statusRaw = order["status"] as? String ?? ""
            guard statusRaw == PostcardOrderStatus.awaitingShipping.rawValue ||
                statusRaw == PostcardOrderStatus.sellerConfirmPending.rawValue ||
                statusRaw == "AwaitingSellerSend" else {
                errorPointer?.pointee = self.makeError(PostcardRepoError.invalidOrderState)
                return nil
            }

            let orderBuyerId = order["buyerId"] as? String ?? ""
            let postcardId = order["postcardId"] as? String ?? ""
            let holdHoney = order["holdHoney"] as? Int ?? 0
            if orderBuyerId.isEmpty || postcardId.isEmpty || holdHoney <= 0 {
                errorPointer?.pointee = self.makeError(PostcardRepoError.invalidListing)
                return nil
            }

            let postcardRef = self.db.collection("postcards").document(postcardId)
            let buyerRef = self.db.collection("users").document(orderBuyerId)
            let postcardSnap: DocumentSnapshot
            let buyerSnap: DocumentSnapshot
            do {
                postcardSnap = try tx.getDocument(postcardRef)
                buyerSnap = try tx.getDocument(buyerRef)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }

            let stock = postcardSnap.data()?["stock"] as? Int ?? 0
            let buyerHoney = buyerSnap.data()?["honey"] as? Int ?? 0
            tx.setData([
                "stock": stock + 1,
                "updatedAt": now
            ], forDocument: postcardRef, merge: true)
            tx.setData([
                "honey": buyerHoney + holdHoney,
                "updatedAt": now
            ], forDocument: buyerRef, merge: true)

            tx.updateData([
                "status": PostcardOrderStatus.rejected.rawValue,
                "updatedAt": now,
                "completedAt": now
            ], forDocument: orderRef)

            return nil
        }
    }

    private func decodeListing(_ doc: QueryDocumentSnapshot) -> PostcardListing {
        decodeListing(id: doc.documentID, data: doc.data())
    }

    private func decodeBuyerOrder(_ doc: QueryDocumentSnapshot) -> PostcardBuyerOrder? {
        let data = doc.data()
        let postcardId = data["postcardId"] as? String ?? ""
        let statusRaw = data["status"] as? String ?? ""
        guard let status = PostcardOrderStatus.from(rawValue: statusRaw) else { return nil }

        let holdHoney = data["holdHoney"] as? Int ?? 0
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date.distantPast
        return PostcardBuyerOrder(
            id: doc.documentID,
            postcardId: postcardId,
            status: status,
            holdHoney: holdHoney,
            createdAt: createdAt
        )
    }

    private func decodeListing(id: String, data: [String: Any]) -> PostcardListing {
        let title = data["title"] as? String ?? "Untitled"
        let priceHoney = data["priceHoney"] as? Int ?? 0
        let sellerId = data["sellerId"] as? String ?? ""
        let sellerName = data["sellerName"] as? String ?? "Unknown"
        let sellerFriendCode = data["sellerFriendCode"] as? String ?? ""
        let stock = data["stock"] as? Int ?? 0
        let imageUrl = data["imageUrl"] as? String
        let thumbnailUrl = data["thumbnailUrl"] as? String

        let locationMap = data["location"] as? [String: Any]
        let location = PostcardLocation(
            country: locationMap?["country"] as? String ?? "",
            province: locationMap?["province"] as? String ?? "",
            detail: locationMap?["detail"] as? String ?? ""
        )

        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date.distantPast

        return PostcardListing(
            id: id,
            sellerId: sellerId,
            title: title,
            priceHoney: priceHoney,
            location: location,
            sellerName: sellerName,
            sellerFriendCode: sellerFriendCode,
            stock: stock,
            imageUrl: imageUrl,
            thumbnailUrl: thumbnailUrl,
            createdAt: createdAt
        )
    }

    private func deleteStorageImage(urlString: String?) async {
        guard let urlString = urlString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !urlString.isEmpty else { return }
        do {
            try await Storage.storage().reference(forURL: urlString).delete()
        } catch {
            // Best effort cleanup only.
        }
    }

    private func makeError(_ error: PostcardRepoError) -> NSError {
        NSError(
            domain: "Postcard",
            code: 400,
            userInfo: [NSLocalizedDescriptionKey: error.errorDescription ?? "Postcard error."]
        )
    }

    private func fetchDocuments(query: Query) async throws -> [QueryDocumentSnapshot] {
        do {
            return try await query.getDocuments(source: .server).documents
        } catch {
            return try await query.getDocuments(source: .default).documents
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] { // Handles chunked flow.
        guard size > 0, !isEmpty else { return isEmpty ? [] : [self] }
        var chunks: [[Element]] = []
        chunks.reserveCapacity((count + size - 1) / size)
        var index = 0
        while index < count {
            let end = Swift.min(index + size, count)
            chunks.append(Array(self[index..<end]))
            index += size
        }
        return chunks
    }
}
