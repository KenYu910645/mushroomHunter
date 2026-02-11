//
//  FirebaseBrowseRepository.swift
//  mushroomHunter
//
//  Created by Ken on 2/2/2026.
//

import Foundation
import FirebaseFirestore

struct RoomListing: Identifiable, Hashable {
    let id: String
    var title: String
    var mushroomType: String
    var targetColor: String
    var targetAttribute: String
    var targetSize: String
    var joinedPlayers: Int
    let maxPlayers: Int  // store from backend (default 10)
    var hostName: String?
    var hostStars: Int
    var location: String
    var expiresAt: Date? // optional for future
}

enum BrowseRepoError: LocalizedError {
    case decodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .decodeFailed(let msg): return msg
        }
    }
}

final class FirebaseBrowseRepository {
    private let db = Firestore.firestore()
    func fetchOpenListings(limit: Int = 50) async throws -> [RoomListing] {
        // ✅ Must match your createRoom(): collection is "rooms"
        let q = db.collection("rooms")
            .order(by: "createdAt", descending: true)
            .limit(to: limit)

        let snap = try await q.getDocuments()

        return snap.documents.map { doc in
            let data = doc.data()

            let title = (data["title"] as? String)
                ?? (data["roomTitle"] as? String)
                ?? "Untitled Room"

            // ✅ Your Firestore fields are: targetColor / targetAttribute / targetSize
            // For Browse filtering, we usually show "attribute" as the "mushroomType"
            let mushroomType = (data["targetAttribute"] as? String)
                ?? (data["attribute"] as? String)
                ?? "normal"

            let joined = data["joinedCount"] as? Int ?? 0
            let maxPlayers = data["maxPlayers"] as? Int ?? 10
            let targetColor = (data["targetColor"] as? String) ?? ""
            let targetAttribute = (data["targetAttribute"] as? String) ?? ""
            let targetSize = (data["targetSize"] as? String) ?? ""

            return RoomListing(
                id: doc.documentID, // ✅ This must be used for RoomDetails route
                title: title,
                mushroomType: mushroomType.capitalized,
                targetColor: targetColor,
                targetAttribute: targetAttribute,
                targetSize: targetSize,
                joinedPlayers: joined,
                maxPlayers: maxPlayers,
                hostName: nil,
                hostStars: 0,
                location: data["location"] as? String ?? "",
                expiresAt: (data["expiresAt"] as? Timestamp)?.dateValue()
            )
        }
    }
}
