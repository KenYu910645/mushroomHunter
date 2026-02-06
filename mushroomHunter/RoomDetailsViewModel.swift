//
//  RoomDetailsViewModel.swift
//  mushroomHunter
//
//  Created by Ken on 4/2/2026.
//


import SwiftUI
import Combine

// MARK: - ViewModel

@MainActor
final class RoomDetailsViewModel: ObservableObject {

    // UI state
    @Published private(set) var room: RoomDetail?
    @Published private(set) var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    // Sorting / presentation
    enum AttendeeSort: String, CaseIterable, Identifiable {
        case bidHighToLow = "Bid (High → Low)"
        case starsHighToLow = "Stars (High → Low)"
        case joinedOldToNew = "Joined (Old → New)"

        var id: String { rawValue }
    }

    @Published var attendeeSort: AttendeeSort = .bidHighToLow

    // Derived: role + capabilities
    @Published private(set) var role: RoomRole = .viewer
    @Published private(set) var capabilities: RoomCapabilities = .init(
        canJoin: false, canLeave: false, canEditRoom: false, canKickAttendees: false, canUpdateBid: false
    )

    // Dependencies
    private let roomId: String
    private unowned let session: SessionStore
    private let repo = FirebaseRoomDetailsRepository()

    // MARK: Init

    init(roomId: String, session: SessionStore) {
        self.roomId = roomId
        self.session = session
    }

    // MARK: Public API

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let fetchedRoom = try await repo.fetchRoom(roomId: roomId)
            let attendees = try await repo.fetchAttendees(roomId: roomId)

            var merged = fetchedRoom
            merged.attendees = attendees
            self.room = merged

            recomputeRoleAndCapabilities()
            sortAttendees(by: attendeeSort)
        } catch {
            print("❌ RoomDetails load error:", error)
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func refreshRoleState() {
        // Call this if session changes (login, profile name updated, etc.)
        recomputeRoleAndCapabilities()
    }

    // MARK: Actions (stubbed, later map to Firestore transactions)

    /// Viewer -> Attendee
    func join(initialBid: Honey) async {
        guard let room else { return }
        guard capabilities.canJoin else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            // Later: Firestore transaction:
            // - ensure open
            // - ensure not full
            // - write joins/{uid} with bid
            // - increment joinedCount
            try await Task.sleep(nanoseconds: 250_000_000)

            var updated = room
            let uid = session.authUid ?? UUID().uuidString

            // prevent duplicates
            if updated.attendees.contains(where: { $0.id == uid }) {
                self.room = updated
                recomputeRoleAndCapabilities()
                return
            }

            guard updated.attendees.count < updated.maxPlayers else {
                throw NSError(domain: "Join", code: 409, userInfo: [NSLocalizedDescriptionKey: "Room is full"])
            }

            let attendee = RoomAttendee(
                id: uid,
                name: session.displayName,
                friendCode: session.friendCode, // digits-only
                stars: session.stars,
                bidHoney: max(0, initialBid),
                joinedAt: Date()
            )

            updated.attendees.append(attendee)
            self.room = updated

            recomputeRoleAndCapabilities()
            sortAttendees(by: attendeeSort)

        } catch {
            print("❌ join error:", error)
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Attendee -> Viewer
    func leave() async {
        guard let room else { return }
        guard capabilities.canLeave else { return }
        guard let uid = session.authUid else {
            errorMessage = "Not signed in."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            // Later: Firestore transaction:
            // - delete joins/{uid}
            // - decrement joinedCount
            try await Task.sleep(nanoseconds: 200_000_000)

            var updated = room
            updated.attendees.removeAll { $0.id == uid }
            self.room = updated

            recomputeRoleAndCapabilities()
            sortAttendees(by: attendeeSort)

        } catch {
            print("❌ leave error:", error)
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Attendee updates their bid
    func updateBid(to newBid: Honey) async {
        guard let room else { return }
        guard capabilities.canUpdateBid else { return }
        guard let uid = session.authUid else {
            errorMessage = "Not signed in."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            // Later: Firestore update:
            // - update joins/{uid}.bidHoney
            try await Task.sleep(nanoseconds: 200_000_000)

            var updated = room
            guard let idx = updated.attendees.firstIndex(where: { $0.id == uid }) else {
                throw NSError(domain: "Bid", code: 404, userInfo: [NSLocalizedDescriptionKey: "You are not in this room"])
            }

            updated.attendees[idx].bidHoney = max(0, newBid)
            self.room = updated

            sortAttendees(by: attendeeSort)

        } catch {
            print("❌ updateBid error:", error)
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Host kicks an attendee
    func kick(attendeeId: String) async {
        guard let room else { return }
        guard capabilities.canKickAttendees else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            // Later: Firestore transaction:
            // - delete joins/{attendeeId}
            // - decrement joinedCount
            try await Task.sleep(nanoseconds: 200_000_000)

            var updated = room
            updated.attendees.removeAll { $0.id == attendeeId }
            self.room = updated

            sortAttendees(by: attendeeSort)

        } catch {
            print("❌ kick error:", error)
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func sortAttendees(by mode: AttendeeSort) {
        guard var room else { return }

        attendeeSort = mode

        switch mode {
        case .bidHighToLow:
            room.attendees.sort {
                if $0.bidHoney != $1.bidHoney { return $0.bidHoney > $1.bidHoney }
                // tie-break: stars
                if $0.stars != $1.stars { return $0.stars > $1.stars }
                // tie-break: joinedAt (earlier first)
                return ($0.joinedAt ?? .distantFuture) < ($1.joinedAt ?? .distantFuture)
            }
        case .starsHighToLow:
            room.attendees.sort {
                if $0.stars != $1.stars { return $0.stars > $1.stars }
                if $0.bidHoney != $1.bidHoney { return $0.bidHoney > $1.bidHoney }
                return ($0.joinedAt ?? .distantFuture) < ($1.joinedAt ?? .distantFuture)
            }
        case .joinedOldToNew:
            room.attendees.sort {
                ($0.joinedAt ?? .distantFuture) < ($1.joinedAt ?? .distantFuture)
            }
        }

        self.room = room
    }

    // MARK: Private helpers

    private func recomputeRoleAndCapabilities() {
        guard let room else {
            role = .viewer
            capabilities = .derive(role: .viewer, room: Self.emptyRoom(roomId: roomId))
            return
        }

        // For now, we cannot reliably detect "host" without a hostUid in RoomDetail.
        // We'll treat: if session.displayName == hostName then host (MVP heuristic).
        // In Step 3 we should add hostUid to RoomDetail and remove this heuristic.
        let uid = session.authUid
        if let uid, room.attendees.contains(where: { $0.id == uid }) {
            role = .attendee
        } else if session.displayName == room.hostName {
            role = .host
        } else {
            role = .viewer
        }

        capabilities = .derive(role: role, room: room)
    }

    // MARK: Mock / placeholder

    private static func emptyRoom(roomId: String) -> RoomDetail {
        RoomDetail(
            id: roomId,
            title: "Room",
            hostName: "Host",
            hostStars: 0,
            targetMushroom: .init(color: .Red, attribute: .Normal, size: .Normal),
            lastSuccessfulRaidAt: nil,
            attendees: [],
            maxPlayers: 10,
            status: .open
        )
    }

    static func mockRoom(roomId: String) -> RoomDetail {
        RoomDetail(
            id: roomId,
            title: "Taichung Riverside Hunt",
            hostName: "Ken",
            hostStars: 12,
            targetMushroom: .init(color: .Red, attribute: .Fire, size: .Normal),
            lastSuccessfulRaidAt: Date().addingTimeInterval(-24 * 60 * 60), // 24h ago
            attendees: [
                .init(id: "u1", name: "Mia",  friendCode: "123456782345", stars: 8,  bidHoney: 15, joinedAt: Date().addingTimeInterval(-3600)),
                .init(id: "u2", name: "Ray",  friendCode: "999900001111", stars: 3,  bidHoney: 5,  joinedAt: Date().addingTimeInterval(-4000)),
                .init(id: "u3", name: "Lulu", friendCode: "111122223333", stars: 20, bidHoney: 12, joinedAt: Date().addingTimeInterval(-2000)),
            ],
            maxPlayers: 10,
            status: .open
        )
    }
}
