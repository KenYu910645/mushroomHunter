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

        let attendeeDocs = try await fetchAttendeeDocs(
            uid: uid,
            statusFilter: .equal(AttendeeStatus.host.rawValue)
        )
        let roomMap = try await fetchRoomDataMap(roomIds: attendeeDocs.compactMap { $0.reference.parent.parent?.documentID })

        var results: [HostedRoomSummary] = []
        results.reserveCapacity(attendeeDocs.count)

        for doc in attendeeDocs {
            guard let roomRef = doc.reference.parent.parent else { continue }
            guard let d = roomMap[roomRef.documentID] else { continue }

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

        let attendeeDocs = try await fetchAttendeeDocs(
            uid: uid,
            statusFilter: .inList([
                AttendeeStatus.ready.rawValue,
                AttendeeStatus.waitingConfirmation.rawValue,
                AttendeeStatus.rejected.rawValue
            ])
        )
        let roomMap = try await fetchRoomDataMap(roomIds: attendeeDocs.compactMap { $0.reference.parent.parent?.documentID })

        var results: [JoinedRoomSummary] = []
        results.reserveCapacity(attendeeDocs.count)

        for doc in attendeeDocs {
            guard let roomRef = doc.reference.parent.parent else { continue }
            guard let data = roomMap[roomRef.documentID] else { continue }

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

    private enum StatusFilter {
        case equal(String)
        case inList([String])
    }

    private func fetchAttendeeDocs(
        uid: String,
        statusFilter: StatusFilter
    ) async throws -> [QueryDocumentSnapshot] {
        let attendeeGroup = db.collectionGroup("attendees")
        let byUidQuery = applyStatusFilter(
            to: attendeeGroup.whereField("uid", isEqualTo: uid),
            statusFilter: statusFilter
        )
        let byStatusQuery = applyStatusFilter(to: attendeeGroup, statusFilter: statusFilter)

        async let byUidSnap = fetchDocuments(query: byUidQuery)
        async let byStatusSnap = fetchDocuments(query: byStatusQuery)
        let (uidDocs, statusDocs) = try await (byUidSnap, byStatusSnap)
        let legacyDocs = statusDocs.filter { $0.documentID == uid }

        var merged: [String: QueryDocumentSnapshot] = [:]
        merged.reserveCapacity(uidDocs.count + legacyDocs.count)
        for doc in uidDocs + legacyDocs {
            merged[doc.reference.path] = doc
        }

        return Array(merged.values)
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
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
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
