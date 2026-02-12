import Foundation
import FirebaseFirestore

enum PostcardRepoError: LocalizedError {
    case decodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .decodeFailed(let msg): return msg
        }
    }
}

final class FirebasePostcardRepository {
    private let db = Firestore.firestore()

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
}
