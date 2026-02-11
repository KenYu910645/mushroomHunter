//
//  FirebaseRoomActionsRepository.swift
//  mushroomHunter
//
//  Created by Ken on 6/2/2026.
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
    case maxJoinRoomsReached(Int)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "You are not signed in."
        case .roomNotFound: return "Room not found."
        case .roomFull: return "This room is full."
        case .alreadyJoined: return "You already joined this room."
        case .notInRoom: return "You are not in this room."
        case .notHost: return "Only the host can do this."
        case .notEnoughHoney: return "Not enough honey."
        case .maxJoinRoomsReached(let limit): return "You can only join up to \(limit) rooms."
        }
    }
}

final class FirebaseRoomActionsRepository {
    private let db = Firestore.firestore()
    private let defaultMaxHostRooms = 1
    private let defaultMaxJoinRooms = 3

    private func fetchMaxJoinRooms(uid: String) async throws -> Int {
        let userSnap = try await db.collection("users").document(uid).getDocument()
        return userSnap.data()?["maxJoinRoom"] as? Int ?? defaultMaxJoinRooms
    }

    private func countActiveJoinedRooms(uid: String) async throws -> Int {
        let attendeeSnap = try await db.collectionGroup("attendees")
            .whereField("uid", isEqualTo: uid)
            .getDocuments()

        var count = 0
        for doc in attendeeSnap.documents {
            guard let roomRef = doc.reference.parent.parent else { continue }
            let roomSnap = try await roomRef.getDocument()
            if roomSnap.exists {
                count += 1
            }
        }
        return count
    }

    // MARK: - Join (transaction)
    func joinRoom(
        roomId: String,
        initialDepositHoney: Int,
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

            let maxPlayers = room["maxPlayers"] as? Int ?? 10
            let joinedCount = room["joinedCount"] as? Int ?? 0
            if joinedCount >= maxPlayers {
                errPtr?.pointee = RoomActionError.roomFull as NSError
                return nil
            }

            let fixedRaidCost = (room["fixedRaidCost"] as? Int) ?? 10

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
            if let userData = userSnap.data() {
                currentHoney = userData["honey"] as? Int ?? 0
            } else {
                currentHoney = max(0, attendeeHoney)
                tx.setData([
                    "displayName": userName,
                    "friendCode": friendCode,
                    "stars": stars,
                    "honey": currentHoney,
                    "maxHostRoom": self.defaultMaxHostRooms,
                    "maxJoinRoom": self.defaultMaxJoinRooms,
                    "createdAt": now,
                    "updatedAt": now
                ], forDocument: userRef)
            }

            let deposit = max(0, initialDepositHoney)
            if deposit < max(1, fixedRaidCost) {
                errPtr?.pointee = RoomActionError.notEnoughHoney as NSError
                return nil
            }
            if currentHoney < deposit {
                errPtr?.pointee = RoomActionError.notEnoughHoney as NSError
                return nil
            }

            // 3) Write attendee
            tx.setData([
                "name": userName,
                "friendCode": friendCode,
                "stars": stars,
                "depositHoney": deposit,
                "status": AttendeeStatus.ready.rawValue,
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
    func updateDeposit(roomId: String, depositHoney: Int, attendeeHoney: Int) async throws {
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
            let fixedRaidCost = (roomSnap.data()?["fixedRaidCost"] as? Int) ?? 10
            if newDeposit < max(1, fixedRaidCost) {
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

    // MARK: - Leave (transaction)
    func leaveRoom(roomId: String, attendeeHoney: Int) async throws {
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
    func kickAttendee(roomId: String, attendeeUid: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw RoomActionError.notSignedIn }

        let roomRef = db.collection("rooms").document(roomId)
        let attendeeRef = roomRef.collection("attendees").document(attendeeUid)
        let userRef = db.collection("users").document(attendeeUid)
        let now = Timestamp(date: Date())

        try await db.runTransaction { tx, errPtr -> Any? in
            // Read room
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

            // Ensure attendee exists
            let attendeeSnap: DocumentSnapshot
            do { attendeeSnap = try tx.getDocument(attendeeRef) }
            catch { errPtr?.pointee = error as NSError; return nil }

            guard attendeeSnap.exists else {
                // kicking someone not there: treat as no-op or error
                errPtr?.pointee = RoomActionError.notInRoom as NSError
                return nil
            }

            let deposit = attendeeSnap.data()?["depositHoney"] as? Int ?? 0

            tx.deleteDocument(attendeeRef)
            tx.updateData([
                "joinedCount": FieldValue.increment(Int64(-1)),
                "updatedAt": now
            ], forDocument: roomRef)

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
    func closeRoom(roomId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw RoomActionError.notSignedIn }

        let roomRef = db.collection("rooms").document(roomId)
        let snap = try await roomRef.getDocument()
        guard snap.exists else { throw RoomActionError.roomNotFound }

        let hostSelfSnap = try await roomRef.collection("attendees").document(uid).getDocument()
        let status = hostSelfSnap.data()?["status"] as? String ?? ""
        guard status == AttendeeStatus.host.rawValue else { throw RoomActionError.notHost }

        let attendeesSnap = try await roomRef.collection("attendees").getDocuments()
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

        batch.deleteDocument(roomRef)
        try await batch.commit()
    }

    // MARK: - Finish raid (host only)
    func finishRaid(roomId: String, attendeeUids: [String]) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw RoomActionError.notSignedIn }
        guard !attendeeUids.isEmpty else { return }

        let roomRef = db.collection("rooms").document(roomId)
        let now = Timestamp(date: Date())

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

            let raidCost = (room["fixedRaidCost"] as? Int) ?? 10

            for attendeeUid in attendeeUids {
                let attendeeRef = roomRef.collection("attendees").document(attendeeUid)
                let attendeeSnap: DocumentSnapshot
                do { attendeeSnap = try tx.getDocument(attendeeRef) }
                catch { errPtr?.pointee = error as NSError; return nil }

                guard attendeeSnap.exists, let data = attendeeSnap.data() else {
                    continue
                }

                let deposit = data["depositHoney"] as? Int ?? 0
                if deposit < raidCost { continue }

                tx.updateData([
                    "status": AttendeeStatus.waitingConfirmation.rawValue,
                    "updatedAt": now
                ], forDocument: attendeeRef)
            }

            let roomUpdates: [String: Any] = [
                "lastSuccessfulRaidAt": now,
                "updatedAt": now
            ]
            tx.updateData(roomUpdates, forDocument: roomRef)

            return nil
        }
    }

    // MARK: - Confirm raid (attendee only)
    func respondToRaidConfirmation(roomId: String, attendeeUid: String, accept: Bool) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw RoomActionError.notSignedIn }
        guard uid == attendeeUid else { throw RoomActionError.notInRoom }

        let roomRef = db.collection("rooms").document(roomId)
        let attendeeRef = roomRef.collection("attendees").document(attendeeUid)
        let now = Timestamp(date: Date())

        let hostQuery = try await roomRef.collection("attendees")
            .whereField("status", isEqualTo: AttendeeStatus.host.rawValue)
            .limit(to: 1)
            .getDocuments()
        guard let hostDoc = hostQuery.documents.first else {
            throw RoomActionError.notHost
        }
        let hostUid = hostDoc.documentID

        try await db.runTransaction { [self] tx, errPtr -> Any? in
            let roomSnap: DocumentSnapshot
            do { roomSnap = try tx.getDocument(roomRef) }
            catch { errPtr?.pointee = error as NSError; return nil }

            guard let room = roomSnap.data() else {
                errPtr?.pointee = RoomActionError.roomNotFound as NSError
                return nil
            }

            let raidCostHoney = (room["fixedRaidCost"] as? Int) ?? 10
            let hostRef = self.db.collection("users").document(hostUid)

            let hostSnap: DocumentSnapshot
            let attendeeSnap: DocumentSnapshot
            do {
                hostSnap = try tx.getDocument(hostRef)
                attendeeSnap = try tx.getDocument(attendeeRef)
            } catch {
                errPtr?.pointee = error as NSError
                return nil
            }

            let hostHoney = hostSnap.data()?["honey"] as? Int ?? 0
            let attendeeDeposit = attendeeSnap.data()?["depositHoney"] as? Int ?? 0

            if accept {
                if attendeeDeposit < raidCostHoney {
                    errPtr?.pointee = RoomActionError.notEnoughHoney as NSError
                    return nil
                }
                tx.updateData([
                    "honey": hostHoney + max(0, raidCostHoney),
                    "updatedAt": now
                ], forDocument: hostRef)

                tx.updateData([
                    "depositHoney": max(0, attendeeDeposit - raidCostHoney),
                    "status": AttendeeStatus.ready.rawValue,
                    "updatedAt": now
                ], forDocument: attendeeRef)
            } else {
                tx.updateData([
                    "status": AttendeeStatus.rejected.rawValue,
                    "updatedAt": now
                ], forDocument: attendeeRef)
            }

            return nil
        }
    }

    // MARK: - Resolve rejected (host only)
    func resolveRejectedConfirmation(roomId: String, attendeeUid: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw RoomActionError.notSignedIn }

        let roomRef = db.collection("rooms").document(roomId)
        let attendeeRef = roomRef.collection("attendees").document(attendeeUid)
        let now = Timestamp(date: Date())

        try await db.runTransaction { tx, errPtr -> Any? in
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

            tx.updateData([
                "status": AttendeeStatus.ready.rawValue,
                "updatedAt": now
            ], forDocument: attendeeRef)

            return nil
        }
    }
}
