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
        initialBidHoney: Int,
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

            let bid = max(0, initialBidHoney)
            if currentHoney < bid {
                errPtr?.pointee = RoomActionError.notEnoughHoney as NSError
                return nil
            }

            // 3) Write attendee
            tx.setData([
                "uid": uid,
                "name": userName,
                "friendCode": friendCode,
                "stars": stars,
                "bidHoney": bid,
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
                "honey": currentHoney - bid,
                "activeRoomId": roomId,
                "updatedAt": now
            ], forDocument: userRef)

            return nil
        }
    }

    // MARK: - Update bid (attendee only)
    func updateBid(roomId: String, bidHoney: Int, attendeeHoney: Int) async throws {
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

            let oldBid = attendee["bidHoney"] as? Int ?? 0
            let newBid = max(0, bidHoney)
            let delta = newBid - oldBid

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
                "bidHoney": newBid,
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

            let bid = attendeeSnap.data()?["bidHoney"] as? Int ?? 0

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

            // Refund bid
            tx.updateData([
                "honey": currentHoney + max(0, bid),
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

            tx.deleteDocument(attendeeRef)
            tx.updateData([
                "joinedCount": FieldValue.increment(Int64(-1)),
                "updatedAt": now
            ], forDocument: roomRef)

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

        try await roomRef.updateData([
            "status": "closed",
            "updatedAt": Timestamp(date: Date())
        ])
    }

    // MARK: - Finish raid (host only)
    func finishRaid(roomId: String, attendeeUids: [String], hostCurrentHoney: Int) async throws -> Int {
        guard let uid = Auth.auth().currentUser?.uid else { throw RoomActionError.notSignedIn }
        guard !attendeeUids.isEmpty else { return 0 }

        let roomRef = db.collection("rooms").document(roomId)
        let hostRef = db.collection("users").document(uid)
        let now = Timestamp(date: Date())

        let totalHoney = try await db.runTransaction { [self] tx, errPtr -> Any? in
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

            var total = 0
            var removedCount = 0
            let minBid = max(1, room["minBid"] as? Int ?? 10)

            let hostSnap: DocumentSnapshot
            do { hostSnap = try tx.getDocument(hostRef) }
            catch { errPtr?.pointee = error as NSError; return nil }

            let hostHoney: Int
            if let hostData = hostSnap.data() {
                hostHoney = hostData["honey"] as? Int ?? 0
            } else {
                hostHoney = max(0, hostCurrentHoney)
                tx.setData([
                    "displayName": "",
                    "friendCode": "",
                    "stars": 0,
                    "honey": hostHoney,
                    "createdAt": now,
                    "updatedAt": now
                ], forDocument: hostRef)
            }

            for attendeeUid in attendeeUids {
                let attendeeRef = roomRef.collection("attendees").document(attendeeUid)
                let userRef = self.db.collection("users").document(attendeeUid)
                let attendeeSnap: DocumentSnapshot
                do { attendeeSnap = try tx.getDocument(attendeeRef) }
                catch { errPtr?.pointee = error as NSError; return nil }

                guard attendeeSnap.exists, let data = attendeeSnap.data() else {
                    continue
                }

                let bid = data["bidHoney"] as? Int ?? 0
                let userSnap: DocumentSnapshot
                do { userSnap = try tx.getDocument(userRef) }
                catch { errPtr?.pointee = error as NSError; return nil }

                let honey = userSnap.data()?["honey"] as? Int ?? 0

                if honey < minBid {
                    tx.deleteDocument(attendeeRef)
                    removedCount += 1
                    continue
                }

                let newBid = max(minBid, min(bid, honey))
                total += newBid

                tx.updateData([
                    "bidHoney": newBid,
                    "updatedAt": now
                ], forDocument: attendeeRef)

                tx.updateData([
                    "honey": honey - newBid,
                    "updatedAt": now
                ], forDocument: userRef)
            }

            var roomUpdates: [String: Any] = [
                "lastSuccessfulRaidAt": now,
                "updatedAt": now
            ]
            if removedCount > 0 {
                roomUpdates["joinedCount"] = FieldValue.increment(Int64(-removedCount))
            }
            tx.updateData(roomUpdates, forDocument: roomRef)

            if total > 0 {
                tx.updateData([
                    "honey": hostHoney + total,
                    "updatedAt": now
                ], forDocument: hostRef)
            }

            return total
        }

        return totalHoney as? Int ?? 0
    }
}
