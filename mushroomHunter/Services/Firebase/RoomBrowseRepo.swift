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
//  [R] - `hostUid`: Reads host uid used to resolve host stars from user profile snapshots.
//  [R] - `location`: Reads location text shown in browse cards.
//  [X] - `description`: Not used by browse list UI.
//  [X] - `fixedRaidCost`: Not used by browse list UI.
//  [R] - `maxPlayers`: Reads cap to show joined/max occupancy.
//  [R] - `joinedCount`: Reads current joined count for occupancy display.
//  [R] - `createdAt`: Reads for query ordering (`order by createdAt desc`).
//  [X] - `updatedAt`: Not used by browse list UI.
//  [R] - `lastSuccessfulRaidAt`: Reads for dormant-room priority downgrade logic.
//  [R] - `mushroomType`: Reads normalized room mushroom type label for browse cards.
//  [R] - `attribute` (legacy fallback): Reads fallback mushroom type when `mushroomType` is missing.
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
    var joinedPlayers: Int
    let maxPlayers: Int  // store from backend (default 10)
    var hostUid: String
    var hostStars: Int
    var location: String
    var createdAt: Date?
    var lastSuccessfulRaidAt: Date?
    var expiresAt: Date? // optional for future
}

final class FbRoomBrowseRepo {
    private let db = Firestore.firestore()
    func fetchOpenListings(
        limit: Int = AppConfig.Mushroom.browseListFetchLimit,
        isForcingServer: Bool = false
    ) async throws -> [RoomListing] { // Handles fetchOpenListings flow.
        // ✅ Must match your createRoom(): collection is "rooms"
        let q = db.collection("rooms")
            .order(by: "createdAt", descending: true)
            .limit(to: limit)

        let snap = try await fetchSnapshot(query: q, isForcingServer: isForcingServer)

        return try await hydrateHostStars(
            snap.documents.map(decodeListing),
            isForcingServer: isForcingServer
        )
    }

    /// Loads room listings by ids for pinned "joined/hosted" browse slots.
    /// - Parameter roomIds: Target room ids that should be resolved into listing rows.
    /// - Returns: Decoded room listings for ids that still exist.
    func fetchListings(
        roomIds: [String],
        isForcingServer: Bool = false
    ) async throws -> [RoomListing] {
        let uniqueRoomIds = Array(Set(roomIds.filter { !$0.isEmpty }))
        guard uniqueRoomIds.isEmpty == false else { return [] }

        var listings: [RoomListing] = []
        for roomIdChunk in uniqueRoomIds.chunked(into: 10) {
            let query = db.collection("rooms")
                .whereField(FieldPath.documentID(), in: roomIdChunk)
            let snapshot = try await fetchSnapshot(query: query, isForcingServer: isForcingServer)
            listings.append(contentsOf: snapshot.documents.map(decodeListing))
        }
        return try await hydrateHostStars(listings, isForcingServer: isForcingServer)
    }

    /// Decodes Firestore room document into browse listing payload.
    /// - Parameter document: Firestore room document snapshot.
    /// - Returns: Browse-list-ready room listing value.
    private func decodeListing(_ document: QueryDocumentSnapshot) -> RoomListing {
        let data = document.data()
        let title = (data["title"] as? String)
            ?? (data["roomTitle"] as? String)
            ?? "Untitled Room"
        let mushroomType = (data["mushroomType"] as? String)
            ?? (data["attribute"] as? String)
            ?? "normal"
        let joined = data["joinedCount"] as? Int ?? 0
        let maxPlayers = data["maxPlayers"] as? Int ?? AppConfig.Mushroom.defaultMaxPlayersPerRoom

        return RoomListing(
            id: document.documentID,
            title: title,
            mushroomType: mushroomType.capitalized,
            joinedPlayers: joined,
            maxPlayers: maxPlayers,
            hostUid: data["hostUid"] as? String ?? "",
            hostStars: data["hostStars"] as? Int ?? 0,
            location: data["location"] as? String ?? "",
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue(),
            lastSuccessfulRaidAt: (data["lastSuccessfulRaidAt"] as? Timestamp)?.dateValue(),
            expiresAt: (data["expiresAt"] as? Timestamp)?.dateValue()
        )
    }

    /// Resolves latest host stars from user profiles, keeping room-level stars as a legacy fallback.
    /// - Parameter listings: Decoded room listings awaiting host-star hydration.
    /// - Returns: Listings with `hostStars` overridden by `users/{uid}.stars` when available.
    private func hydrateHostStars(
        _ listings: [RoomListing],
        isForcingServer: Bool
    ) async throws -> [RoomListing] {
        let hostUids = Array(Set(listings.map(\.hostUid).filter { !$0.isEmpty }))
        guard hostUids.isEmpty == false else { return listings }

        var starsByUid: [String: Int] = [:]
        for hostUidChunk in hostUids.chunked(into: 10) {
            let query = db.collection("users")
                .whereField(FieldPath.documentID(), in: hostUidChunk)
            let snapshot = try await fetchSnapshot(query: query, isForcingServer: isForcingServer)
            for document in snapshot.documents {
                let starsValue = document.data()["stars"] as? Int ?? 0
                starsByUid[document.documentID] = max(0, starsValue)
            }
        }

        return listings.map { listing in
            var hydratedListing = listing
            if let stars = starsByUid[listing.hostUid] {
                hydratedListing.hostStars = stars
            }
            return hydratedListing
        }
    }

    /// Resolves a Firestore query snapshot with optional cache fallback.
    /// - Parameters:
    ///   - query: Firestore query used by browse and pinned-room refresh flows.
    ///   - isForcingServer: True when the caller requires a server-authoritative refresh.
    /// - Returns: Snapshot from the requested source policy.
    private func fetchSnapshot(query: Query, isForcingServer: Bool) async throws -> QuerySnapshot {
        if isForcingServer {
            return try await query.getDocuments(source: .server)
        }
        do {
            return try await query.getDocuments(source: .server)
        } catch {
            return try await query.getDocuments(source: .default)
        }
    }
}

private extension Array {
    /// Splits array into fixed-size chunks for Firestore `in` query limits.
    /// - Parameter size: Max number of items per chunk.
    /// - Returns: Ordered chunked array slices.
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
