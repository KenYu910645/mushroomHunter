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
}

final class FirebaseHostRepository {
    private let db = Firestore.firestore()

    func createRoom(req: FirestoreRoomCreateRequest, hostName: String, hostStars: Int) async throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
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
            "status": "open",
            "maxPlayers": 10,
            "joinedCount": 0,
            "createdAt": now,
            "updatedAt": now
            // "lastSuccessfulRaidAt": FieldValue.delete() 
        ]

        try await ref.setData(data)
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
            "updatedAt": now
        ]

        try await ref.updateData(data)
    }
}
