//
//  RoomBrowseRepo.swift
//  mushroomHunter
//
//  Purpose:
//  - Contains Firestore reads and mapping for Mushroom room browse listings.
//
//  Defined in this file:
//  - RoomListing model and Firebase browse query/mapper methods.
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
    var location: String
    var expiresAt: Date? // optional for future
}

final class FirebaseBrowseRepository {
    private let db = Firestore.firestore()
    func fetchOpenListings(limit: Int = AppConfig.Mushroom.browseListFetchLimit) async throws -> [RoomListing] { // Handles fetchOpenListings flow.
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
            let maxPlayers = data["maxPlayers"] as? Int ?? AppConfig.Mushroom.defaultMaxPlayersPerRoom
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
                hostName: data["hostName"] as? String,
                location: data["location"] as? String ?? "",
                expiresAt: (data["expiresAt"] as? Timestamp)?.dateValue()
            )
        }
    }
}
