//
//  FirebaseBrowseRepository.swift
//  mushroomHunter
//
//  Created by Ken on 2/2/2026.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

struct RoomListing: Identifiable, Hashable {
    let id: String
    var title: String
    var mushroomType: String
    var joinedPlayers: Int
    let maxPlayers: Int  // store from backend (default 10)
    var hostName: String?
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

    /// Fetch open listings from /listings
    /// - Parameters:
    ///   - limit: max docs returned
    func fetchOpenListings(limit: Int = 50) async throws -> [RoomListing] {
        // Query: status == "open", order by createdAt desc
        // NOTE: this requires your docs to have "status" + "createdAt".
        let q = db.collection("listings")
            .whereField("status", isEqualTo: "open")
            .order(by: "createdAt", descending: true)
            .limit(to: limit)

        let snap = try await q.getDocuments()

        return try snap.documents.map { doc in
            let data = doc.data()

            guard let title = data["title"] as? String ?? data["roomTitle"] as? String else {
                // In case you used "hostName" as title earlier, you can adjust here.
                // For your current HostView, you likely don't have "title" yet.
                // We'll fallback to hostName.
                let host = data["hostName"] as? String ?? "Host"
                return RoomListing(
                    id: doc.documentID,
                    title: host,
                    mushroomType: (data["attribute"] as? String) ?? "Normal",
                    joinedPlayers: (data["joinedCount"] as? Int) ?? 0,
                    maxPlayers: (data["maxPlayers"] as? Int) ?? 10,
                    hostName: (data["hostName"] as? String),
                    expiresAt: (data["expiresAt"] as? Timestamp)?.dateValue()
                )
            }

            return RoomListing(
                id: doc.documentID,
                title: title,
                mushroomType: (data["attribute"] as? String) ?? "Normal",
                joinedPlayers: (data["joinedCount"] as? Int) ?? 0,
                maxPlayers: (data["maxPlayers"] as? Int) ?? 10,
                hostName: (data["hostName"] as? String),
                expiresAt: (data["expiresAt"] as? Timestamp)?.dateValue()
            )
        }
    }
}

// MARK: FirebaseBrowseRepository
extension FirebaseBrowseRepository {

    /// Join a listing using transaction (max 10 players enforced)
    func join(listing: RoomListing) async throws {

        guard let user = Auth.auth().currentUser else {
            throw NSError(
                domain: "Auth",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Not signed in"]
            )
        }

        let listingRef = db.collection("listings").document(listing.id)
        let joinRef = listingRef.collection("joins").document(user.uid)

        try await db.runTransaction { txn, errorPointer in

            do {
                // Read listing
                let snap = try txn.getDocument(listingRef)

                let joined = (snap.data()?["joinedCount"] as? Int) ?? 0
                let maxPlayers = (snap.data()?["maxPlayers"] as? Int) ?? 10
                let status = (snap.data()?["status"] as? String) ?? "open"

                // Validate
                if status != "open" {
                    errorPointer?.pointee = NSError(
                        domain: "Join",
                        code: 400,
                        userInfo: [NSLocalizedDescriptionKey: "Room is not open"]
                    )
                    return nil
                }

                if joined >= maxPlayers {
                    errorPointer?.pointee = NSError(
                        domain: "Join",
                        code: 409,
                        userInfo: [NSLocalizedDescriptionKey: "Room is full"]
                    )
                    return nil
                }

                // Prevent double join
                if let joinSnap = try? txn.getDocument(joinRef),
                   joinSnap.exists {
                    // Already joined → no-op
                    return nil
                }

                // Update joined count
                txn.updateData(
                    ["joinedCount": joined + 1],
                    forDocument: listingRef
                )

                // Create join record
                txn.setData([
                    "uid": user.uid,
                    "displayName": user.displayName ?? "",
                    "joinedAt": FieldValue.serverTimestamp()
                ], forDocument: joinRef)

                return nil

            } catch let err as NSError {
                errorPointer?.pointee = err
                return nil
            }
        }
    }
}
