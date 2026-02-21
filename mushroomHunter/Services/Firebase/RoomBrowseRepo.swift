//
//  RoomBrowseRepo.swift
//  mushroomHunter
//
//  Purpose:
//  - Repository for Mushroom browse list flow.
//
//  Related flow:
//  - Mushroom tab -> browse/open rooms list.
//
//  Field access legend:
//  [R] Represent Read
//  [X] Represent dont care
//  [W] Represent write
//
//  Room document (`rooms/{roomId}`):
//  [R] - `documentId`: Uses room id as the browse card identity and navigation key.
//  [R] - `title`: Reads primary room title shown in browse cards.
//  [R] - `roomTitle` (legacy fallback): Reads fallback title when `title` is missing.
//  [R] - `hostName`: Reads host display name for browse summary.
//  [R] - `hostStars`: Reads host-star snapshot for browse priority sorting.
//  [R] - `location`: Reads location text shown in browse cards.
//  [X] - `description`: Not used by browse list UI.
//  [X] - `fixedRaidCost`: Not used by browse list UI.
//  [R] - `maxPlayers`: Reads cap to show joined/max occupancy.
//  [R] - `joinedCount`: Reads current joined count for occupancy display.
//  [R] - `createdAt`: Reads for query ordering (`order by createdAt desc`).
//  [X] - `updatedAt`: Not used by browse list UI.
//  [R] - `lastSuccessfulRaidAt`: Reads for dormant-room priority downgrade logic.
//  [R] - `targetColor`: Reads target color for browse filters/badges.
//  [R] - `targetAttribute`: Reads target attribute and derives `mushroomType`.
//  [R] - `attribute` (legacy fallback): Reads fallback when `targetAttribute` is missing.
//  [R] - `targetSize`: Reads target size for browse filters/badges.
//  [R] - `expiresAt`: Reads optional expiration timestamp for display logic.
//
//  Attendee document (`rooms/{roomId}/attendees/{uid}`):
//  [X] - `uid`: Browse flow does not query attendee subcollection.
//  [X] - `name`: Browse flow does not query attendee subcollection.
//  [X] - `friendCode`: Browse flow does not query attendee subcollection.
//  [X] - `stars`: Browse flow does not query attendee subcollection.
//  [X] - `depositHoney`: Browse flow does not query attendee subcollection.
//  [X] - `status`: Browse flow does not query attendee subcollection.
//  [X] - `joinedAt`: Browse flow does not query attendee subcollection.
//  [X] - `updatedAt`: Browse flow does not query attendee subcollection.
//  [X] - `needsHostRating`: Browse flow does not query attendee subcollection.
//  [X] - `attendeeRatedHost`: Browse flow does not query attendee subcollection.
//  [X] - `hostRatedAttendee`: Browse flow does not query attendee subcollection.
//
import Foundation
import FirebaseFirestore

struct RoomListing: Identifiable, Hashable, Codable {
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
    var createdAt: Date?
    var lastSuccessfulRaidAt: Date?
    var expiresAt: Date? // optional for future
}

final class FbRoomBrowseRepo {
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
                id: doc.documentID, // ✅ This must be used for Room route
                title: title,
                mushroomType: mushroomType.capitalized,
                targetColor: targetColor,
                targetAttribute: targetAttribute,
                targetSize: targetSize,
                joinedPlayers: joined,
                maxPlayers: maxPlayers,
                hostName: data["hostName"] as? String,
                hostStars: data["hostStars"] as? Int ?? 0,
                location: data["location"] as? String ?? "",
                createdAt: (data["createdAt"] as? Timestamp)?.dateValue(),
                lastSuccessfulRaidAt: (data["lastSuccessfulRaidAt"] as? Timestamp)?.dateValue(),
                expiresAt: (data["expiresAt"] as? Timestamp)?.dateValue()
            )
        }
    }
}
