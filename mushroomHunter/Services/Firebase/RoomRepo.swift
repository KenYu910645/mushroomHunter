//
//  RoomRepo.swift
//  mushroomHunter
//
//  Purpose:
//  - Repository for room detail screen load flow.
//
//  Related flow:
//  - Open room from browse/deep link -> load room detail + attendee list.
//
//  Field access legend:
//  [R] Represent Read
//  [X] Represent dont care
//  [W] Represent write
//
//  Room document (`rooms/{roomId}`):
//  [R] - `documentId`: Reads room document id and maps it to `RoomDetail.id`.
//  [R] - `title`: Reads room title for detail header.
//  [X] - `roomTitle` (legacy fallback): Detail repo does not use legacy title key.
//  [X] - `hostName`: Detail repo does not map host name from room document.
//  [X] - `hostStars`: Detail repo does not map host stars from room document.
//  [R] - `location`: Reads room location for detail display.
//  [R] - `description`: Reads room description for detail display.
//  [R] - `fixedRaidCost`: Reads legacy compatibility reward field; active validations use global app config instead.
//  [R] - `maxPlayers`: Reads max player cap for detail occupancy logic.
//  [X] - `joinedCount`: Not used because attendee count is derived from attendee list.
//  [X] - `createdAt`: Not used by detail mapping.
//  [X] - `updatedAt`: Not used by detail mapping.
//  [R] - `lastSuccessfulRaidAt`: Reads last raid timestamp for detail status.
//  [R] - `raidConfirmationHistory`: Reads host raid-confirmation history snapshots.
//  [X] - `mushroomType`: Detail repo does not map browse-only mushroom type field.
//  [X] - `attribute` (legacy fallback): Detail repo does not use legacy attribute key.
//  [X] - `expiresAt`: Not used by detail mapping.
//
//  Attendee document (`rooms/{roomId}/attendees/{uid}`):
//  [X] - `uid`: Uses attendee document id instead of `uid` field for `RoomAttendee.id`.
//  [R] - `name`: Reads attendee display name for attendee rows.
//  [R] - `friendCode`: Reads attendee friend code for attendee rows.
//  [R] - `stars`: Reads attendee stars for attendee rows.
//  [R] - `depositHoney`: Reads attendee deposit and uses it for sort order.
//  [R] - `joinGreetingMessage`: Reads attendee join greeting for host review.
//  [R] - `status`: Reads attendee status for role/confirmation UI.
//  [R] - `joinedAt`: Reads join timestamp for attendee metadata.
//  [X] - `updatedAt`: Not mapped by detail repo.
//  [R] - `isHostRatingRequired`: Reads host-rating pending flag for detail actions.
//  [X] - `attendeeRatedHost`: Not mapped by detail repo.
//  [X] - `hostRatedAttendee`: Not mapped by detail repo.
//  [R] - `pendingConfirmationRequests`: Reads joiner pending confirmation queue for room detail confirmation UI.
//
import Foundation
import FirebaseAuth
import FirebaseFirestore

final class FbRoomRepo {
    private let db = Firestore.firestore()

    /// Decodes one attendee document snapshot into the room attendee model used by detail UI.
    /// - Parameter document: Firestore attendee snapshot from `rooms/{roomId}/attendees/{uid}`.
    /// - Returns: Decoded attendee row with defensive fallbacks for legacy fields.
    private func decodeAttendee(document: QueryDocumentSnapshot) -> RoomAttendee {
        let data = document.data()
        let name = data["name"] as? String ?? "Unknown"
        let friendCode = data["friendCode"] as? String ?? ""
        let stars = data["stars"] as? Int ?? 0
        let deposit = (data["depositHoney"] as? Int) ?? 0
        let joinGreetingMessage = (data["joinGreetingMessage"] as? String) ?? ""
        let joinedAt = (data["joinedAt"] as? Timestamp)?.dateValue()
        let statusRaw = (data["status"] as? String) ?? AttendeeStatus.ready.rawValue
        let status = AttendeeStatus(rawValue: statusRaw) ?? .ready
        let isHostRatingRequired = (data["isHostRatingRequired"] as? Bool) ?? (data["needsHostRating"] as? Bool) ?? false
        let pendingConfirmationRequestsRaw = data["pendingConfirmationRequests"] as? [String: Any] ?? [:]
        let pendingConfirmationRequests = pendingConfirmationRequestsRaw.reduce(into: [String: Date]()) { partialResult, entry in
            if let timestamp = entry.value as? Timestamp {
                partialResult[entry.key] = timestamp.dateValue()
            }
        }

        return RoomAttendee(
            id: document.documentID,
            name: name,
            friendCode: friendCode,
            stars: stars,
            depositHoney: deposit,
            joinGreetingMessage: joinGreetingMessage,
            joinedAt: joinedAt,
            status: status,
            isHostRatingRequired: isHostRatingRequired,
            pendingConfirmationRequests: pendingConfirmationRequests
        )
    }

    /// Resolves latest profile stars for attendee ids from `users/{uid}` so forced refresh can bypass stale room snapshots.
    /// - Parameters:
    ///   - attendeeIds: Room attendee document ids that also match profile user ids.
    ///   - isForcingServer: True when pull-to-refresh requires server-authoritative stars.
    /// - Returns: Dictionary keyed by attendee uid with the latest non-negative user stars.
    private func fetchLatestUserStarsByAttendeeId(
        attendeeIds: [String],
        isForcingServer: Bool
    ) async throws -> [String: Int] {
        let uniqueAttendeeIds = Array(Set(attendeeIds.filter { $0.isEmpty == false }))
        guard uniqueAttendeeIds.isEmpty == false else { return [:] }

        var starsByAttendeeId: [String: Int] = [:]
        for attendeeIdChunk in uniqueAttendeeIds.chunked(into: 10) {
            let query = db.collection("users")
                .whereField(FieldPath.documentID(), in: attendeeIdChunk)
            let snapshot: QuerySnapshot
            if isForcingServer {
                snapshot = try await query.getDocuments(source: .server)
            } else {
                do {
                    snapshot = try await query.getDocuments(source: .server)
                } catch {
                    snapshot = try await query.getDocuments(source: .default)
                }
            }

            for document in snapshot.documents {
                let starsValue = document.data()["stars"] as? Int ?? 0
                starsByAttendeeId[document.documentID] = max(0, starsValue)
            }
        }

        return starsByAttendeeId
    }

    func fetchRoom(roomId: String) async throws -> RoomDetail { // Handles fetchRoom flow.
        let ref = db.collection("rooms").document(roomId)
        let snap: DocumentSnapshot
        do {
            snap = try await ref.getDocument(source: .server)
        } catch {
            snap = try await ref.getDocument(source: .default)
        }

        guard let data = snap.data() else {
            throw NSError(domain: "Room", code: 404, userInfo: [NSLocalizedDescriptionKey: "Room not found"])
        }

        // Required
        let title = data["title"] as? String ?? "Untitled"
        let location = data["location"] as? String ?? ""
        let description = data["description"] as? String ?? ""
        let fixedRaidCost = AppConfig.Mushroom.minimumRequiredDepositHoney

        // Meta
        let maxPlayers = data["maxPlayers"] as? Int ?? AppConfig.Mushroom.defaultMaxPlayersPerRoom

        let lastRaidAt = (data["lastSuccessfulRaidAt"] as? Timestamp)?.dateValue()
        let raidHistoryRaw = data["raidConfirmationHistory"] as? [[String: Any]] ?? []
        let raidConfirmationHistory: [RoomRaidConfirmationRecord] = raidHistoryRaw.compactMap { entry -> RoomRaidConfirmationRecord? in
            guard
                let confirmationId = entry["id"] as? String,
                let requestedAt = (entry["requestedAt"] as? Timestamp)?.dateValue()
            else {
                return nil
            }
            let attendeeResultsRaw = entry["attendeeResults"] as? [[String: Any]] ?? []
            let attendeeResults: [RoomRaidConfirmationAttendeeResult] = attendeeResultsRaw.compactMap { attendeeResult -> RoomRaidConfirmationAttendeeResult? in
                guard
                    let attendeeId = attendeeResult["uid"] as? String,
                    let attendeeName = attendeeResult["name"] as? String,
                    let statusRaw = attendeeResult["status"] as? String,
                    let status = RoomRaidConfirmationAttendeeStatus(rawValue: statusRaw)
                else {
                    return nil
                }
                return RoomRaidConfirmationAttendeeResult(
                    id: attendeeId,
                    name: attendeeName,
                    status: status
                )
            }
            return RoomRaidConfirmationRecord(
                id: confirmationId,
                requestedAt: requestedAt,
                attendeeResults: attendeeResults
            )
        }.sorted(by: { (lhs: RoomRaidConfirmationRecord, rhs: RoomRaidConfirmationRecord) in
            lhs.requestedAt > rhs.requestedAt
        })

        // attendees will be filled by fetchAttendees()
        return RoomDetail(
            id: snap.documentID,
            title: title,
            location: location,
            description: description,
            targetMushroom: MushroomTarget(color: .All, attribute: .All, size: .All),
            fixedRaidCost: fixedRaidCost,
            lastSuccessfulRaidAt: lastRaidAt,
            raidConfirmationHistory: raidConfirmationHistory,
            attendees: [],
            maxPlayers: maxPlayers
        )
    }

    func fetchAttendees(
        roomId: String,
        isHydratingLatestUserStars: Bool = false
    ) async throws -> [RoomAttendee] { // Handles fetchAttendees flow.
        // Most useful sort: high deposit first
        // (single-field orderBy in a subcollection does NOT require composite index)
        let query = db.collection("rooms")
            .document(roomId)
            .collection("attendees")
            .order(by: "depositHoney", descending: true)

        let qs: QuerySnapshot
        do {
            qs = try await query.getDocuments(source: .server)
        } catch {
            qs = try await query.getDocuments(source: .default)
        }

        var attendees = qs.documents.map(decodeAttendee)
        if isHydratingLatestUserStars {
            let latestStarsByAttendeeId = try await fetchLatestUserStarsByAttendeeId(
                attendeeIds: attendees.map(\.id),
                isForcingServer: true
            )
            attendees = attendees.map { attendee in
                var hydratedAttendee = attendee
                if let latestStars = latestStarsByAttendeeId[attendee.id] {
                    hydratedAttendee.stars = latestStars
                }
                return hydratedAttendee
            }
        }
        return attendees
    }

    /// Starts a live Firestore listener for attendee rows inside one room.
    /// - Parameters:
    ///   - roomId: Parent room id.
    ///   - onUpdate: Callback invoked with the latest decoded attendee rows.
    /// - Returns: Listener registration that must be removed when the room screen disappears.
    func observeAttendees(
        roomId: String,
        onUpdate: @escaping ([RoomAttendee]) -> Void
    ) -> ListenerRegistration {
        db.collection("rooms")
            .document(roomId)
            .collection("attendees")
            .order(by: "depositHoney", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                guard error == nil else { return }
                guard let snapshot else { return }
                onUpdate(snapshot.documents.map(self.decodeAttendee))
            }
    }

    /// Loads pending room rating tasks for the current user inside one room.
    /// - Parameter roomId: Room currently open in detail UI.
    /// - Returns: Pending room rating tasks sorted newest first.
    func fetchPendingRoomRatingTasks(roomId: String) async throws -> [RoomRatingTask] {
        guard let uid = Auth.auth().currentUser?.uid else { return [] }

        let query = db.collection("roomRatingTasks")
            .whereField("roomId", isEqualTo: roomId)
            .whereField("raterUid", isEqualTo: uid)
            .whereField("status", isEqualTo: RoomRatingTaskStatus.pending.rawValue)

        let snapshot: QuerySnapshot
        do {
            snapshot = try await query.getDocuments(source: .server)
        } catch {
            snapshot = try await query.getDocuments(source: .default)
        }

        return snapshot.documents.compactMap { document in
            let data = document.data()
            let confirmationId = (data["confirmationId"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let requestedAt = (data["requestedAt"] as? Timestamp)?.dateValue() ?? .distantPast
            let rateeUid = (data["rateeUid"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let counterpartName = (data["counterpartName"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let directionRaw = (data["direction"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let outcomeRaw = (data["settlementOutcome"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let statusRaw = (data["status"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard confirmationId.isEmpty == false,
                  rateeUid.isEmpty == false,
                  let direction = RoomRatingDirection(rawValue: directionRaw),
                  let settlementOutcome = RaidSettlementOutcome(rawValue: outcomeRaw),
                  let status = RoomRatingTaskStatus(rawValue: statusRaw) else {
                return nil
            }
            return RoomRatingTask(
                id: document.documentID,
                roomId: roomId,
                confirmationId: confirmationId,
                requestedAt: requestedAt,
                rateeUid: rateeUid,
                counterpartName: counterpartName.isEmpty ? "Player" : counterpartName,
                direction: direction,
                settlementOutcome: settlementOutcome,
                status: status
            )
        }
        .sorted { lhs, rhs in
            lhs.requestedAt > rhs.requestedAt
        }
    }

}

private extension Array {
    /// Splits an array into fixed-size chunks for Firestore `in` query limits.
    /// - Parameter size: Maximum number of items per chunk.
    /// - Returns: Ordered chunk slices preserving the original element order.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0, isEmpty == false else { return isEmpty ? [] : [self] }
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
