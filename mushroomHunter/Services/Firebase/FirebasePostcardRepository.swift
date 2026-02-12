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

    var errorDescription: String? {
        switch self {
        case .decodeFailed(let msg): return msg
        case .notSignedIn: return "Please sign in first."
        case .listingNotFound: return "Postcard listing not found."
        case .invalidListing: return "Postcard listing is invalid."
        case .outOfStock: return "This postcard is out of stock."
        case .notEnoughHoney: return "Not enough honey."
        case .cannotBuyOwnListing: return "You cannot buy your own postcard."
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
        sellerName: String
    ) async throws {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSeller = sellerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCountry = location.country.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanProvince = location.province.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDetail = location.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = SearchTokenBuilder.indexTokens(
            from: [cleanTitle, cleanSeller, cleanCountry, cleanProvince, cleanDetail]
        )

        try await db.collection("postcards").document(postcardId).setData([
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
        ], merge: true)
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

    private func decodeListing(_ doc: QueryDocumentSnapshot) -> PostcardListing {
        decodeListing(id: doc.documentID, data: doc.data())
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
