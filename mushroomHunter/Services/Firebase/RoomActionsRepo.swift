//
//  RoomActionsRepo.swift
//  mushroomHunter
//
//  Purpose:
//  - Repository for transactional room action flows.
//
//  Related flow:
//  - Room detail actions: join, leave, deposit update, kick, close, finish raid,
//    attendee confirmation response, repeated confirmation requests, host/attendee rating.
//
//  Field access legend:
//  [R] Represent Read
//  [X] Represent dont care
//  [W] Represent write
//
//  Room document (`rooms/{roomId}`):
//  [R] - `documentId`: Uses room id to locate transaction targets.
//  [X] - `title`: Not used by actions logic.
//  [X] - `roomTitle` (legacy fallback): Not used by actions logic.
//  [X] - `hostName`: Not used by actions logic.
//  [X] - `hostStars`: Not used by actions logic.
//  [X] - `location`: Not used by actions logic.
//  [X] - `description`: Not used by actions logic.
//  [W] - `fixedRaidCost`: Reads/writes legacy compatibility room reward value but does not drive active settlement policy.
//  [R] - `maxPlayers`: Reads to enforce room capacity during join.
//  [W] - `joinedCount`: Updates when joining, leaving, kicking, and closing.
//  [X] - `createdAt`: Not used by actions logic.
//  [W] - `updatedAt`: Updates timestamp on every room mutation.
//  [W] - `lastSuccessfulRaidAt`: Writes when host finishes raid confirmation cycle.
//  [W] - `raidConfirmationHistory`: Writes and updates host read-only raid confirmation history snapshots.
//  [X] - `mushroomType`: Not used by actions logic.
//  [X] - `attribute` (legacy fallback): Not used by actions logic.
//  [X] - `expiresAt`: Not used by actions logic.
//
//  Attendee document (`rooms/{roomId}/attendees/{uid}`):
//  [W] - `uid`: Reads for collection-group join-limit checks and writes on attendee create.
//  [W] - `name`: Writes attendee/host display name on create path.
//  [W] - `friendCode`: Writes attendee friend code on create path.
//  [W] - `stars`: Writes and increments stars during join and rating flows.
//  [W] - `depositHoney`: Reads for validation/refund and writes on join/deposit/confirmation.
//  [W] - `joinGreetingMessage`: Writes the attendee greeting entered at join time.
//  [W] - `status`: Reads for authorization/state checks and writes on transitions (`AskingToJoin`/`Ready`/`WaitingConfirmation`).
//  [W] - `joinedAt`: Writes join timestamp when attendee row is created.
//  [W] - `updatedAt`: Writes attendee mutation timestamp on every state change.
//  [W] - `isHostRatingRequired`: Reads/writes pending host-rating state after confirmations.
//  [W] - `isAttendeeRatedHost`: Reads/writes attendee-to-host rating completion state.
//  [W] - `isHostRatedAttendee`: Reads/writes host-to-attendee rating completion state.
//  [W] - `pendingConfirmationRequests`: Reads/writes per-attendee pending confirmation queue entries.
//  [W] - `lastSettlementOutcome`: Writes latest attendee escrow-settlement result.
//  [W] - `lastSettlementHoney`: Writes latest honey settled from attendee to host.
//
//  Kick marker document (`rooms/{roomId}/kickEvents/{kickEventId}`):
//  [W] - `hostUid`: Writes host uid snapshot for kick event production.
//  [W] - `attendeeUid`: Writes kicked attendee uid snapshot for kick event production.
//  [W] - `attendeeName`: Writes kicked attendee display name snapshot for inbox copy.
//  [W] - `roomId`: Writes room id snapshot for backend event routing.
//  [W] - `roomTitle`: Writes room title snapshot for inbox copy.
//  [W] - `refundedHoney`: Writes refunded deposit amount for attendee event copy.
//  [W] - `createdAt`: Writes kick marker creation timestamp.
//
import Foundation
import FirebaseAuth
import FirebaseFirestore

enum RoomActionError: LocalizedError {
    case notSignedIn
    case roomNotFound
    case roomFull
    case alreadyJoined
    case notInRoom
    case notHost
    case notEnoughHoney
    case emptyGreetingMessage
    case invalidJoinApplicationState
    case maxJoinRoomsReached(Int)
    case invalidStars
    case alreadyRated
    case ratingNotAvailable

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "You are not signed in."
        case .roomNotFound: return "Room not found."
        case .roomFull: return "This room is full."
        case .alreadyJoined: return "You already joined this room."
        case .notInRoom: return "You are not in this room."
        case .notHost: return "Only the host can do this."
        case .notEnoughHoney: return "Not enough honey."
        case .emptyGreetingMessage: return "Please enter a greeting message."
        case .invalidJoinApplicationState: return "Invalid join-application state."
        case .maxJoinRoomsReached(let limit): return "You can only join up to \(limit) rooms."
        case .invalidStars: return "Stars must be between 1 and 3."
        case .alreadyRated: return "You already submitted stars for this raid."
        case .ratingNotAvailable: return "Star rating is not available right now."
        }
    }
}

final class FbRoomActionsRepo {
    /// Room-scoped backend marker collection used to produce kick record events.
    private enum BackendCollectionName {
        /// Distinguishes host kick flows from leave/close attendee deletions.
        static let kickEvents: String = "kickEvents"
        /// Stores durable room rating tasks while the room remains open.
        static let roomRatingTasks: String = "roomRatingTasks"
    }

    private let db = Firestore.firestore()
    private let defaultMaxHostRooms = AppConfig.Mushroom.defaultHostRoomLimit
    private let defaultMaxJoinRooms = AppConfig.Mushroom.defaultJoinRoomLimit

    /// Resolves the effective joined-room limit from one user document snapshot.
    /// - Parameter userData: Raw Firestore user document payload.
    /// - Returns: Effective joined-room limit for the current entitlement state.
    private func effectiveMaxJoinRooms(from userData: [String: Any]) -> Int {
        let isPremium = userData["isPremium"] as? Bool ?? false
        let premiumExpirationDate = (userData["premiumExpirationAt"] as? Timestamp)?.dateValue()
        let isPremiumActive = isPremium && (premiumExpirationDate?.timeIntervalSinceNow ?? -1) > 0
        if isPremiumActive {
            return AppConfig.Premium.premiumJoinRoomLimit
        }
        return userData["maxJoinRoom"] as? Int ?? defaultMaxJoinRooms
    }

    /// Returns the attendee status that should be stored after a confirmation settles.
    private func resolvedPostSettlementStatus(
        remainingDepositHoney: Int,
        fixedRaidCost: Int,
        hasPendingConfirmation: Bool
    ) -> AttendeeStatus {
        if hasPendingConfirmation {
            return .waitingConfirmation
        }
        if remainingDepositHoney < fixedRaidCost {
            return .notEnoughHoney
        }
        return .ready
    }

    private func fetchMaxJoinRooms(uid: String) async throws -> Int {
        let userSnap = try await db.collection("users").document(uid).getDocument()
        return effectiveMaxJoinRooms(from: userSnap.data() ?? [:])
    }

    /// Builds a stable room rating task id so retries do not create duplicates.
    /// - Parameters:
    ///   - roomId: Parent room id.
    ///   - confirmationId: Confirmation cycle id.
    ///   - attendeeUid: Non-host attendee uid tied to this confirmation result.
    ///   - direction: Rating direction for the task.
    /// - Returns: Stable task document id.
    private func roomRatingTaskId(
        roomId: String,
        confirmationId: String,
        attendeeUid: String,
        direction: RoomRatingDirection
    ) -> String {
        "\(roomId)_\(confirmationId)_\(attendeeUid)_\(direction.rawValue)"
    }

    /// Returns the durable room rating task reference for one confirmation participant pair.
    /// - Parameters:
    ///   - roomId: Parent room id.
    ///   - confirmationId: Confirmation cycle id.
    ///   - attendeeUid: Non-host attendee uid tied to the task.
    ///   - direction: Rating direction for this task.
    /// - Returns: Firestore document reference.
    private func roomRatingTaskRef(
        roomId: String,
        confirmationId: String,
        attendeeUid: String,
        direction: RoomRatingDirection
    ) -> DocumentReference {
        db.collection(BackendCollectionName.roomRatingTasks).document(
            roomRatingTaskId(
                roomId: roomId,
                confirmationId: confirmationId,
                attendeeUid: attendeeUid,
                direction: direction
            )
        )
    }

    private func countActiveJoinedRooms(uid: String) async throws -> Int {
        let byUidField = try await db.collectionGroup("attendees")
            .whereField("uid", isEqualTo: uid)
            .whereField("status", in: AttendeeStatus.activeStatusRawValues)
            .getDocuments()
        return byUidField.documents.count
    }

    private struct RoomHostContext {
        let hostUid: String
    }

    private func fetchRoomHostContext(roomRef: DocumentReference) async throws -> RoomHostContext {
        let roomSnap = try await roomRef.getDocument()
        guard let roomData = roomSnap.data() else {
            throw RoomActionError.roomNotFound
        }

        let hostUidFromRoom = (roomData["hostUid"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !hostUidFromRoom.isEmpty {
            return RoomHostContext(hostUid: hostUidFromRoom)
        }

        let hostQuery = try await roomRef.collection("attendees")
            .whereField("status", isEqualTo: AttendeeStatus.host.rawValue)
            .limit(to: 1)
            .getDocuments()
        guard let hostDoc = hostQuery.documents.first else {
            throw RoomActionError.notHost
        }
        return RoomHostContext(hostUid: hostDoc.documentID)
    }

    // MARK: - Join (transaction)
    func joinRoom(
        roomId: String,
        initialDepositHoney: Int,
        greetingMessage: String,
        userName: String,
        friendCode: String,
        stars: Int,
        attendeeHoney: Int
    ) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw RoomActionError.notSignedIn }

        let maxJoinRooms = try await fetchMaxJoinRooms(uid: uid)
        let currentJoined = try await countActiveJoinedRooms(uid: uid)
        if currentJoined >= maxJoinRooms {
            throw RoomActionError.maxJoinRoomsReached(maxJoinRooms)
        }

        let roomRef = db.collection("rooms").document(roomId)
        let attendeeRef = roomRef.collection("attendees").document(uid)
        let userRef = db.collection("users").document(uid)
        let now = Timestamp(date: Date())

        try await db.runTransaction { [self] tx, errPtr -> Any? in
            // 1) Read room
            let roomSnap: DocumentSnapshot
            do { roomSnap = try tx.getDocument(roomRef) }
            catch { errPtr?.pointee = error as NSError; return nil }

            guard roomSnap.exists, let room = roomSnap.data() else {
                errPtr?.pointee = RoomActionError.roomNotFound as NSError
                return nil
            }

            let maxPlayers = room["maxPlayers"] as? Int ?? AppConfig.Mushroom.defaultMaxPlayersPerRoom
            let joinedCount = room["joinedCount"] as? Int ?? 0
            if joinedCount >= maxPlayers {
                errPtr?.pointee = RoomActionError.roomFull as NSError
                return nil
            }

            let minimumRequiredDepositHoney = AppConfig.Mushroom.minimumRequiredDepositHoney

            // 2) Check attendee doc doesn't already exist
            let attendeeSnap: DocumentSnapshot
            do { attendeeSnap = try tx.getDocument(attendeeRef) }
            catch { errPtr?.pointee = error as NSError; return nil }

            if attendeeSnap.exists {
                errPtr?.pointee = RoomActionError.alreadyJoined as NSError
                return nil
            }

            let userSnap: DocumentSnapshot
            do { userSnap = try tx.getDocument(userRef) }
            catch { errPtr?.pointee = error as NSError; return nil }

            let currentHoney: Int
            let currentFcmToken: String
            if let userData = userSnap.data() {
                currentHoney = userData["honey"] as? Int ?? 0
                currentFcmToken = (userData["fcmToken"] as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                currentHoney = max(0, attendeeHoney)
                currentFcmToken = ""
                tx.setData([
                    "displayName": userName,
                    "friendCode": friendCode,
                    "stars": stars,
                    "honey": currentHoney,
                    "maxHostRoom": self.defaultMaxHostRooms,
                    "maxJoinRoom": self.defaultMaxJoinRooms,
                    "isPremium": false,
                    "premiumProductId": "",
                    "createdAt": now,
                    "updatedAt": now
                ], forDocument: userRef)
            }

            let deposit = max(0, initialDepositHoney)
            if deposit < minimumRequiredDepositHoney {
                errPtr?.pointee = RoomActionError.notEnoughHoney as NSError
                return nil
            }
            let trimmedGreetingMessage = greetingMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedGreetingMessage.isEmpty {
                errPtr?.pointee = RoomActionError.emptyGreetingMessage as NSError
                return nil
            }
            if currentHoney < deposit {
                errPtr?.pointee = RoomActionError.notEnoughHoney as NSError
                return nil
            }

            // 3) Write attendee
            tx.setData([
                "uid": uid,
                "fcmToken": currentFcmToken,
                "name": userName,
                "friendCode": friendCode,
                "stars": stars,
                "depositHoney": deposit,
                "joinGreetingMessage": trimmedGreetingMessage,
                "status": AttendeeStatus.askingToJoin.rawValue,
                "joinedAt": now,
                "updatedAt": now
            ], forDocument: attendeeRef)

            // 4) Increment joinedCount + updatedAt
            tx.updateData([
                "joinedCount": FieldValue.increment(Int64(1)),
                "updatedAt": now
            ], forDocument: roomRef)

            // 5) Deduct honey from user
            tx.updateData([
                "honey": currentHoney - deposit,
                "updatedAt": now
            ], forDocument: userRef)

            return nil
        }
    }

    // MARK: - Update deposit (attendee only)
    func updateDeposit(roomId: String, depositHoney: Int, attendeeHoney: Int) async throws { // Handles updateDeposit flow.
        guard let uid = Auth.auth().currentUser?.uid else { throw RoomActionError.notSignedIn }

        let roomRef = db.collection("rooms").document(roomId)
        let attendeeRef = roomRef.collection("attendees").document(uid)
        let userRef = db.collection("users").document(uid)
        let now = Timestamp(date: Date())

        try await db.runTransaction { tx, errPtr -> Any? in
            let attendeeSnap: DocumentSnapshot
            do { attendeeSnap = try tx.getDocument(attendeeRef) }
            catch { errPtr?.pointee = error as NSError; return nil }

            guard let attendee = attendeeSnap.data() else {
                errPtr?.pointee = RoomActionError.notInRoom as NSError
                return nil
            }

            let oldDeposit = attendee["depositHoney"] as? Int ?? 0
            let newDeposit = max(0, depositHoney)
            let delta = newDeposit - oldDeposit

            let roomSnap: DocumentSnapshot
            do { roomSnap = try tx.getDocument(roomRef) }
            catch { errPtr?.pointee = error as NSError; return nil }
            let minimumRequiredDepositHoney = AppConfig.Mushroom.minimumRequiredDepositHoney
            if newDeposit < minimumRequiredDepositHoney {
                errPtr?.pointee = RoomActionError.notEnoughHoney as NSError
                return nil
            }

            let userSnap: DocumentSnapshot
            do { userSnap = try tx.getDocument(userRef) }
            catch { errPtr?.pointee = error as NSError; return nil }

            let currentHoney: Int
            if let userData = userSnap.data() {
                currentHoney = userData["honey"] as? Int ?? 0
            } else {
                currentHoney = max(0, attendeeHoney)
                tx.setData([
                    "displayName": "",
                    "friendCode": "",
                    "stars": 0,
                    "honey": currentHoney,
                    "maxHostRoom": self.defaultMaxHostRooms,
                    "maxJoinRoom": self.defaultMaxJoinRooms,
                    "isPremium": false,
                    "premiumProductId": "",
                    "createdAt": now,
                    "updatedAt": now
                ], forDocument: userRef)
            }

            if delta > 0 && currentHoney < delta {
                errPtr?.pointee = RoomActionError.notEnoughHoney as NSError
                return nil
            }

            tx.updateData([
                "depositHoney": newDeposit,
                "status": AttendeeStatus.ready.rawValue,
                "updatedAt": now
            ], forDocument: attendeeRef)

            let newHoney = currentHoney - delta
            tx.updateData([
                "honey": newHoney,
                "updatedAt": now
            ], forDocument: userRef)

            return nil
        }
    }

    // MARK: - Join application moderation (host only)
    func approveJoinApplication(roomId: String, attendeeUid: String) async throws { // Handles approveJoinApplication flow.
        guard let hostUid = Auth.auth().currentUser?.uid else { throw RoomActionError.notSignedIn }

        let roomRef = db.collection("rooms").document(roomId)
        let attendeeRef = roomRef.collection("attendees").document(attendeeUid)
        let now = Timestamp(date: Date())

        try await db.runTransaction { tx, errPtr -> Any? in
            let roomSnap: DocumentSnapshot
            let hostSelfSnap: DocumentSnapshot
            let attendeeSnap: DocumentSnapshot
            do {
                roomSnap = try tx.getDocument(roomRef)
                hostSelfSnap = try tx.getDocument(roomRef.collection("attendees").document(hostUid))
                attendeeSnap = try tx.getDocument(attendeeRef)
            } catch {
                errPtr?.pointee = error as NSError
                return nil
            }

            guard roomSnap.data() != nil else {
                errPtr?.pointee = RoomActionError.roomNotFound as NSError
                return nil
            }
            let hostStatus = hostSelfSnap.data()?["status"] as? String ?? ""
            guard hostStatus == AttendeeStatus.host.rawValue else {
                errPtr?.pointee = RoomActionError.notHost as NSError
                return nil
            }
            let attendeeStatus = attendeeSnap.data()?["status"] as? String ?? ""
            guard attendeeStatus == AttendeeStatus.askingToJoin.rawValue else {
                errPtr?.pointee = RoomActionError.invalidJoinApplicationState as NSError
                return nil
            }

            tx.updateData([
                "status": AttendeeStatus.ready.rawValue,
                "updatedAt": now
            ], forDocument: attendeeRef)
            tx.updateData([
                "updatedAt": now
            ], forDocument: roomRef)
            return nil
        }
    }

    func rejectJoinApplication(roomId: String, attendeeUid: String) async throws { // Handles rejectJoinApplication flow.
        guard let hostUid = Auth.auth().currentUser?.uid else { throw RoomActionError.notSignedIn }

        let roomRef = db.collection("rooms").document(roomId)
        let attendeeRef = roomRef.collection("attendees").document(attendeeUid)
        let userRef = db.collection("users").document(attendeeUid)
        let now = Timestamp(date: Date())

        try await db.runTransaction { tx, errPtr -> Any? in
            let roomSnap: DocumentSnapshot
            let hostSelfSnap: DocumentSnapshot
            let attendeeSnap: DocumentSnapshot
            do {
                roomSnap = try tx.getDocument(roomRef)
                hostSelfSnap = try tx.getDocument(roomRef.collection("attendees").document(hostUid))
                attendeeSnap = try tx.getDocument(attendeeRef)
            } catch {
                errPtr?.pointee = error as NSError
                return nil
            }

            guard roomSnap.data() != nil else {
                errPtr?.pointee = RoomActionError.roomNotFound as NSError
                return nil
            }
            let hostStatus = hostSelfSnap.data()?["status"] as? String ?? ""
            guard hostStatus == AttendeeStatus.host.rawValue else {
                errPtr?.pointee = RoomActionError.notHost as NSError
                return nil
            }
            let attendeeData = attendeeSnap.data() ?? [:]
            let attendeeStatus = attendeeData["status"] as? String ?? ""
            guard attendeeStatus == AttendeeStatus.askingToJoin.rawValue else {
                errPtr?.pointee = RoomActionError.invalidJoinApplicationState as NSError
                return nil
            }
            let depositHoney = attendeeData["depositHoney"] as? Int ?? 0

            tx.deleteDocument(attendeeRef)
            tx.updateData([
                "joinedCount": FieldValue.increment(Int64(-1)),
                "updatedAt": now
            ], forDocument: roomRef)
            if depositHoney > 0 {
                tx.setData([
                    "honey": FieldValue.increment(Int64(depositHoney)),
                    "updatedAt": now
                ], forDocument: userRef, merge: true)
            } else {
                tx.setData([
                    "updatedAt": now
                ], forDocument: userRef, merge: true)
            }

            return nil
        }
    }

    // MARK: - Leave (transaction)
    func leaveRoom(roomId: String, attendeeHoney: Int) async throws { // Handles leaveRoom flow.
        guard let uid = Auth.auth().currentUser?.uid else { throw RoomActionError.notSignedIn }

        let roomRef = db.collection("rooms").document(roomId)
        let attendeeRef = roomRef.collection("attendees").document(uid)
        let userRef = db.collection("users").document(uid)
        let now = Timestamp(date: Date())

        try await db.runTransaction { tx, errPtr -> Any? in
            // Ensure room exists
            let roomSnap: DocumentSnapshot
            do { roomSnap = try tx.getDocument(roomRef) }
            catch { errPtr?.pointee = error as NSError; return nil }

            guard roomSnap.exists else {
                errPtr?.pointee = RoomActionError.roomNotFound as NSError
                return nil
            }

            // Ensure attendee exists
            let attendeeSnap: DocumentSnapshot
            do { attendeeSnap = try tx.getDocument(attendeeRef) }
            catch { errPtr?.pointee = error as NSError; return nil }

            guard attendeeSnap.exists else {
                errPtr?.pointee = RoomActionError.notInRoom as NSError
                return nil
            }

            let deposit = attendeeSnap.data()?["depositHoney"] as? Int ?? 0

            let userSnap: DocumentSnapshot
            do { userSnap = try tx.getDocument(userRef) }
            catch { errPtr?.pointee = error as NSError; return nil }

            let currentHoney: Int
            if let userData = userSnap.data() {
                currentHoney = userData["honey"] as? Int ?? 0
            } else {
                currentHoney = max(0, attendeeHoney)
                tx.setData([
                    "displayName": "",
                    "friendCode": "",
                    "stars": 0,
                    "honey": currentHoney,
                    "maxHostRoom": self.defaultMaxHostRooms,
                    "maxJoinRoom": self.defaultMaxJoinRooms,
                    "isPremium": false,
                    "premiumProductId": "",
                    "createdAt": now,
                    "updatedAt": now
                ], forDocument: userRef)
            }

            // Delete attendee doc
            tx.deleteDocument(attendeeRef)

            // Decrement joinedCount (clamp later if needed)
            tx.updateData([
                "joinedCount": FieldValue.increment(Int64(-1)),
                "updatedAt": now
            ], forDocument: roomRef)

            // Refund deposit
            tx.updateData([
                "honey": currentHoney + max(0, deposit),
                "updatedAt": now
            ], forDocument: userRef)

            return nil
        }
    }

    // MARK: - Kick (host only, transaction)
    func kickAttendee(roomId: String, attendeeUid: String) async throws { // Handles kickAttendee flow.
        guard let uid = Auth.auth().currentUser?.uid else { throw RoomActionError.notSignedIn }

        let roomRef = db.collection("rooms").document(roomId)
        let attendeeRef = roomRef.collection("attendees").document(attendeeUid)
        let userRef = db.collection("users").document(attendeeUid)
        // Stable marker id reused across transaction retries so backend history stays single-write.
        let kickEventRef = roomRef
            .collection(BackendCollectionName.kickEvents)
            .document()
        let now = Timestamp(date: Date())

        try await db.runTransaction { tx, errPtr -> Any? in
            // Read room
            let roomSnap: DocumentSnapshot
            do { roomSnap = try tx.getDocument(roomRef) }
            catch { errPtr?.pointee = error as NSError; return nil }

            guard roomSnap.data() != nil else {
                errPtr?.pointee = RoomActionError.roomNotFound as NSError
                return nil
            }

            let hostSelfRef = roomRef.collection("attendees").document(uid)
            let hostSelfSnap: DocumentSnapshot
            do { hostSelfSnap = try tx.getDocument(hostSelfRef) }
            catch { errPtr?.pointee = error as NSError; return nil }
            let status = hostSelfSnap.data()?["status"] as? String ?? ""
            guard status == AttendeeStatus.host.rawValue else {
                errPtr?.pointee = RoomActionError.notHost as NSError
                return nil
            }

            // Ensure attendee exists
            let attendeeSnap: DocumentSnapshot
            do { attendeeSnap = try tx.getDocument(attendeeRef) }
            catch { errPtr?.pointee = error as NSError; return nil }

            guard attendeeSnap.exists else {
                // kicking someone not there: treat as no-op or error
                errPtr?.pointee = RoomActionError.notInRoom as NSError
                return nil
            }

            let roomTitle = (roomSnap.data()?["title"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let attendeeData = attendeeSnap.data() ?? [:]
            let deposit = attendeeData["depositHoney"] as? Int ?? 0
            let attendeeName = (attendeeData["name"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            tx.deleteDocument(attendeeRef)
            tx.updateData([
                "joinedCount": FieldValue.increment(Int64(-1)),
                "updatedAt": now
            ], forDocument: roomRef)

            tx.setData([
                "hostUid": uid,
                "attendeeUid": attendeeUid,
                "attendeeName": attendeeName,
                "roomId": roomId,
                "roomTitle": roomTitle,
                "refundedHoney": max(0, deposit),
                "createdAt": now
            ], forDocument: kickEventRef)

            if deposit > 0 {
                tx.setData([
                    "honey": FieldValue.increment(Int64(deposit)),
                    "updatedAt": now
                ], forDocument: userRef, merge: true)
            } else {
                tx.setData([
                    "updatedAt": now
                ], forDocument: userRef, merge: true)
            }

            return nil
        }
    }

    // MARK: - Close room (host only)
    func closeRoom(roomId: String) async throws { // Handles closeRoom flow.
        guard let uid = Auth.auth().currentUser?.uid else { throw RoomActionError.notSignedIn }

        let roomRef = db.collection("rooms").document(roomId)
        let snap = try await roomRef.getDocument()
        guard snap.exists else { throw RoomActionError.roomNotFound }

        let hostSelfSnap = try await roomRef.collection("attendees").document(uid).getDocument()
        let status = hostSelfSnap.data()?["status"] as? String ?? ""
        guard status == AttendeeStatus.host.rawValue else { throw RoomActionError.notHost }

        let attendeesSnap = try await roomRef.collection("attendees").getDocuments()
        let pendingRatingTasksSnap = try await db.collection(BackendCollectionName.roomRatingTasks)
            .whereField("roomId", isEqualTo: roomId)
            .whereField("status", isEqualTo: RoomRatingTaskStatus.pending.rawValue)
            .getDocuments()
        let now = Timestamp(date: Date())

        let batch = db.batch()

        batch.updateData([
            "joinedCount": 0,
            "updatedAt": now
        ], forDocument: roomRef)

        for doc in attendeesSnap.documents {
            let attendeeUid = doc.documentID
            let deposit = doc.data()["depositHoney"] as? Int ?? 0
            let userRef = db.collection("users").document(attendeeUid)

            batch.deleteDocument(doc.reference)
            if deposit > 0 {
                batch.setData([
                    "honey": FieldValue.increment(Int64(deposit)),
                    "updatedAt": now
                ], forDocument: userRef, merge: true)
            } else {
                batch.setData([
                    "updatedAt": now
                ], forDocument: userRef, merge: true)
            }
        }

        for taskDoc in pendingRatingTasksSnap.documents {
            batch.updateData([
                "status": RoomRatingTaskStatus.closed.rawValue,
                "updatedAt": now,
                "resolvedAt": now
            ], forDocument: taskDoc.reference)
        }

        batch.deleteDocument(roomRef)
        try await batch.commit()
    }

    // MARK: - Finish raid (host only)
    func finishRaid(
        roomId: String,
        attendeeUids: [String],
        allNonHostAttendeeUids: [String]
    ) async throws { // Handles finishRaid flow.
        guard let uid = Auth.auth().currentUser?.uid else { throw RoomActionError.notSignedIn }
        guard !attendeeUids.isEmpty else { return }

        let roomRef = db.collection("rooms").document(roomId)
        let now = Timestamp(date: Date())
        let confirmationId = UUID().uuidString
        let invitedAttendeeUids = Set(attendeeUids)
        let historyLimit = 50

        _ = try await db.runTransaction { [self] tx, errPtr -> Any? in
            let roomSnap: DocumentSnapshot
            do { roomSnap = try tx.getDocument(roomRef) }
            catch { errPtr?.pointee = error as NSError; return nil }

            guard let room = roomSnap.data() else {
                errPtr?.pointee = RoomActionError.roomNotFound as NSError
                return nil
            }

            let hostSelfRef = roomRef.collection("attendees").document(uid)
            let hostSelfSnap: DocumentSnapshot
            do { hostSelfSnap = try tx.getDocument(hostSelfRef) }
            catch { errPtr?.pointee = error as NSError; return nil }
            let status = hostSelfSnap.data()?["status"] as? String ?? ""
            guard status == AttendeeStatus.host.rawValue else {
                errPtr?.pointee = RoomActionError.notHost as NSError
                return nil
            }

            var attendeeDocsForHistory: [(uid: String, ref: DocumentReference, data: [String: Any])] = []
            attendeeDocsForHistory.reserveCapacity(allNonHostAttendeeUids.count)

            for attendeeUid in allNonHostAttendeeUids {
                let attendeeRef = roomRef.collection("attendees").document(attendeeUid)
                let attendeeSnap: DocumentSnapshot
                do { attendeeSnap = try tx.getDocument(attendeeRef) }
                catch { errPtr?.pointee = error as NSError; return nil }

                guard attendeeSnap.exists, let data = attendeeSnap.data() else {
                    continue
                }
                attendeeDocsForHistory.append((uid: attendeeUid, ref: attendeeRef, data: data))
            }

            for attendee in attendeeDocsForHistory where invitedAttendeeUids.contains(attendee.uid) {
                let existingQueueRaw = attendee.data["pendingConfirmationRequests"] as? [String: Any] ?? [:]
                var pendingConfirmationRequests = existingQueueRaw.reduce(into: [String: Timestamp]()) { partialResult, entry in
                    if let timestamp = entry.value as? Timestamp {
                        partialResult[entry.key] = timestamp
                    }
                }
                pendingConfirmationRequests[confirmationId] = now
                tx.updateData([
                    "status": AttendeeStatus.waitingConfirmation.rawValue,
                    "isAttendeeRatedHost": false,
                    "attendeeRatedHost": false,
                    "isHostRatedAttendee": false,
                    "hostRatedAttendee": false,
                    "isHostRatingRequired": false,
                    "needsHostRating": false,
                    "pendingConfirmationRequests": pendingConfirmationRequests,
                    "lastSettlementOutcome": "",
                    "lastSettlementHoney": 0,
                    "updatedAt": now
                ], forDocument: attendee.ref)
            }

            let attendeeResultsForHistory = attendeeDocsForHistory.map { attendee in
                let attendeeName = attendee.data["name"] as? String ?? "Unknown"
                let isInvited = invitedAttendeeUids.contains(attendee.uid)
                return [
                    "uid": attendee.uid,
                    "name": attendeeName,
                    "status": isInvited
                        ? RoomRaidConfirmationAttendeeStatus.confirming.rawValue
                        : RoomRaidConfirmationAttendeeStatus.noInvite.rawValue
                ]
            }

            let existingHistory = room["raidConfirmationHistory"] as? [[String: Any]] ?? []
            let createdHistoryEntry: [String: Any] = [
                "id": confirmationId,
                "requestedAt": now,
                "attendeeResults": attendeeResultsForHistory
            ]
            let updatedHistory = Array(([createdHistoryEntry] + existingHistory).prefix(historyLimit))

            let roomUpdates: [String: Any] = [
                "lastSuccessfulRaidAt": now,
                "raidConfirmationHistory": updatedHistory,
                "updatedAt": now
            ]
            tx.updateData(roomUpdates, forDocument: roomRef)

            return nil
        }
    }

    // MARK: - Confirm raid (attendee only)
    func respondToRaidConfirmation(
        roomId: String,
        attendeeUid: String,
        confirmationId: String,
        settlementOutcome: RaidSettlementOutcome
    ) async throws { // Handles respondToRaidConfirmation flow.
        guard let uid = Auth.auth().currentUser?.uid else { throw RoomActionError.notSignedIn }
        guard uid == attendeeUid else { throw RoomActionError.notInRoom }

        let roomRef = db.collection("rooms").document(roomId)
        let attendeeRef = roomRef.collection("attendees").document(attendeeUid)
        let now = Timestamp(date: Date())
        let hostContext = try await fetchRoomHostContext(roomRef: roomRef)

        try await db.runTransaction { [self] tx, errPtr -> Any? in
            let hostRef = self.db.collection("users").document(hostContext.hostUid)

            let roomSnap: DocumentSnapshot
            let hostSnap: DocumentSnapshot
            let attendeeSnap: DocumentSnapshot
            do {
                roomSnap = try tx.getDocument(roomRef)
                hostSnap = try tx.getDocument(hostRef)
                attendeeSnap = try tx.getDocument(attendeeRef)
            } catch {
                errPtr?.pointee = error as NSError
                return nil
            }

            let roomData = roomSnap.data() ?? [:]
            let roomTitle = (roomData["title"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let hostHoney = hostSnap.data()?["honey"] as? Int ?? 0
            let hostName = (hostSnap.data()?["displayName"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let attendeeData = attendeeSnap.data() ?? [:]
            let attendeeDeposit = attendeeData["depositHoney"] as? Int ?? 0
            let attendeeStatus = attendeeData["status"] as? String ?? ""
            let attendeeName = (attendeeData["name"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let pendingQueueRaw = attendeeData["pendingConfirmationRequests"] as? [String: Any] ?? [:]
            var pendingConfirmationRequests = pendingQueueRaw.reduce(into: [String: Timestamp]()) { partialResult, entry in
                if let timestamp = entry.value as? Timestamp {
                    partialResult[entry.key] = timestamp
                }
            }

            if pendingConfirmationRequests.isEmpty {
                if attendeeStatus != AttendeeStatus.waitingConfirmation.rawValue {
                    errPtr?.pointee = RoomActionError.notInRoom as NSError
                    return nil
                }
            } else {
                guard pendingConfirmationRequests[confirmationId] != nil else {
                    errPtr?.pointee = RoomActionError.notInRoom as NSError
                    return nil
                }
                pendingConfirmationRequests.removeValue(forKey: confirmationId)
            }

            let hasPendingConfirmation = pendingConfirmationRequests.isEmpty == false

            let historyStatus: RoomRaidConfirmationAttendeeStatus
            switch settlementOutcome {
            case .joinedSuccess:
                historyStatus = .joined
                if attendeeDeposit < AppConfig.Mushroom.joinedSuccessRewardHoney {
                    errPtr?.pointee = RoomActionError.notEnoughHoney as NSError
                    return nil
                }
                let settlementHoney = AppConfig.Mushroom.joinedSuccessRewardHoney
                tx.updateData([
                    "honey": hostHoney + settlementHoney,
                    "updatedAt": now
                ], forDocument: hostRef)

                let remainingDepositHoney = max(0, attendeeDeposit - settlementHoney)
                let nextStatus = resolvedPostSettlementStatus(
                    remainingDepositHoney: remainingDepositHoney,
                    fixedRaidCost: AppConfig.Mushroom.minimumRequiredDepositHoney,
                    hasPendingConfirmation: hasPendingConfirmation
                )
                tx.updateData([
                    "depositHoney": max(0, attendeeDeposit - settlementHoney),
                    "status": nextStatus.rawValue,
                    "isHostRatingRequired": false,
                    "needsHostRating": false,
                    "pendingConfirmationRequests": pendingConfirmationRequests,
                    "lastSettlementOutcome": settlementOutcome.rawValue,
                    "lastSettlementHoney": settlementHoney,
                    "updatedAt": now
                ], forDocument: attendeeRef)
            case .seatFullNoFault:
                historyStatus = .seatFull
                let settlementHoney = min(attendeeDeposit, AppConfig.Mushroom.seatFullRewardHoney)
                tx.updateData([
                    "honey": hostHoney + settlementHoney,
                    "updatedAt": now
                ], forDocument: hostRef)

                let remainingDepositHoney = max(0, attendeeDeposit - settlementHoney)
                let nextStatus = resolvedPostSettlementStatus(
                    remainingDepositHoney: remainingDepositHoney,
                    fixedRaidCost: AppConfig.Mushroom.minimumRequiredDepositHoney,
                    hasPendingConfirmation: hasPendingConfirmation
                )
                tx.updateData([
                    "depositHoney": max(0, attendeeDeposit - settlementHoney),
                    "status": nextStatus.rawValue,
                    "isHostRatingRequired": false,
                    "needsHostRating": false,
                    "pendingConfirmationRequests": pendingConfirmationRequests,
                    "lastSettlementOutcome": settlementOutcome.rawValue,
                    "lastSettlementHoney": settlementHoney,
                    "updatedAt": now
                ], forDocument: attendeeRef)
            case .missedInvitation:
                historyStatus = .noInvite
                let nextStatus = resolvedPostSettlementStatus(
                    remainingDepositHoney: attendeeDeposit,
                    fixedRaidCost: AppConfig.Mushroom.minimumRequiredDepositHoney,
                    hasPendingConfirmation: hasPendingConfirmation
                )
                tx.updateData([
                    "status": nextStatus.rawValue,
                    "isHostRatingRequired": false,
                    "needsHostRating": false,
                    "pendingConfirmationRequests": pendingConfirmationRequests,
                    "lastSettlementOutcome": settlementOutcome.rawValue,
                    "lastSettlementHoney": 0,
                    "updatedAt": now
                ], forDocument: attendeeRef)
            }

            let attendeeToHostTaskRef = self.roomRatingTaskRef(
                roomId: roomId,
                confirmationId: confirmationId,
                attendeeUid: attendeeUid,
                direction: .attendeeToHost
            )
            let hostToAttendeeTaskRef = self.roomRatingTaskRef(
                roomId: roomId,
                confirmationId: confirmationId,
                attendeeUid: attendeeUid,
                direction: .hostToAttendee
            )
            let requestedAtTimestamp = pendingQueueRaw[confirmationId] as? Timestamp ?? now
            let normalizedRoomTitle = roomTitle.isEmpty ? "Room" : roomTitle
            let normalizedHostName = hostName.isEmpty ? "Host" : hostName
            let normalizedAttendeeName = attendeeName.isEmpty ? "Attendee" : attendeeName
            tx.setData([
                "roomId": roomId,
                "roomTitle": normalizedRoomTitle,
                "confirmationId": confirmationId,
                "requestedAt": requestedAtTimestamp,
                "raterUid": attendeeUid,
                "rateeUid": hostContext.hostUid,
                "counterpartName": normalizedHostName,
                "direction": RoomRatingDirection.attendeeToHost.rawValue,
                "settlementOutcome": settlementOutcome.rawValue,
                "status": RoomRatingTaskStatus.pending.rawValue,
                "updatedAt": now
            ], forDocument: attendeeToHostTaskRef, merge: true)
            tx.setData([
                "roomId": roomId,
                "roomTitle": normalizedRoomTitle,
                "confirmationId": confirmationId,
                "requestedAt": requestedAtTimestamp,
                "raterUid": hostContext.hostUid,
                "rateeUid": attendeeUid,
                "counterpartName": normalizedAttendeeName,
                "direction": RoomRatingDirection.hostToAttendee.rawValue,
                "settlementOutcome": settlementOutcome.rawValue,
                "status": RoomRatingTaskStatus.pending.rawValue,
                "updatedAt": now
            ], forDocument: hostToAttendeeTaskRef, merge: true)

            var raidConfirmationHistory = roomData["raidConfirmationHistory"] as? [[String: Any]] ?? []
            if let historyIndex = raidConfirmationHistory.firstIndex(where: { historyEntry in
                (historyEntry["id"] as? String) == confirmationId
            }) {
                var historyEntry = raidConfirmationHistory[historyIndex]
                var attendeeResults = historyEntry["attendeeResults"] as? [[String: Any]] ?? []
                if let attendeeIndex = attendeeResults.firstIndex(where: { attendeeEntry in
                    (attendeeEntry["uid"] as? String) == attendeeUid
                }) {
                    var attendeeEntry = attendeeResults[attendeeIndex]
                    attendeeEntry["status"] = historyStatus.rawValue
                    attendeeResults[attendeeIndex] = attendeeEntry
                    historyEntry["attendeeResults"] = attendeeResults
                    raidConfirmationHistory[historyIndex] = historyEntry
                    tx.updateData([
                        "raidConfirmationHistory": raidConfirmationHistory,
                        "updatedAt": now
                    ], forDocument: roomRef)
                }
            }

            return nil
        }
    }

    // MARK: - Stars
    func submitRoomRating(taskId: String, stars: Int) async throws { // Handles submitRoomRating flow.
        guard (1...3).contains(stars) else { throw RoomActionError.invalidStars }
        guard let currentUid = Auth.auth().currentUser?.uid else { throw RoomActionError.notSignedIn }

        let taskRef = db.collection(BackendCollectionName.roomRatingTasks).document(taskId)
        let now = Timestamp(date: Date())

        print("🔎 [RoomRating] submit start taskId=\(taskId) raterUid=\(currentUid) stars=\(stars)")
        try await db.runTransaction { tx, errPtr -> Any? in
            let taskSnap: DocumentSnapshot
            do {
                taskSnap = try tx.getDocument(taskRef)
            } catch {
                errPtr?.pointee = error as NSError
                return nil
            }

            guard let taskData = taskSnap.data() else {
                errPtr?.pointee = RoomActionError.ratingNotAvailable as NSError
                return nil
            }
            let taskRaterUid = (taskData["raterUid"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard taskRaterUid == currentUid else {
                errPtr?.pointee = RoomActionError.notInRoom as NSError
                return nil
            }
            let taskStatusRaw = (taskData["status"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard taskStatusRaw == RoomRatingTaskStatus.pending.rawValue else {
                errPtr?.pointee = RoomActionError.ratingNotAvailable as NSError
                return nil
            }
            let rateeUid = (taskData["rateeUid"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let roomId = (taskData["roomId"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard rateeUid.isEmpty == false else {
                errPtr?.pointee = RoomActionError.ratingNotAvailable as NSError
                return nil
            }
            let rateeUserRef = self.db.collection("users").document(rateeUid)
            let rateeUserSnapshot: DocumentSnapshot
            do {
                rateeUserSnapshot = try tx.getDocument(rateeUserRef)
            } catch {
                errPtr?.pointee = error as NSError
                return nil
            }
            let previousRateeStars = rateeUserSnapshot.data()?["stars"] as? Int ?? 0
            print(
                "🔎 [RoomRating] taskId=\(taskId) roomId=\(roomId) rateeUid=\(rateeUid) " +
                "previousUserStars=\(previousRateeStars) increment=\(stars) " +
                "expectedUserStars=\(previousRateeStars + stars)"
            )

            tx.setData([
                "stars": FieldValue.increment(Int64(stars)),
                "updatedAt": now
            ], forDocument: rateeUserRef, merge: true)

            if roomId.isEmpty == false {
                let roomAttendeeRef = self.db.collection("rooms")
                    .document(roomId)
                    .collection("attendees")
                    .document(rateeUid)
                tx.setData([
                    "stars": FieldValue.increment(Int64(stars)),
                    "updatedAt": now
                ], forDocument: roomAttendeeRef, merge: true)
            }

            tx.updateData([
                "status": RoomRatingTaskStatus.rated.rawValue,
                "stars": stars,
                "updatedAt": now,
                "resolvedAt": now
            ], forDocument: taskRef)

            return nil
        }

        let committedTaskSnapshot = try await taskRef.getDocument(source: .server)
        let rateeUid = committedTaskSnapshot.data()?["rateeUid"] as? String ?? ""
        if rateeUid.isEmpty == false {
            let rateeSnapshot = try await db.collection("users").document(rateeUid).getDocument(source: .server)
            let serverStars = rateeSnapshot.data()?["stars"] as? Int ?? 0
            print("🔎 [RoomRating] submit committed taskId=\(taskId) rateeUid=\(rateeUid) serverUserStars=\(serverStars)")
        } else {
            print("🔎 [RoomRating] submit committed taskId=\(taskId) but rateeUid was empty on post-read")
        }
    }

    /// Permanently skips one pending room rating task.
    /// - Parameter taskId: Durable rating task id shown in the room clipboard UI.
    func skipRoomRating(taskId: String) async throws {
        guard let currentUid = Auth.auth().currentUser?.uid else { throw RoomActionError.notSignedIn }

        let taskRef = db.collection(BackendCollectionName.roomRatingTasks).document(taskId)
        let now = Timestamp(date: Date())

        try await db.runTransaction { tx, errPtr -> Any? in
            let taskSnap: DocumentSnapshot
            do {
                taskSnap = try tx.getDocument(taskRef)
            } catch {
                errPtr?.pointee = error as NSError
                return nil
            }

            guard let taskData = taskSnap.data() else {
                errPtr?.pointee = RoomActionError.ratingNotAvailable as NSError
                return nil
            }
            let taskRaterUid = (taskData["raterUid"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard taskRaterUid == currentUid else {
                errPtr?.pointee = RoomActionError.notInRoom as NSError
                return nil
            }
            let taskStatusRaw = (taskData["status"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard taskStatusRaw == RoomRatingTaskStatus.pending.rawValue else {
                errPtr?.pointee = RoomActionError.ratingNotAvailable as NSError
                return nil
            }
            tx.updateData([
                "status": RoomRatingTaskStatus.skipped.rawValue,
                "updatedAt": now,
                "resolvedAt": now
            ], forDocument: taskRef)

            return nil
        }
    }
}
