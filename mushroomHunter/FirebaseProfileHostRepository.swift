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

final class FirebaseProfileHostRepository {
    private let db = Firestore.firestore()

    func fetchMyHostedRooms(limit: Int = 50) async throws -> [HostedRoomSummary] {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }

        let q = db.collection("rooms")
            .whereField("hostUid", isEqualTo: uid)
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
}
