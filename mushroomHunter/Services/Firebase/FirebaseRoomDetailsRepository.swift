//
//  FirebaseRoomDetailsRepository.swift
//  mushroomHunter
//
//  Created by Ken on 4/2/2026.
//

import Foundation
import FirebaseFirestore

final class FirebaseRoomDetailsRepository {
    private let db = Firestore.firestore()

    func fetchRoom(roomId: String) async throws -> RoomDetail {
        let snap = try await db.collection("rooms").document(roomId).getDocument()

        guard let data = snap.data() else {
            throw NSError(domain: "Room", code: 404, userInfo: [NSLocalizedDescriptionKey: "Room not found"])
        }

        // Required
        let title = data["title"] as? String ?? "Untitled"
        let location = data["location"] as? String ?? ""
        let description = data["description"] as? String ?? ""
        let fixedRaidCost = (data["fixedRaidCost"] as? Int) ?? 10

        // Mushroom target
        let colorRaw = (data["targetColor"] as? String) ?? "All"
        let attrRaw  = (data["targetAttribute"] as? String) ?? "All"
        let sizeRaw  = (data["targetSize"] as? String) ?? "All"

        let target = MushroomTarget(
            color: MushroomColor(rawValue: normalizeTargetRaw(colorRaw)) ?? .All,
            attribute: MushroomAttribute(rawValue: normalizeTargetRaw(attrRaw)) ?? .All,
            size: MushroomSize(rawValue: normalizeTargetRaw(sizeRaw)) ?? .All
        )

        // Meta
        let maxPlayers = data["maxPlayers"] as? Int ?? 10

        let lastRaidAt = (data["lastSuccessfulRaidAt"] as? Timestamp)?.dateValue()

        // attendees will be filled by fetchAttendees()
        return RoomDetail(
            id: snap.documentID,
            title: title,
            location: location,
            description: description,
            targetMushroom: target,
            fixedRaidCost: fixedRaidCost,
            lastSuccessfulRaidAt: lastRaidAt,
            attendees: [],
            maxPlayers: maxPlayers
        )
    }

    func fetchAttendees(roomId: String) async throws -> [RoomAttendee] {
        // Most useful sort: high deposit first
        // (single-field orderBy in a subcollection does NOT require composite index)
        let qs = try await db.collection("rooms")
            .document(roomId)
            .collection("attendees")
            .order(by: "depositHoney", descending: true)
            .getDocuments()

        return qs.documents.map { doc in
            let d = doc.data()
            let name = d["name"] as? String ?? "Unknown"
            let friendCode = d["friendCode"] as? String ?? ""
            let stars = d["stars"] as? Int ?? 0
            let deposit = (d["depositHoney"] as? Int) ?? 0
            let joinedAt = (d["joinedAt"] as? Timestamp)?.dateValue()
            let statusRaw = (d["status"] as? String) ?? AttendeeStatus.ready.rawValue
            let status = AttendeeStatus(rawValue: statusRaw) ?? .ready

            return RoomAttendee(
                id: doc.documentID,
                name: name,
                friendCode: friendCode,
                stars: stars,
                depositHoney: deposit,
                joinedAt: joinedAt,
                status: status
            )
        }
    }

    private func normalizeTargetRaw(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
    }

}
