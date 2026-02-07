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

        let snap = try await q.getDocuments()
        return snap.documents.map(decodeListing)
    }

    func searchByToken(_ token: String, limit: Int = 50) async throws -> [PostcardListing] {
        let q = db.collection("postcards")
            .whereField("searchTokens", arrayContains: token)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)

        let snap = try await q.getDocuments()
        return snap.documents.map(decodeListing)
    }

    private func decodeListing(_ doc: QueryDocumentSnapshot) -> PostcardListing {
        let data = doc.data()

        let title = data["title"] as? String ?? "Untitled"
        let priceHoney = data["priceHoney"] as? Int ?? 0
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
            id: doc.documentID,
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
