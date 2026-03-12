//
//  RoomFormRepo.swift
//  mushroomHunter
//
//  Purpose:
//  - Repository for room create/edit form flow.
//
//  Related flow:
//  - Mushroom tab -> host create room / edit room form submit.
//
//  Field access legend:
//  [R] Represent Read
//  [X] Represent dont care
//  [W] Represent write
//
//  Room document (`rooms/{roomId}`):
//  [X] - `documentId`: Uses generated id from Firestore reference; does not read/write id field.
//  [W] - `title`: Writes room title from form input on create/edit.
//  [X] - `roomTitle` (legacy fallback): Legacy field is not used in form write path.
//  [W] - `hostUid`: Writes cached host uid on create for host lookups without attendee query.
//  [W] - `location`: Writes location string from form input on create/edit.
//  [W] - `description`: Writes room description from form input on create/edit.
//  [W] - `fixedRaidCost`: Writes legacy compatibility reward value on create/edit.
//  [W] - `maxPlayers`: Writes default max player cap on create.
//  [W] - `joinedCount`: Writes initial joined count (`1`) on create.
//  [W] - `createdAt`: Writes create timestamp when creating room.
//  [W] - `updatedAt`: Writes update timestamp on create/edit.
//  [X] - `lastSuccessfulRaidAt`: Not touched by form flow.
//  [X] - `mushroomType`: Not touched by current form flow.
//  [X] - `attribute` (legacy fallback): Not touched by current form flow.
//  [X] - `expiresAt`: Not touched by current form flow.
//
//  Attendee document (`rooms/{roomId}/attendees/{uid}`):
//  [W] - `uid`: Writes host uid when creating host attendee row.
//  [W] - `name`: Writes host name when creating host attendee row.
//  [W] - `friendCode`: Writes host friend code when creating host attendee row.
//  [W] - `stars`: Writes host stars when creating host attendee row.
//  [W] - `depositHoney`: Writes initial host deposit (`0`) on create.
//  [W] - `status`: Reads host `status` for edit authorization and writes host status on create.
//  [W] - `joinedAt`: Writes host joined timestamp on create.
//  [W] - `updatedAt`: Writes attendee update timestamp on create.
//  [X] - `needsHostRating`: Not touched by form flow.
//  [X] - `attendeeRatedHost`: Not touched by form flow.
//  [X] - `hostRatedAttendee`: Not touched by form flow.
//
import Foundation
import FirebaseFirestore
import FirebaseAuth

struct FsRoomFormRequest {
    let title: String
    let location: String
    let description: String
    let hostFriendCode: String
}

enum RoomFormError: LocalizedError {
    case maxHostRoomsReached(Int)

    var errorDescription: String? {
        switch self {
        case .maxHostRoomsReached(let limit):
            return String(
                format: NSLocalizedString("host_limit_message_format", comment: ""),
                limit
            )
        }
    }
}

final class FbRoomFormRepo {
    private let db = Firestore.firestore()
    private let defaultMaxHostRooms = AppConfig.Mushroom.defaultHostRoomLimit
    private let defaultMaxJoinRooms = AppConfig.Mushroom.defaultJoinRoomLimit

    /// Resolves the effective host-room limit from one user document snapshot.
    /// - Parameter userData: Raw Firestore user document payload.
    /// - Returns: Effective host-room limit for the current entitlement state.
    private func effectiveMaxHostRooms(from userData: [String: Any]) -> Int {
        let isPremium = userData["isPremium"] as? Bool ?? false
        let premiumExpirationDate = (userData["premiumExpirationAt"] as? Timestamp)?.dateValue()
        let isPremiumActive = isPremium && (premiumExpirationDate?.timeIntervalSinceNow ?? -1) > 0
        if isPremiumActive {
            return AppConfig.Premium.premiumHostRoomLimit
        }
        return userData["maxHostRoom"] as? Int ?? defaultMaxHostRooms
    }

    func createRoom(req: FsRoomFormRequest, hostDisplayName: String, hostStars: Int) async throws -> String { // Handles createRoom flow.
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }

        let userSnap = try await db.collection("users").document(uid).getDocument()
        let userData = userSnap.data() ?? [:]
        let maxHostRooms = effectiveMaxHostRooms(from: userData)
        let hostFcmToken = (userData["fcmToken"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        let hostedRoomsSnap = try await db.collection("rooms")
            .whereField("hostUid", isEqualTo: uid)
            .limit(to: maxHostRooms)
            .getDocuments()
        var hostedRoomIds = Set(hostedRoomsSnap.documents.map(\.documentID))

        if hostedRoomIds.count >= maxHostRooms {
            throw RoomFormError.maxHostRoomsReached(maxHostRooms)
        }

        let ref = db.collection("rooms").document()
        let now = Timestamp(date: Date())

        let data: [String: Any] = [
            "title": req.title,
            "hostUid": uid,
            "hostFcmToken": hostFcmToken,
            "location": req.location,
            "description": req.description,
            "fixedRaidCost": AppConfig.Mushroom.joinedSuccessRewardHoney,
            "maxPlayers": AppConfig.Mushroom.defaultMaxPlayersPerRoom,
            "joinedCount": 1,
            "createdAt": now,
            "updatedAt": now
            // "lastSuccessfulRaidAt": FieldValue.delete() 
        ]

        let hostAttendeeRef = ref.collection("attendees").document(uid)
        let attendeeData: [String: Any] = [
            "uid": uid,
            "fcmToken": hostFcmToken,
            "name": hostDisplayName,
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
                "displayName": hostDisplayName,
                "isProfileComplete": true,
                "stars": hostStars,
                "honey": 0,
                "maxHostRoom": defaultMaxHostRooms,
                "maxJoinRoom": defaultMaxJoinRooms,
                "isPremium": false,
                "premiumProductId": "",
                "createdAt": now,
                "updatedAt": now
            ], merge: true)
        }
        return ref.documentID
    }

    func updateRoom(roomId: String, req: FsRoomFormRequest) async throws { // Handles updateRoom flow.
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
            "fixedRaidCost": AppConfig.Mushroom.joinedSuccessRewardHoney,
            "updatedAt": now
        ]

        try await ref.updateData(data)
    }
}
