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
    @Published private(set) var pendingRaidClaim: RaidClaim? = nil
    @Published private(set) var pendingClaimAttendeeIds: Set<String> = []
    
    // Sorting / presentation
    enum AttendeeSort: String, CaseIterable, Identifiable {
        case depositHighToLow = "Deposit (High → Low)"
        case starsHighToLow = "Stars (High → Low)"
        case joinedOldToNew = "Joined (Old → New)"
        
        var id: String { rawValue }

        var localizedKey: String {
            switch self {
            case .depositHighToLow: return "room_sort_bid"
            case .starsHighToLow: return "room_sort_stars"
            case .joinedOldToNew: return "room_sort_joined"
            }
        }
    }
    
    @Published var attendeeSort: AttendeeSort = .depositHighToLow
    @Published var showJoinLimitAlert: Bool = false
    @Published var joinLimitMessage: String = ""
    
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
            if role == .host {
                pendingClaimAttendeeIds = try await repo.fetchPendingRaidClaimAttendeeIds(roomId: roomId)
            } else {
                pendingClaimAttendeeIds = []
            }
            sortAttendees(by: attendeeSort)
        } catch {
            print("❌ RoomDetails load error:", error)
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func loadPendingRaidClaim() async {
        guard let uid = session.authUid else { return }
        do {
            let claim = try await repo.fetchPendingRaidClaim(roomId: roomId, attendeeUid: uid)
            if let claim, let expiresAt = claim.expiresAt, expiresAt <= Date() {
                try await actions.settleRaidClaim(roomId: roomId, attendeeUid: uid, accept: true)
                pendingRaidClaim = nil
            } else {
                pendingRaidClaim = claim
            }
        } catch {
            print("❌ loadPendingRaidClaim error:", error)
        }
    }

    func respondToRaidClaim(accept: Bool) async {
        guard let uid = session.authUid else { return }
        do {
            try await actions.settleRaidClaim(roomId: roomId, attendeeUid: uid, accept: accept)
            pendingRaidClaim = nil
            await load()
        } catch {
            print("❌ respondToRaidClaim error:", error)
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
    
    func refreshRoleState() {
        // Call this if session changes (login, profile name updated, etc.)
        recomputeRoleAndCapabilities()
    }
    
    // MARK: Actions (stubbed, later map to Firestore transactions)
    
    /// Viewer -> Attendee
    func join(initialDeposit: Honey) async {
        guard let room else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let trimmedDeposit = max(0, initialDeposit)
            let minimum = max(1, room.fixedRaidCost)
            guard trimmedDeposit >= minimum else {
                errorMessage = String(format: NSLocalizedString("room_error_min_deposit", comment: ""), minimum)
                return
            }
            guard session.canAffordHoney(trimmedDeposit) else {
                errorMessage = String(format: NSLocalizedString("room_error_not_enough_honey", comment: ""), session.honey)
                return
            }
            let friendCode = session.friendCode // digits only, from your SessionStore
            let balanceAfter = max(0, session.honey - trimmedDeposit)
            try await actions.joinRoom(
                roomId: room.id,
                initialDepositHoney: trimmedDeposit,
                userName: session.displayName,
                friendCode: friendCode,
                stars: session.stars,
                attendeeHoney: balanceAfter
            )
            _ = session.spendHoney(trimmedDeposit)
            await load() // refresh room + attendees
        } catch is CancellationError {
            return
        } catch {
            print("❌ join error:", error)
            if let actionError = error as? RoomActionError,
               case .maxJoinRoomsReached = actionError {
                joinLimitMessage = actionError.errorDescription ?? ""
                showJoinLimitAlert = true
            } else {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
    
    func leave() async {
        guard let room else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let currentDeposit = currentUserDepositHoney() ?? 0
            try await actions.leaveRoom(roomId: room.id, attendeeHoney: session.honey)
            if currentDeposit > 0 {
                session.addHoney(currentDeposit)
            }
            await load()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
    
    /// Attendee updates their deposit
    func updateDeposit(to deposit: Honey) async {
        guard let room else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let newDeposit = max(0, deposit)
            let minimum = max(1, room.fixedRaidCost)
            guard newDeposit >= minimum else {
                errorMessage = String(format: NSLocalizedString("room_error_min_deposit", comment: ""), minimum)
                return
            }
            let previousDeposit = currentUserDepositHoney() ?? 0
            let delta = newDeposit - previousDeposit

            if delta > 0 && !session.canAffordHoney(delta) {
                errorMessage = String(format: NSLocalizedString("room_error_need_more_honey", comment: ""), delta)
                return
            }

            let newBalance: Int
            if delta > 0 {
                newBalance = session.honey - delta
            } else if delta < 0 {
                newBalance = session.honey + (-delta)
            } else {
                newBalance = session.honey
            }

            try await actions.updateDeposit(roomId: room.id, depositHoney: newDeposit, attendeeHoney: newBalance)

            if delta > 0 {
                _ = session.spendHoney(delta)
            } else if delta < 0 {
                session.addHoney(-delta)
            }
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

    func finishRaid(attendeeIds: [String]) async {
        guard let room else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await actions.finishRaid(
                roomId: room.id,
                attendeeUids: attendeeIds
            )
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
        case .depositHighToLow:
            room.attendees.sort {
                if $0.depositHoney != $1.depositHoney { return $0.depositHoney > $1.depositHoney }
                // tie-break: stars
                if $0.stars != $1.stars { return $0.stars > $1.stars }
                // tie-break: joinedAt (earlier first)
                return ($0.joinedAt ?? .distantFuture) < ($1.joinedAt ?? .distantFuture)
            }
        case .starsHighToLow:
            room.attendees.sort {
                if $0.stars != $1.stars { return $0.stars > $1.stars }
                if $0.depositHoney != $1.depositHoney { return $0.depositHoney > $1.depositHoney }
                return ($0.joinedAt ?? .distantFuture) < ($1.joinedAt ?? .distantFuture)
            }
        case .joinedOldToNew:
            room.attendees.sort {
                ($0.joinedAt ?? .distantFuture) < ($1.joinedAt ?? .distantFuture)
            }
        }
        
        self.room = room
    }

    var currentUserId: String? {
        session.authUid
    }

    func currentUserDepositHoney() -> Honey? {
        guard let room, let uid = session.authUid else { return nil }
        return room.attendees.first(where: { $0.id == uid })?.depositHoney
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
    
}
