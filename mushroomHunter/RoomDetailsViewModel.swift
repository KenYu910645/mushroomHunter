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
    private let actions = FirebaseRoomActionsRepository()
    
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
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let friendCode = session.friendCode // digits only, from your SessionStore
            try await actions.joinRoom(
                roomId: room.id,
                initialBidHoney: initialBid,
                userName: session.displayName,
                friendCode: friendCode,
                stars: session.stars
            )
            await load() // refresh room + attendees
        } catch is CancellationError {
            return
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
    
    func leave() async {
        guard let room else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            try await actions.leaveRoom(roomId: room.id)
            await load()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
    
    /// Attendee updates their bid
    func updateBid(to bid: Honey) async {
        guard let room else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            try await actions.updateBid(roomId: room.id, bidHoney: bid)
            await load()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
    
    /// Host kicks an attendee
    func kick(attendeeId: String) async {
        guard let room else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            try await actions.kickAttendee(roomId: room.id, attendeeUid: attendeeId)
            await load()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
    
    func closeRoom() async {
        guard let room else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            try await actions.closeRoom(roomId: room.id)
            await load()
        } catch is CancellationError {
            return
        } catch {
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
            capabilities = .none
            return
        }
        
        let uid = session.authUid
        
        if let uid, uid == room.hostUid {
            role = .host
        } else if let uid, room.attendees.contains(where: { $0.id == uid }) {
            role = .attendee
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
            hostUid: "", // ✅ placeholder (unknown yet)
            hostName: "Host",
            hostStars: 0,
            targetMushroom: .init(color: .Red, attribute: .Normal, size: .Normal),
            lastSuccessfulRaidAt: nil,
            attendees: [],
            maxPlayers: 10,
            status: .open
        )
    }
}
