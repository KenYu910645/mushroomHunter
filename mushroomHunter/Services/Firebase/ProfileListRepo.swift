//
//  ProfileListRepo.swift
//  mushroomHunter
//
//  Purpose:
//  - Repository for profile-hosted/profile-joined room summary queries.
//
//  Related flow:
//  - Profile tab -> hosted rooms list and joined rooms list.
//
//  Field access legend:
//  [R] Represent Read
//  [X] Represent dont care
//  [W] Represent write
//
//  Room document (`rooms/{roomId}`):
//  [R] - `documentId`: Reads room id for summary identity.
//  [R] - `title`: Reads room title for hosted/joined summaries.
//  [R] - `joinedCount`: Reads occupancy for hosted/joined summaries.
//  [R] - `maxPlayers`: Reads player cap for hosted/joined summaries.
//  [R] - `createdAt`: Reads sort key for hosted room list.
//  [R] - `updatedAt`: Reads sort key for joined room list.
//  [X] - `location`: Not required for current profile room summaries.
//  [X] - `description`: Not required for current profile room summaries.
//  [X] - `fixedRaidCost`: Not required for current profile room summaries.
//  [X] - `mushroomType`: Not required for current profile room summaries.
//  [X] - `lastSuccessfulRaidAt`: Not required for current profile room summaries.
//
//  Attendee document (`rooms/{roomId}/attendees/{uid}`):
//  [R] - `uid`: Reads by `uid` field and legacy document-id fallback for current user matching.
//  [R] - `status`: Reads to split hosted (`host`) and joined (`askingToJoin`/`ready`/`notEnoughHoney`/`waitingConfirmation`) lists.
//  [R] - `depositHoney`: Reads for joined-room summary display.
//  [X] - `name`: Not required for current profile room summaries.
//  [X] - `friendCode`: Not required for current profile room summaries.
//  [X] - `stars`: Not required for current profile room summaries.
//  [X] - `joinedAt`: Not required for current profile room summaries.
//  [X] - `updatedAt`: Not required from attendee row (room `updatedAt` is used).
//  [X] - `needsHostRating`: Not required for current profile room summaries.
//  [X] - `attendeeRatedHost`: Not required for current profile room summaries.
//  [X] - `hostRatedAttendee`: Not required for current profile room summaries.
//
import Foundation
import FirebaseFirestore
import FirebaseAuth

struct HostedRoomSummary: Identifiable, Hashable, Codable {
    let id: String          // Firestore docID
    let title: String
    let joinedCount: Int
    let maxPlayers: Int
    let roomStatus: HostedRoomStatus
    let createdAt: Date?
}

enum HostedRoomStatus: String, Hashable, Codable {
    case ready
    case waitingForPlayers
    case waitingConfirmation
}

struct JoinedRoomSummary: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let joinedCount: Int
    let maxPlayers: Int
    let depositHoney: Int
    let attendeeStatus: AttendeeStatus
    let updatedAt: Date?
}

final class FbProfileListRepo {
    private let db = Firestore.firestore()

    func fetchMyHostedRooms(limit: Int = AppConfig.Mushroom.profileListFetchLimit) async throws -> [HostedRoomSummary] { // Handles fetchMyHostedRooms flow.
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }

        let hostRoomQuery = db.collection("rooms")
            .whereField("hostUid", isEqualTo: uid)
        let hostRoomDocs = try await fetchDocuments(query: hostRoomQuery)
        var roomMap: [String: [String: Any]] = [:]
        roomMap.reserveCapacity(hostRoomDocs.count)
        for doc in hostRoomDocs {
            roomMap[doc.documentID] = doc.data()
        }

        if roomMap.count < limit {
            let attendeeDocs = try await fetchAttendeeDocs(
                uid: uid,
                statusFilter: .equal(AttendeeStatus.host.rawValue),
                desiredCount: limit
            )
            let attendeeRoomIds = attendeeDocs.compactMap { $0.reference.parent.parent?.documentID }
            let missingRoomIds = attendeeRoomIds.filter { roomMap[$0] == nil }
            if !missingRoomIds.isEmpty {
                let legacyRoomMap = try await fetchRoomDataMap(roomIds: missingRoomIds)
                for (roomId, roomData) in legacyRoomMap {
                    roomMap[roomId] = roomData
                }
            }
        }

        var baseResults: [HostedRoomSummary] = []
        baseResults.reserveCapacity(roomMap.count)
        for (roomId, d) in roomMap {
            baseResults.append(
                HostedRoomSummary(
                    id: roomId,
                    title: (d["title"] as? String) ?? "Untitled Room",
                    joinedCount: (d["joinedCount"] as? Int) ?? 0,
                    maxPlayers: (d["maxPlayers"] as? Int) ?? AppConfig.Mushroom.defaultMaxPlayersPerRoom,
                    roomStatus: .waitingForPlayers,
                    createdAt: (d["createdAt"] as? Timestamp)?.dateValue()
                )
            )
        }

        let sortedBaseResults = baseResults
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            .prefix(limit)
            .map { $0 }

        var finalResults: [HostedRoomSummary] = []
        finalResults.reserveCapacity(sortedBaseResults.count)
        for room in sortedBaseResults {
            let roomStatus = try await fetchHostedRoomStatus(roomId: room.id)
            finalResults.append(
                HostedRoomSummary(
                    id: room.id,
                    title: room.title,
                    joinedCount: room.joinedCount,
                    maxPlayers: room.maxPlayers,
                    roomStatus: roomStatus,
                    createdAt: room.createdAt
                )
            )
        }

        return finalResults
    }

    func fetchMyJoinedRooms(limit: Int = AppConfig.Mushroom.profileListFetchLimit) async throws -> [JoinedRoomSummary] { // Handles fetchMyJoinedRooms flow.
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }

        let attendeeDocs = try await fetchAttendeeDocs(
            uid: uid,
            statusFilter: .inList([
                AttendeeStatus.askingToJoin.rawValue,
                AttendeeStatus.ready.rawValue,
                AttendeeStatus.notEnoughHoney.rawValue,
                AttendeeStatus.waitingConfirmation.rawValue
            ]),
            desiredCount: limit
        )
        let roomMap = try await fetchRoomDataMap(roomIds: attendeeDocs.compactMap { $0.reference.parent.parent?.documentID })

        var results: [JoinedRoomSummary] = []
        results.reserveCapacity(attendeeDocs.count)

        for doc in attendeeDocs {
            guard let roomRef = doc.reference.parent.parent else { continue }
            guard let data = roomMap[roomRef.documentID] else { continue }

            let depositHoney = doc.data()["depositHoney"] as? Int ?? 0
            let rawAttendeeStatus = (doc.data()["status"] as? String) ?? AttendeeStatus.ready.rawValue
            let attendeeStatus = AttendeeStatus(rawValue: rawAttendeeStatus) ?? .ready
            results.append(
                JoinedRoomSummary(
                    id: roomRef.documentID,
                    title: (data["title"] as? String) ?? "Untitled Room",
                    joinedCount: (data["joinedCount"] as? Int) ?? 0,
                    maxPlayers: (data["maxPlayers"] as? Int) ?? AppConfig.Mushroom.defaultMaxPlayersPerRoom,
                    depositHoney: depositHoney,
                    attendeeStatus: attendeeStatus,
                    updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue()
                )
            )
        }

        return results
            .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
            .prefix(limit)
            .map { $0 }
    }

    /// Loads pending join-request counts for each hosted room id.
    /// - Parameter roomIds: Hosted room document ids owned by current host.
    /// - Returns: Dictionary keyed by room id with attendee counts in `AskingToJoin`.
    func fetchHostPendingJoinRequestCounts(roomIds: [String]) async throws -> [String: Int] {
        let uniqueRoomIds = Array(Set(roomIds.filter { !$0.isEmpty }))
        guard uniqueRoomIds.isEmpty == false else { return [:] }

        var pendingCountByRoomId: [String: Int] = [:]
        pendingCountByRoomId.reserveCapacity(uniqueRoomIds.count)

        for roomId in uniqueRoomIds {
            let query = db.collection("rooms")
                .document(roomId)
                .collection("attendees")
                .whereField("status", isEqualTo: AttendeeStatus.askingToJoin.rawValue)
            let documentCount = try await fetchDocuments(query: query).count
            pendingCountByRoomId[roomId] = documentCount
        }
        return pendingCountByRoomId
    }

    private enum StatusFilter {
        case equal(String)
        case inList([String])
    }

    private func fetchAttendeeDocs(
        uid: String,
        statusFilter: StatusFilter,
        desiredCount: Int
    ) async throws -> [QueryDocumentSnapshot] {
        _ = desiredCount
        let attendeeGroup = db.collectionGroup("attendees")
        let byUidQuery = applyStatusFilter(
            to: attendeeGroup.whereField("uid", isEqualTo: uid),
            statusFilter: statusFilter
        )
        return try await fetchDocuments(query: byUidQuery)
    }

    private func applyStatusFilter(to query: Query, statusFilter: StatusFilter) -> Query {
        switch statusFilter {
        case .equal(let status):
            return query.whereField("status", isEqualTo: status)
        case .inList(let statuses):
            return query.whereField("status", in: statuses)
        }
    }

    private func fetchRoomDataMap(roomIds: [String]) async throws -> [String: [String: Any]] {
        let uniqueRoomIds = Array(Set(roomIds.filter { !$0.isEmpty }))
        guard !uniqueRoomIds.isEmpty else { return [:] }

        var roomDataMap: [String: [String: Any]] = [:]
        for chunk in uniqueRoomIds.chunked(into: 10) {
            let query = db.collection("rooms").whereField(FieldPath.documentID(), in: chunk)
            let snap = try await fetchDocuments(query: query)
            for doc in snap {
                roomDataMap[doc.documentID] = doc.data()
            }
        }
        return roomDataMap
    }

    private func fetchDocuments(query: Query) async throws -> [QueryDocumentSnapshot] {
        do {
            return try await query.getDocuments(source: .server).documents
        } catch {
            return try await query.getDocuments(source: .default).documents
        }
    }

    private func fetchHostedRoomStatus(roomId: String) async throws -> HostedRoomStatus {
        let attendeeRef = db.collection("rooms").document(roomId).collection("attendees")
        let attendeeDocuments: [QueryDocumentSnapshot]
        do {
            attendeeDocuments = try await attendeeRef.getDocuments(source: .server).documents
        } catch {
            attendeeDocuments = try await attendeeRef.getDocuments(source: .default).documents
        }

        let nonHostAttendeeStatuses: [AttendeeStatus] = attendeeDocuments.compactMap { document in
            let rawStatus = document.data()["status"] as? String ?? ""
            let attendeeStatus = AttendeeStatus(rawValue: rawStatus) ?? .ready
            if attendeeStatus == .host { return nil }
            return attendeeStatus
        }

        let isHasAnyNonHostAttendee = !nonHostAttendeeStatuses.isEmpty
        if !isHasAnyNonHostAttendee {
            return .waitingForPlayers
        }

        let isAllWaitingConfirmation = nonHostAttendeeStatuses.allSatisfy { $0 == .waitingConfirmation }
        if isAllWaitingConfirmation {
            return .waitingConfirmation
        }

        // Any room that already has non-host attendees should not show "waiting for players".
        return .ready
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] { // Handles chunked flow.
        guard size > 0, !isEmpty else { return isEmpty ? [] : [self] }
        var chunks: [[Element]] = []
        chunks.reserveCapacity((count + size - 1) / size)
        var index = 0
        while index < count {
            let end = Swift.min(index + size, count)
            chunks.append(Array(self[index..<end]))
            index += size
        }
        return chunks
    }
}
