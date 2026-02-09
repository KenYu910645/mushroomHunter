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
    case roomClosed
    case roomFull
    case alreadyJoined
    case notInRoom
    case notHost
    case notEnoughHoney

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "You are not signed in."
        case .roomNotFound: return "Room not found."
        case .roomClosed: return "This room is closed."
        case .roomFull: return "This room is full."
        case .alreadyJoined: return "You already joined this room."
        case .notInRoom: return "You are not in this room."
        case .notHost: return "Only the host can do this."
        case .notEnoughHoney: return "Not enough honey."
        }
    }
}

final class FirebaseRoomActionsRepository {
    private let db = Firestore.firestore()

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

        let roomRef = db.collection("rooms").document(roomId)
        let attendeeRef = roomRef.collection("attendees").document(uid)
        let userRef = db.collection("users").document(uid)
        let now = Timestamp(date: Date())

        try await db.runTransaction { tx, errPtr -> Any? in
            // 1) Read room
            let roomSnap: DocumentSnapshot
            do { roomSnap = try tx.getDocument(roomRef) }
            catch { errPtr?.pointee = error as NSError; return nil }

            guard roomSnap.exists, let room = roomSnap.data() else {
                errPtr?.pointee = RoomActionError.roomNotFound as NSError
                return nil
            }

            let status = (room["status"] as? String ?? "open").lowercased()
            if status != "open" {
                errPtr?.pointee = RoomActionError.roomClosed as NSError
                return nil
            }

            let maxPlayers = room["maxPlayers"] as? Int ?? 10
            let joinedCount = room["joinedCount"] as? Int ?? 0
            if joinedCount >= maxPlayers {
                errPtr?.pointee = RoomActionError.roomFull as NSError
                return nil
            }

            let fixedRaidCost = (room["fixedRaidCost"] as? Int)
                ?? (room["minBid"] as? Int)
                ?? 10

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
                    "activeRoomId": roomId,
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
                "uid": uid,
                "name": userName,
                "friendCode": friendCode,
                "stars": stars,
                "depositHoney": deposit,
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
                "activeRoomId": roomId,
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
            let fixedRaidCost = (roomSnap.data()?["fixedRaidCost"] as? Int)
                ?? (roomSnap.data()?["minBid"] as? Int)
                ?? 10
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
                    "activeRoomId": roomId,
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
                "updatedAt": now
            ], forDocument: attendeeRef)

            let newHoney = currentHoney - delta
            tx.updateData([
                "honey": newHoney,
                "activeRoomId": roomId,
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
                    "activeRoomId": roomId,
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
                "activeRoomId": FieldValue.delete(),
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

            let hostUid = room["hostUid"] as? String ?? ""
            guard hostUid == uid else {
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
                    "activeRoomId": FieldValue.delete(),
                    "updatedAt": now
                ], forDocument: userRef, merge: true)
            } else {
                tx.setData([
                    "activeRoomId": FieldValue.delete(),
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
        guard let data = snap.data() else { throw RoomActionError.roomNotFound }

        let hostUid = data["hostUid"] as? String ?? ""
        guard hostUid == uid else { throw RoomActionError.notHost }

        let attendeesSnap = try await roomRef.collection("attendees").getDocuments()
        let now = Timestamp(date: Date())

        let batch = db.batch()

        batch.updateData([
            "status": "closed",
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
                    "activeRoomId": FieldValue.delete(),
                    "updatedAt": now
                ], forDocument: userRef, merge: true)
            } else {
                batch.setData([
                    "activeRoomId": FieldValue.delete(),
                    "updatedAt": now
                ], forDocument: userRef, merge: true)
            }
        }

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

            let hostUid = room["hostUid"] as? String ?? ""
            guard hostUid == uid else {
                errPtr?.pointee = RoomActionError.notHost as NSError
                return nil
            }

            let hostName = room["hostName"] as? String ?? "Host"
            let expiresAt = Timestamp(date: Date().addingTimeInterval(72 * 60 * 60))

            for attendeeUid in attendeeUids {
                let attendeeRef = roomRef.collection("attendees").document(attendeeUid)
                let attendeeSnap: DocumentSnapshot
                do { attendeeSnap = try tx.getDocument(attendeeRef) }
                catch { errPtr?.pointee = error as NSError; return nil }

                guard attendeeSnap.exists, let data = attendeeSnap.data() else {
                    continue
                }

                let deposit = data["depositHoney"] as? Int ?? 0
                let claimRef = roomRef.collection("raidClaims").document(attendeeUid)
                let raidCost = (room["fixedRaidCost"] as? Int)
                    ?? (room["minBid"] as? Int)
                    ?? 10

                if deposit < raidCost {
                    continue
                }

                let claimData: [String: Any] = [
                    "hostUid": uid,
                    "hostName": hostName,
                    "attendeeUid": attendeeUid,
                    "raidCostHoney": raidCost,
                    "status": "pending",
                    "createdAt": now,
                    "updatedAt": now,
                    "expiresAt": expiresAt
                ]

                tx.setData(claimData, forDocument: claimRef, merge: true)
            }

            let roomUpdates: [String: Any] = [
                "lastSuccessfulRaidAt": now,
                "updatedAt": now
            ]
            tx.updateData(roomUpdates, forDocument: roomRef)

            return nil
        }
    }

    // MARK: - Settle raid claim (attendee only, client-side for dev)
    func settleRaidClaim(roomId: String, attendeeUid: String, accept: Bool) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw RoomActionError.notSignedIn }
        guard uid == attendeeUid else { throw RoomActionError.notInRoom }

        let roomRef = db.collection("rooms").document(roomId)
        let claimRef = roomRef.collection("raidClaims").document(attendeeUid)
        let attendeeRef = roomRef.collection("attendees").document(attendeeUid)
        let now = Timestamp(date: Date())

        try await db.runTransaction { [self] tx, errPtr -> Any? in
            let claimSnap: DocumentSnapshot
            do { claimSnap = try tx.getDocument(claimRef) }
            catch { errPtr?.pointee = error as NSError; return nil }

            guard let claim = claimSnap.data() else { return nil }
            let status = claim["status"] as? String ?? ""
            if status != "pending" { return nil }

            let hostUid = claim["hostUid"] as? String ?? ""
            let raidCostHoney = (claim["raidCostHoney"] as? Int)
                ?? (claim["bidHoney"] as? Int)
                ?? 0
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
            }

            if accept, attendeeSnap.exists {
                tx.updateData([
                    "depositHoney": max(0, attendeeDeposit - raidCostHoney),
                    "updatedAt": now
                ], forDocument: attendeeRef)
            }

            tx.updateData([
                "status": accept ? "accepted" : "declined",
                "respondedAt": now,
                "transferredAt": now,
                "updatedAt": now
            ], forDocument: claimRef)

            return nil
        }
    }
}
