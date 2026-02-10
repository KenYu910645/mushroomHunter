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
        let note = data["note"] as? String ?? ""
        let hostUid = data["hostUid"] as? String ?? ""
        let hostName = data["hostName"] as? String ?? "Unknown"
        let hostStars = data["hostStars"] as? Int ?? 0
        let hostFriendCode = data["hostFriendCode"] as? String ?? ""
        let fixedRaidCost = (data["fixedRaidCost"] as? Int)
            ?? (data["minBid"] as? Int)
            ?? 10

        // Mushroom target
        let colorRaw = (data["targetColor"] as? String) ?? "red"
        let attrRaw  = (data["targetAttribute"] as? String) ?? "normal"
        let sizeRaw  = (data["targetSize"] as? String) ?? "normal"

        let target = MushroomTarget(
            color: MushroomColor(rawValue: colorRaw) ?? .Red,
            attribute: MushroomAttribute(rawValue: attrRaw) ?? .Normal,
            size: MushroomSize(rawValue: sizeRaw) ?? .Normal
        )

        // Meta
        let maxPlayers = data["maxPlayers"] as? Int ?? 10

        let statusRaw = (data["status"] as? String) ?? "open"
        let status: RoomStatus = (statusRaw.lowercased() == "closed") ? .closed : .open

        let lastRaidAt = (data["lastSuccessfulRaidAt"] as? Timestamp)?.dateValue()

        // attendees will be filled by fetchAttendees()
        return RoomDetail(
            id: snap.documentID,
            title: title,
            location: location,
            note: note,
            hostUid: hostUid,
            hostName: hostName,
            hostStars: hostStars,
            hostFriendCode: hostFriendCode,
            targetMushroom: target,
            fixedRaidCost: fixedRaidCost,
            lastSuccessfulRaidAt: lastRaidAt,
            attendees: [],
            maxPlayers: maxPlayers,
            status: status
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
            let deposit = (d["depositHoney"] as? Int)
                ?? (d["bidHoney"] as? Int)
                ?? 0
            let joinedAt = (d["joinedAt"] as? Timestamp)?.dateValue()

            return RoomAttendee(
                id: doc.documentID,
                name: name,
                friendCode: friendCode,
                stars: stars,
                depositHoney: deposit,
                joinedAt: joinedAt
            )
        }
    }

    func fetchPendingRaidClaim(roomId: String, attendeeUid: String) async throws -> RaidClaim? {
        let snap = try await db.collection("rooms")
            .document(roomId)
            .collection("raidClaims")
            .document(attendeeUid)
            .getDocument()

        guard let data = snap.data() else { return nil }
        let status = data["status"] as? String ?? ""
        guard status == "pending" else { return nil }

        return RaidClaim(
            id: snap.documentID,
            hostName: data["hostName"] as? String ?? "Host",
            raidCostHoney: (data["raidCostHoney"] as? Int)
                ?? (data["bidHoney"] as? Int)
                ?? 0,
            status: status,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue(),
            expiresAt: (data["expiresAt"] as? Timestamp)?.dateValue()
        )
    }

    func fetchPendingRaidClaimAttendeeIds(roomId: String) async throws -> Set<String> {
        let statuses = try await fetchRaidClaimStatuses(roomId: roomId)
        let ids = statuses.filter { $0.value == "pending" }.map { $0.key }
        return Set(ids)
    }

    func fetchRaidClaimStatuses(roomId: String) async throws -> [String: String] {
        let snap = try await db.collection("rooms")
            .document(roomId)
            .collection("raidClaims")
            .getDocuments()

        var result: [String: String] = [:]
        result.reserveCapacity(snap.documents.count)
        for doc in snap.documents {
            let status = (doc.data()["status"] as? String) ?? ""
            if !status.isEmpty {
                result[doc.documentID] = status
            }
        }
        return result
    }
}
