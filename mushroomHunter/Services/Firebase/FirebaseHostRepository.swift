//
//  FirebaseHostRepository.swift
//  mushroomHunter
//
//  Created by Ken on 4/2/2026.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

struct FirestoreRoomCreateRequest {
    let title: String
    let targetColor: String
    let targetAttribute: String
    let targetSize: String
    let location: String
    let note: String
    let hostFriendCode: String
    let fixedRaidCost: Int
}

enum HostRoomError: LocalizedError {
    case maxHostRoomsReached(Int)

    var errorDescription: String? {
        switch self {
        case .maxHostRoomsReached(let limit):
            return "You can only host up to \(limit) rooms."
        }
    }
}

final class FirebaseHostRepository {
    private let db = Firestore.firestore()
    private let defaultMaxHostRooms = 1
    private let defaultMaxJoinRooms = 3

    func createRoom(req: FirestoreRoomCreateRequest, hostName: String, hostStars: Int) async throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }

        let userSnap = try await db.collection("users").document(uid).getDocument()
        let maxHostRooms = userSnap.data()?["maxHostRoom"] as? Int ?? defaultMaxHostRooms

        let existing = try await db.collection("rooms")
            .whereField("hostUid", isEqualTo: uid)
            .whereField("status", isEqualTo: "open")
            .getDocuments()

        if existing.documents.count >= maxHostRooms {
            throw HostRoomError.maxHostRoomsReached(maxHostRooms)
        }

        let ref = db.collection("rooms").document()
        let now = Timestamp(date: Date())

        let data: [String: Any] = [
            "title": req.title,
            "hostUid": uid,
            "hostName": hostName,
            "hostStars": hostStars,
            "hostFriendCode": req.hostFriendCode,
            "targetColor": req.targetColor,
            "targetAttribute": req.targetAttribute,
            "targetSize": req.targetSize,
            "location": req.location,
            "note": req.note,
            "fixedRaidCost": max(1, req.fixedRaidCost),
            "status": "open",
            "maxPlayers": 10,
            "joinedCount": 0,
            "createdAt": now,
            "updatedAt": now
            // "lastSuccessfulRaidAt": FieldValue.delete() 
        ]

        try await ref.setData(data)
        if !userSnap.exists {
            try await db.collection("users").document(uid).setData([
                "displayName": hostName,
                "stars": hostStars,
                "honey": 0,
                "maxHostRoom": defaultMaxHostRooms,
                "maxJoinRoom": defaultMaxJoinRooms,
                "createdAt": now,
                "updatedAt": now
            ], merge: true)
        }
        return ref.documentID
    }

    func updateRoom(roomId: String, req: FirestoreRoomCreateRequest) async throws {
        guard Auth.auth().currentUser?.uid != nil else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }

        let ref = db.collection("rooms").document(roomId)
        let now = Timestamp(date: Date())

        let data: [String: Any] = [
            "title": req.title,
            "targetColor": req.targetColor,
            "targetAttribute": req.targetAttribute,
            "targetSize": req.targetSize,
            "location": req.location,
            "note": req.note,
            "hostFriendCode": req.hostFriendCode,
            "fixedRaidCost": max(1, req.fixedRaidCost),
            "updatedAt": now
        ]

        try await ref.updateData(data)
    }
}
