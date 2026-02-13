import Foundation
import FirebaseAuth
import FirebaseFirestore

enum PostcardRepoError: LocalizedError {
    case decodeFailed(String)
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
        case .decodeFailed(let msg): return msg
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

final class FirebasePostcardRepository {
    private let db = Firestore.firestore()
    private let sellerSendReminderHours = 24
    private let sellerSendDeadlineHours = 24
    private let buyerReceiveReminderHours = 24
    private let buyerAutoCompleteHours = 72

    func fetchRecent(limit: Int = 50) async throws -> [PostcardListing] {
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

    func fetchMyListings(userId: String, limit: Int = 50) async throws -> [PostcardListing] {
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

    func fetchMyOrderedPostcards(userId: String, limit: Int = 50) async throws -> [PostcardListing] {
        let q = db.collection("postcardOrders")
            .whereField("buyerId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)

        let orderSnap: QuerySnapshot
        do {
            orderSnap = try await q.getDocuments(source: .server)
        } catch {
            orderSnap = try await q.getDocuments(source: .default)
        }

        let orderedPostcardIds = orderSnap.documents.compactMap { doc -> String? in
            let statusRaw = (doc.data()["status"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if statusRaw == PostcardOrderStatus.completed.rawValue ||
                statusRaw == PostcardOrderStatus.cancelled.rawValue {
                return nil
            }
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

    func searchByToken(_ token: String, limit: Int = 50) async throws -> [PostcardListing] {
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

    func fetchPostcard(postcardId: String) async throws -> PostcardListing? {
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

    func fetchUserFriendCode(userId: String) async throws -> String {
        let ref = db.collection("users").document(userId)
        let snap: DocumentSnapshot
        do {
            snap = try await ref.getDocument(source: .server)
        } catch {
            snap = try await ref.getDocument(source: .default)
        }
        return snap.data()?["friendCode"] as? String ?? ""
    }

    func createPostcard(
        title: String,
        priceHoney: Int,
        location: PostcardLocation,
        stock: Int,
        sellerId: String,
        sellerName: String,
        imageUrl: String
    ) async throws {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSellerId = sellerId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSeller = sellerName.trimmingCharacters(in: .whitespacesAndNewlines)
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
        imageUrl: String? = nil
    ) async throws {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSeller = sellerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCountry = location.country.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanProvince = location.province.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDetail = location.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = SearchTokenBuilder.indexTokens(
            from: [cleanTitle, cleanSeller, cleanCountry, cleanProvince, cleanDetail]
        )

        var payload: [String: Any] = [
            "title": cleanTitle,
            "priceHoney": priceHoney,
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

    func deletePostcard(postcardId: String) async throws {
        try await db.collection("postcards").document(postcardId).delete()
    }

    @discardableResult
    func buyPostcard(postcardId: String) async throws -> String {
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

            tx.setData([
                "postcardId": postcardId,
                "postcardTitle": title,
                "postcardImageUrl": imageUrl,
                "location": location,
                "status": PostcardOrderStatus.awaitingSellerSend.rawValue,
                "buyerId": buyerId,
                "buyerName": buyerName,
                "sellerId": sellerId,
                "sellerName": sellerName,
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

    func fetchShippingRecipients(postcardId: String) async throws -> [PostcardShippingRecipient] {
        guard let sellerId = Auth.auth().currentUser?.uid else {
            throw PostcardRepoError.notSignedIn
        }

        let query = db.collection("postcardOrders")
            .whereField("postcardId", isEqualTo: postcardId)
            .limit(to: 100)

        let snap: QuerySnapshot
        do {
            snap = try await query.getDocuments(source: .server)
        } catch {
            snap = try await query.getDocuments(source: .default)
        }

        let candidates = snap.documents.compactMap { doc -> (String, [String: Any])? in
            let data = doc.data()
            let statusRaw = data["status"] as? String ?? ""
            let orderSellerId = data["sellerId"] as? String ?? ""
            guard orderSellerId == sellerId, statusRaw == PostcardOrderStatus.awaitingSellerSend.rawValue else {
                return nil
            }
            return (doc.documentID, data)
        }

        if candidates.isEmpty { return [] }

        let buyerIds = Array(Set(candidates.compactMap { $0.1["buyerId"] as? String }).filter { !$0.isEmpty })
        var buyerFriendCodes: [String: String] = [:]

        if !buyerIds.isEmpty {
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
            return PostcardShippingRecipient(
                id: orderId,
                buyerId: buyerId,
                buyerName: buyerName,
                buyerFriendCode: buyerFriendCodes[buyerId] ?? ""
            )
        }
        .sorted { $0.buyerName.localizedCaseInsensitiveCompare($1.buyerName) == .orderedAscending }
    }

    func markPostcardSent(orderId: String) async throws {
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

    func fetchLatestBuyerOrder(postcardId: String) async throws -> PostcardBuyerOrder? {
        guard let buyerId = Auth.auth().currentUser?.uid else {
            throw PostcardRepoError.notSignedIn
        }

        let query = db.collection("postcardOrders")
            .whereField("buyerId", isEqualTo: buyerId)
            .whereField("postcardId", isEqualTo: postcardId)
            .limit(to: 50)

        let snap: QuerySnapshot
        do {
            snap = try await query.getDocuments(source: .server)
        } catch {
            snap = try await query.getDocuments(source: .default)
        }

        let orders = snap.documents.compactMap(decodeBuyerOrder)
            .filter { $0.status != .completed && $0.status != .cancelled }
            .sorted { $0.createdAt > $1.createdAt }

        return orders.first
    }

    func confirmPostcardReceived(orderId: String) async throws {
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

    func markPostcardNotYetReceived(orderId: String) async throws {
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
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
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
