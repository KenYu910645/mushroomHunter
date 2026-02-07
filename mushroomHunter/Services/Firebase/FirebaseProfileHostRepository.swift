//
//  FirebaseProfileHostRepository.swift
//  mushroomHunter
//
//  Created by Ken on 6/2/2026.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

struct HostedRoomSummary: Identifiable, Hashable {
    let id: String          // Firestore docID
    let title: String
    let joinedCount: Int
    let maxPlayers: Int
    let status: String
    let createdAt: Date?
}

struct JoinedRoomSummary: Identifiable, Hashable {
    let id: String
    let title: String
    let joinedCount: Int
    let maxPlayers: Int
    let status: String
    let bidHoney: Int
    let updatedAt: Date?
}

final class FirebaseProfileHostRepository {
    private let db = Firestore.firestore()

    func fetchMyHostedRooms(limit: Int = 50) async throws -> [HostedRoomSummary] {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }

        let q = db.collection("rooms")
            .whereField("hostUid", isEqualTo: uid)
            .whereField("status", isEqualTo: "open")
            .order(by: "createdAt", descending: true)
            .limit(to: limit)

        let snap = try await q.getDocuments()

        return snap.documents.map { doc in
            let d = doc.data()
            return HostedRoomSummary(
                id: doc.documentID,
                title: (d["title"] as? String) ?? "Untitled Room",
                joinedCount: (d["joinedCount"] as? Int) ?? 0,
                maxPlayers: (d["maxPlayers"] as? Int) ?? 10,
                status: (d["status"] as? String) ?? "open",
                createdAt: (d["createdAt"] as? Timestamp)?.dateValue()
            )
        }
    }

    func fetchMyJoinedRooms(limit: Int = 50) async throws -> [JoinedRoomSummary] {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }

        let attendeesQuery = db.collectionGroup("attendees")
            .whereField("uid", isEqualTo: uid)
            .order(by: "updatedAt", descending: true)
            .limit(to: limit)

        let attendeeSnap = try await attendeesQuery.getDocuments()

        var results: [JoinedRoomSummary] = []
        results.reserveCapacity(attendeeSnap.documents.count)

        for doc in attendeeSnap.documents {
            guard let roomRef = doc.reference.parent.parent else { continue }
            let roomSnap = try await roomRef.getDocument()
            guard let data = roomSnap.data() else { continue }

            let bidHoney = doc.data()["bidHoney"] as? Int ?? 0

            results.append(
                JoinedRoomSummary(
                    id: roomRef.documentID,
                    title: (data["title"] as? String) ?? "Untitled Room",
                    joinedCount: (data["joinedCount"] as? Int) ?? 0,
                    maxPlayers: (data["maxPlayers"] as? Int) ?? 10,
                    status: (data["status"] as? String) ?? "open",
                    bidHoney: bidHoney,
                    updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue()
                )
            )
        }

        return results
    }
}
