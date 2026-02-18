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
//  [W] - `sellerReminderAt`: Writes seller reminder deadline.
//  [W] - `sellerDeadlineAt`: Writes seller send deadline.
//  [W] - `buyerReminderAt`: Writes buyer reminder deadline.
//  [W] - `buyerAutoCompleteAt`: Writes buyer auto-complete deadline.
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

enum PostcardRepoError: LocalizedError {
    case notSignedIn
    case listingNotFound
    case invalidListing
    case outOfStock
    case notEnoughHoney
    case cannotBuyOwnListing
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
        case .forbidden: return "You don't have access to this action."
        case .invalidOrderState: return "Order is not in a shippable state."
        }
    }
}

final class FbPostcardRepo {
    private let db = Firestore.firestore()
    private let sellerSendReminderHours = AppConfig.Postcard.sellerSendReminderHours
    private let sellerSendDeadlineHours = AppConfig.Postcard.sellerSendDeadlineHours
    private let buyerReceiveReminderHours = AppConfig.Postcard.buyerReceiveReminderHours
    private let buyerAutoCompleteHours = AppConfig.Postcard.buyerAutoCompleteHours

    func fetchRecent(limit: Int = AppConfig.Postcard.browseListFetchLimit) async throws -> [PostcardListing] { // Handles fetchRecent flow.
        let q = db.collection("postcards")
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

    func fetchMyOrderedPostcards(userId: String, limit: Int = AppConfig.Postcard.profileListFetchLimit) async throws -> [PostcardListing] { // Handles fetchMyOrderedPostcards flow.
        let activeStatuses = [
            PostcardOrderStatus.awaitingSellerSend.rawValue,
            PostcardOrderStatus.inTransit.rawValue,
            PostcardOrderStatus.awaitingBuyerDecision.rawValue
        ]
        let query = db.collection("postcardOrders")
            .whereField("buyerId", isEqualTo: userId)
            .whereField("status", in: activeStatuses)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
        let orderDocs = try await fetchDocuments(query: query)

        let orderedPostcardIds = orderDocs
            .compactMap { doc -> String? in
                let id = (doc.data()["postcardId"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return id.isEmpty ? nil : id
            }
        if orderedPostcardIds.isEmpty { return [] }

        let uniqueIds = Array(Set(orderedPostcardIds))
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

        return orderedPostcardIds.compactMap { listingById[$0] }
    }

    func searchByToken(_ token: String, limit: Int = AppConfig.Postcard.browseListFetchLimit) async throws -> [PostcardListing] { // Handles searchByToken flow.
        let q = db.collection("postcards")
            .whereField("searchTokens", arrayContains: token)
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
        imageUrl: String
    ) async throws {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSellerId = sellerId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSeller = sellerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSellerFriendCode = sellerFriendCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSellerFcmToken = sellerFcmToken.trimmingCharacters(in: .whitespacesAndNewlines)
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
        imageUrl: String? = nil
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

        try await db.collection("postcards").document(postcardId).setData(payload, merge: true)
    }

    func deletePostcard(postcardId: String) async throws { // Handles deletePostcard flow.
        try await db.collection("postcards").document(postcardId).delete()
    }

    @discardableResult
    func buyPostcard(postcardId: String) async throws -> String { // Handles buyPostcard flow.
        guard let buyerId = Auth.auth().currentUser?.uid else {
            throw PostcardRepoError.notSignedIn
        }

        let orderRef = db.collection("postcardOrders").document()
        let postcardRef = db.collection("postcards").document(postcardId)
        let buyerRef = db.collection("users").document(buyerId)

        let nowDate = Date()
        let now = Timestamp(date: nowDate)
        let sellerReminderAt = Timestamp(date: nowDate.addingTimeInterval(TimeInterval(sellerSendReminderHours * 3600)))
        let sellerDeadlineAt = Timestamp(date: nowDate.addingTimeInterval(TimeInterval(sellerSendDeadlineHours * 3600)))
        let buyerReminderAt = Timestamp(date: nowDate.addingTimeInterval(TimeInterval(buyerReceiveReminderHours * 3600)))
        let buyerAutoCompleteAt = Timestamp(date: nowDate.addingTimeInterval(TimeInterval(buyerAutoCompleteHours * 3600)))

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
                "status": PostcardOrderStatus.awaitingSellerSend.rawValue,
                "buyerId": buyerId,
                "buyerName": buyerName,
                "buyerFriendCode": buyerFriendCode,
                "buyerFcmToken": buyerFcmToken,
                "sellerId": sellerId,
                "sellerName": sellerName,
                "sellerFcmToken": sellerFcmToken,
                "priceHoney": priceHoney,
                "holdHoney": priceHoney,
                "sellerReminderAt": sellerReminderAt,
                "sellerDeadlineAt": sellerDeadlineAt,
                "buyerReminderAt": buyerReminderAt,
                "buyerAutoCompleteAt": buyerAutoCompleteAt,
                "timeouts": [
                    "sellerSendReminderHours": self.sellerSendReminderHours,
                    "sellerSendDeadlineHours": self.sellerSendDeadlineHours,
                    "buyerReceiveReminderHours": self.buyerReceiveReminderHours,
                    "buyerAutoCompleteHours": self.buyerAutoCompleteHours
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

        let query = db.collection("postcardOrders")
            .whereField("postcardId", isEqualTo: postcardId)
            .whereField("sellerId", isEqualTo: sellerId)
            .whereField("status", isEqualTo: PostcardOrderStatus.awaitingSellerSend.rawValue)

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
                buyerFriendCode: cachedFriendCode.isEmpty ? (buyerFriendCodes[buyerId] ?? "") : cachedFriendCode
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
            guard statusRaw == PostcardOrderStatus.awaitingSellerSend.rawValue else {
                errorPointer?.pointee = self.makeError(PostcardRepoError.invalidOrderState)
                return nil
            }

            let timeoutMap = order["timeouts"] as? [String: Any] ?? [:]
            let buyerReminderHours = timeoutMap["buyerReceiveReminderHours"] as? Int ?? self.buyerReceiveReminderHours
            let buyerAutoHours = timeoutMap["buyerAutoCompleteHours"] as? Int ?? self.buyerAutoCompleteHours

            tx.updateData([
                "status": PostcardOrderStatus.inTransit.rawValue,
                "sentAt": now,
                "buyerReminderAt": Timestamp(
                    date: nowDate.addingTimeInterval(TimeInterval(max(1, buyerReminderHours) * 3600))
                ),
                "buyerAutoCompleteAt": Timestamp(
                    date: nowDate.addingTimeInterval(TimeInterval(max(1, buyerAutoHours) * 3600))
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
            PostcardOrderStatus.awaitingSellerSend.rawValue,
            PostcardOrderStatus.inTransit.rawValue,
            PostcardOrderStatus.awaitingBuyerDecision.rawValue
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
            guard statusRaw == PostcardOrderStatus.inTransit.rawValue ||
                statusRaw == PostcardOrderStatus.awaitingBuyerDecision.rawValue else {
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

    func markPostcardNotYetReceived(orderId: String) async throws { // Handles markPostcardNotYetReceived flow.
        guard let buyerId = Auth.auth().currentUser?.uid else {
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

            let orderBuyerId = order["buyerId"] as? String ?? ""
            guard orderBuyerId == buyerId else {
                errorPointer?.pointee = self.makeError(PostcardRepoError.forbidden)
                return nil
            }

            let statusRaw = order["status"] as? String ?? ""
            guard statusRaw == PostcardOrderStatus.inTransit.rawValue ||
                statusRaw == PostcardOrderStatus.awaitingBuyerDecision.rawValue else {
                errorPointer?.pointee = self.makeError(PostcardRepoError.invalidOrderState)
                return nil
            }

            let timeoutMap = order["timeouts"] as? [String: Any] ?? [:]
            let buyerReminderHours = timeoutMap["buyerReceiveReminderHours"] as? Int ?? self.buyerReceiveReminderHours
            let buyerAutoHours = timeoutMap["buyerAutoCompleteHours"] as? Int ?? self.buyerAutoCompleteHours

            tx.updateData([
                "status": PostcardOrderStatus.awaitingBuyerDecision.rawValue,
                "buyerReminderAt": Timestamp(
                    date: nowDate.addingTimeInterval(TimeInterval(max(1, buyerReminderHours) * 3600))
                ),
                "buyerAutoCompleteAt": Timestamp(
                    date: nowDate.addingTimeInterval(TimeInterval(max(1, buyerAutoHours) * 3600))
                ),
                "updatedAt": now,
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
        guard let status = PostcardOrderStatus(rawValue: statusRaw) else { return nil }

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
            createdAt: createdAt
        )
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
