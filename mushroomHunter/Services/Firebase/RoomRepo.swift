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

    func fetchAttendees(roomId: String) async throws -> [RoomAttendee] { // Handles fetchAttendees flow.
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

        return qs.documents.map { doc in
            let d = doc.data()
            let name = d["name"] as? String ?? "Unknown"
            let friendCode = d["friendCode"] as? String ?? ""
            let stars = d["stars"] as? Int ?? 0
            let deposit = (d["depositHoney"] as? Int) ?? 0
            let joinGreetingMessage = (d["joinGreetingMessage"] as? String) ?? ""
            let joinedAt = (d["joinedAt"] as? Timestamp)?.dateValue()
            let statusRaw = (d["status"] as? String) ?? AttendeeStatus.ready.rawValue
            let status = AttendeeStatus(rawValue: statusRaw) ?? .ready
            let isHostRatingRequired = (d["isHostRatingRequired"] as? Bool) ?? (d["needsHostRating"] as? Bool) ?? false
            let pendingConfirmationRequestsRaw = d["pendingConfirmationRequests"] as? [String: Any] ?? [:]
            let pendingConfirmationRequests = pendingConfirmationRequestsRaw.reduce(into: [String: Date]()) { partialResult, entry in
                if let timestamp = entry.value as? Timestamp {
                    partialResult[entry.key] = timestamp.dateValue()
                }
            }

            return RoomAttendee(
                id: doc.documentID,
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
