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
    let createdAt: Date?
}

struct JoinedRoomSummary: Identifiable, Hashable {
    let id: String
    let title: String
    let joinedCount: Int
    let maxPlayers: Int
    let depositHoney: Int
    let updatedAt: Date?
}

final class FirebaseProfileHostRepository {
    private let db = Firestore.firestore()

    func fetchMyHostedRooms(limit: Int = 50) async throws -> [HostedRoomSummary] {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }

        let attendeeSnap = try await db.collectionGroup("attendees")
            .whereField("status", isEqualTo: AttendeeStatus.host.rawValue)
            .getDocuments()

        var results: [HostedRoomSummary] = []
        results.reserveCapacity(attendeeSnap.documents.count)

        for doc in attendeeSnap.documents {
            guard doc.documentID == uid else { continue }
            guard let roomRef = doc.reference.parent.parent else { continue }
            let roomSnap = try await roomRef.getDocument()
            guard let d = roomSnap.data() else { continue }

            results.append(
                HostedRoomSummary(
                    id: roomRef.documentID,
                    title: (d["title"] as? String) ?? "Untitled Room",
                    joinedCount: (d["joinedCount"] as? Int) ?? 0,
                    maxPlayers: (d["maxPlayers"] as? Int) ?? 10,
                    createdAt: (d["createdAt"] as? Timestamp)?.dateValue()
                )
            )
        }

        return results
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            .prefix(limit)
            .map { $0 }
    }

    func fetchMyJoinedRooms(limit: Int = 50) async throws -> [JoinedRoomSummary] {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }

        let attendeeSnap = try await db.collectionGroup("attendees")
            .whereField("status", in: [
                AttendeeStatus.ready.rawValue,
                AttendeeStatus.waitingConfirmation.rawValue,
                AttendeeStatus.rejected.rawValue
            ])
            .getDocuments()

        var results: [JoinedRoomSummary] = []
        results.reserveCapacity(attendeeSnap.documents.count)

        for doc in attendeeSnap.documents {
            guard doc.documentID == uid else { continue }
            guard let roomRef = doc.reference.parent.parent else { continue }
            let roomSnap = try await roomRef.getDocument()
            guard let data = roomSnap.data() else { continue }

            let depositHoney = doc.data()["depositHoney"] as? Int ?? 0
            results.append(
                JoinedRoomSummary(
                    id: roomRef.documentID,
                    title: (data["title"] as? String) ?? "Untitled Room",
                    joinedCount: (data["joinedCount"] as? Int) ?? 0,
                    maxPlayers: (data["maxPlayers"] as? Int) ?? 10,
                    depositHoney: depositHoney,
                    updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue()
                )
            )
        }

        return results
            .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
            .prefix(limit)
            .map { $0 }
    }
}
