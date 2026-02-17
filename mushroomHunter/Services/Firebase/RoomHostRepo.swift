//
//  RoomHostRepo.swift
//  mushroomHunter
//
//  Purpose:
//  - Contains Firestore create/update operations for hosted room lifecycle.
//
//  Defined in this file:
//  - Room host request models and Firebase room host repository methods.
//
import Foundation
import FirebaseFirestore
import FirebaseAuth

struct FirestoreRoomCreateRequest {
    let title: String
    let location: String
    let description: String
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
    private let defaultMaxHostRooms = AppConfig.Mushroom.defaultHostRoomLimit
    private let defaultMaxJoinRooms = AppConfig.Mushroom.defaultJoinRoomLimit

    func createRoom(req: FirestoreRoomCreateRequest, hostName: String, hostStars: Int) async throws -> String { // Handles createRoom flow.
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }

        let userSnap = try await db.collection("users").document(uid).getDocument()
        let maxHostRooms = userSnap.data()?["maxHostRoom"] as? Int ?? defaultMaxHostRooms

        let existingSnap = try await db.collectionGroup("attendees")
            .whereField("status", isEqualTo: AttendeeStatus.host.rawValue)
            .getDocuments()
        let existing = existingSnap.documents.filter { $0.documentID == uid }

        if existing.count >= maxHostRooms {
            throw HostRoomError.maxHostRoomsReached(maxHostRooms)
        }

        let ref = db.collection("rooms").document()
        let now = Timestamp(date: Date())

        let data: [String: Any] = [
            "title": req.title,
            "hostName": hostName,
            "hostStars": hostStars,
            "location": req.location,
            "description": req.description,
            "fixedRaidCost": max(AppConfig.Mushroom.minFixedRaidCost, req.fixedRaidCost),
            "maxPlayers": AppConfig.Mushroom.defaultMaxPlayersPerRoom,
            "joinedCount": 1,
            "createdAt": now,
            "updatedAt": now
            // "lastSuccessfulRaidAt": FieldValue.delete() 
        ]

        let hostAttendeeRef = ref.collection("attendees").document(uid)
        let attendeeData: [String: Any] = [
            "uid": uid,
            "name": hostName,
            "friendCode": req.hostFriendCode,
            "stars": hostStars,
            "depositHoney": 0,
            "status": AttendeeStatus.host.rawValue,
            "joinedAt": now,
            "updatedAt": now
        ]

        let batch = db.batch()
        batch.setData(data, forDocument: ref)
        batch.setData(attendeeData, forDocument: hostAttendeeRef)
        try await batch.commit()
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

    func updateRoom(roomId: String, req: FirestoreRoomCreateRequest) async throws { // Handles updateRoom flow.
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }

        let ref = db.collection("rooms").document(roomId)
        let hostRef = ref.collection("attendees").document(uid)
        let hostSnap = try await hostRef.getDocument()
        let hostStatus = hostSnap.data()?["status"] as? String
        guard hostStatus == AttendeeStatus.host.rawValue else {
            throw NSError(domain: "Room", code: 403, userInfo: [NSLocalizedDescriptionKey: "Only host can edit this room"])
        }

        let now = Timestamp(date: Date())

        let data: [String: Any] = [
            "title": req.title,
            "location": req.location,
            "description": req.description,
            "fixedRaidCost": max(AppConfig.Mushroom.minFixedRaidCost, req.fixedRaidCost),
            "updatedAt": now
        ]

        try await ref.updateData(data)
    }
}
