//
//  RoomDetailsViewModel.swift
//  mushroomHunter
//
//  Purpose:
//  - Owns room details screen state, loading, and room action orchestration.
//
//  Defined in this file:
//  - RoomDetailsViewModel async data flow and action handlers.
//
import SwiftUI
import Combine

// MARK: - ViewModel

@MainActor
final class RoomDetailsViewModel: ObservableObject {
    
    // UI state
    @Published private(set) var room: RoomDetail? // State or dependency property.
    @Published private(set) var isLoading: Bool = false // State or dependency property.
    @Published var errorMessage: String? = nil // State or dependency property.
    @Published private(set) var pendingConfirmationAttendeeIds: Set<String> = [] // State or dependency property.
    @Published private(set) var rejectedConfirmationAttendeeIds: Set<String> = [] // State or dependency property.
    @Published private(set) var pendingConfirmationForCurrentUser: Bool = false // State or dependency property.
    @Published private(set) var hostPendingRatingAttendeeIds: Set<String> = [] // State or dependency property.    
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
    
    @Published var attendeeSort: AttendeeSort = .depositHighToLow // State or dependency property.
    @Published var showJoinLimitAlert: Bool = false // State or dependency property.
    @Published var joinLimitMessage: String = "" // State or dependency property.    
    // Derived role
    @Published private(set) var role: RoomRole = .viewer // State or dependency property.    
    // Dependencies
    private let roomId: String
    private unowned let session: SessionStore
    private let repo = FirebaseRoomDetailsRepository()
    private let actions = FirebaseRoomActionsRepository()
    
    // MARK: Init
    
    init(roomId: String, session: SessionStore) { // Initializes this type.
        self.roomId = roomId
        self.session = session
        if AppTesting.useMockRooms, roomId == AppTesting.fixtureRoomId {
            self.room = AppTesting.fixtureRoom(includeCurrentUser: false)
            recomputeRole()
            recomputeConfirmationStates()
            sortAttendees(by: attendeeSort)
        }
    }
    
    // MARK: Public API
    
    func load() async { // Handles load flow.
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        if AppTesting.useMockRooms, roomId == AppTesting.fixtureRoomId {
            let includeCurrentUser = false
            self.room = AppTesting.fixtureRoom(includeCurrentUser: includeCurrentUser)
            recomputeRole()
            recomputeConfirmationStates()
            sortAttendees(by: attendeeSort)
            return
        }
        
        do {
            let fetchedRoom = try await repo.fetchRoom(roomId: roomId)
            let attendees = try await repo.fetchAttendees(roomId: roomId)
            
            var merged = fetchedRoom
            merged.attendees = attendees
            self.room = merged
            
            recomputeRole()
            recomputeConfirmationStates()
            sortAttendees(by: attendeeSort)
        } catch {
            print("❌ RoomDetails load error:", error)
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    @discardableResult
    func respondToRaidConfirmation(accept: Bool) async -> Bool { // Handles respondToRaidConfirmation flow.
        guard let uid = session.authUid else { return false }
        do {
            try await actions.respondToRaidConfirmation(roomId: roomId, attendeeUid: uid, accept: accept)
            await load()
            return true
        } catch {
            print("❌ respondToRaidConfirmation error:", error)
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func rateHost(stars: Int) async { // Handles rateHost flow.
        guard let room, let uid = session.authUid else { return }
        do {
            try await actions.rateHostAfterConfirmation(roomId: room.id, attendeeUid: uid, stars: stars)
            await load()
            await session.refreshProfileFromBackend()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func rateAttendee(attendeeId: String, stars: Int) async { // Handles rateAttendee flow.
        guard let room else { return }
        do {
            try await actions.rateAttendeeAfterConfirmation(roomId: room.id, attendeeUid: attendeeId, stars: stars)
            await load()
            await session.refreshProfileFromBackend()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
    
    var canJoin: Bool {
        guard let room else { return false }
        return role == .viewer && room.attendees.count < room.maxPlayers
    }

    func isWaitingConfirmation(attendeeId: String) -> Bool { // Handles isWaitingConfirmation flow.
        pendingConfirmationAttendeeIds.contains(attendeeId)
    }

    func isRejectedConfirmation(attendeeId: String) -> Bool { // Handles isRejectedConfirmation flow.
        rejectedConfirmationAttendeeIds.contains(attendeeId)
    }

    func attendeeById(_ attendeeId: String) -> RoomAttendee? { // Handles attendeeById flow.
        room?.attendees.first(where: { $0.id == attendeeId })
    }

    func resendRejectedConfirmation(attendeeId: String) async { // Handles resendRejectedConfirmation flow.
        guard let room else { return }
        do {
            try await actions.resendRejectedConfirmation(roomId: room.id, attendeeUid: attendeeId)
            await load()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func giveUpRejectedConfirmation(attendeeId: String) async { // Handles giveUpRejectedConfirmation flow.
        guard let room else { return }
        do {
            try await actions.giveUpRejectedConfirmation(roomId: room.id, attendeeUid: attendeeId)
            await load()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
    
    // MARK: Actions
    
    /// Viewer -> Attendee
    func join(initialDeposit: Honey) async { // Handles join flow.
        guard let room else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        if AppTesting.useMockRooms, room.id == AppTesting.fixtureRoomId {
            let trimmedDeposit = max(0, initialDeposit)
            guard trimmedDeposit >= max(AppConfig.Mushroom.minFixedRaidCost, room.fixedRaidCost) else {
                errorMessage = String(format: NSLocalizedString("room_error_min_deposit", comment: ""), room.fixedRaidCost)
                return
            }
            guard session.canAffordHoney(trimmedDeposit) else {
                errorMessage = String(format: NSLocalizedString("room_error_not_enough_honey", comment: ""), session.honey)
                return
            }

            _ = session.spendHoney(trimmedDeposit)
            self.room = AppTesting.fixtureRoom(includeCurrentUser: true)
            recomputeRole()
            recomputeConfirmationStates()
            sortAttendees(by: attendeeSort)
            return
        }
        
        do {
            let trimmedDeposit = max(0, initialDeposit)
            let minimum = max(AppConfig.Mushroom.minFixedRaidCost, room.fixedRaidCost)
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
    
    func leave() async { // Handles leave flow.
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
    func updateDeposit(to deposit: Honey) async { // Handles updateDeposit flow.
        guard let room else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let newDeposit = max(0, deposit)
            let minimum = max(AppConfig.Mushroom.minFixedRaidCost, room.fixedRaidCost)
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
    func kick(attendeeId: String) async { // Handles kick flow.
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
    
    func closeRoom() async { // Handles closeRoom flow.
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

    func finishRaid(attendeeIds: [String]) async { // Handles finishRaid flow.
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
    
    func sortAttendees(by mode: AttendeeSort) { // Handles sortAttendees flow.
        guard var room else { return }
        
        attendeeSort = mode

        let hostId = room.hostId
        let hostAttendee = room.attendees.first(where: { $0.id == hostId })
        var others = room.attendees.filter { $0.id != hostId }

        switch mode {
        case .depositHighToLow:
            others.sort {
                if $0.depositHoney != $1.depositHoney { return $0.depositHoney > $1.depositHoney }
                if $0.stars != $1.stars { return $0.stars > $1.stars }
                return ($0.joinedAt ?? .distantFuture) < ($1.joinedAt ?? .distantFuture)
            }
        case .starsHighToLow:
            others.sort {
                if $0.stars != $1.stars { return $0.stars > $1.stars }
                if $0.depositHoney != $1.depositHoney { return $0.depositHoney > $1.depositHoney }
                return ($0.joinedAt ?? .distantFuture) < ($1.joinedAt ?? .distantFuture)
            }
        case .joinedOldToNew:
            others.sort {
                ($0.joinedAt ?? .distantFuture) < ($1.joinedAt ?? .distantFuture)
            }
        }

        if let hostAttendee {
            room.attendees = [hostAttendee] + others
        } else {
            room.attendees = others
        }
        
        self.room = room
    }

    var currentUserId: String? {
        session.authUid
    }

    func currentUserDepositHoney() -> Honey? { // Handles currentUserDepositHoney flow.
        guard let room, let uid = session.authUid else { return nil }
        guard uid != room.hostId else { return nil }
        return room.attendees.first(where: { $0.id == uid })?.depositHoney
    }
    
    // MARK: Private helpers
    private func recomputeRole() {
        guard let room else {
            role = .viewer
            return
        }
        
        let uid = session.authUid
        
        if let uid, uid == room.hostId {
            role = .host
        } else if let uid, room.attendees.contains(where: { $0.id == uid }) {
            role = .attendee
        } else {
            role = .viewer
        }
    }

    private func recomputeConfirmationStates() {
        guard let room else {
            pendingConfirmationAttendeeIds = []
            rejectedConfirmationAttendeeIds = []
            pendingConfirmationForCurrentUser = false
            hostPendingRatingAttendeeIds = []
            return
        }

        let pending = room.attendees
            .filter { $0.status == .waitingConfirmation }
            .map { $0.id }
        let rejected = room.attendees
            .filter { $0.status == .rejected }
            .map { $0.id }

        pendingConfirmationAttendeeIds = Set(pending)
        rejectedConfirmationAttendeeIds = Set(rejected)
        hostPendingRatingAttendeeIds = Set(
            room.attendees
                .filter { $0.status != .host && $0.needsHostRating }
                .map(\.id)
        )

        if let uid = session.authUid,
           let me = room.attendees.first(where: { $0.id == uid }) {
            pendingConfirmationForCurrentUser = (me.status == .waitingConfirmation)
        } else {
            pendingConfirmationForCurrentUser = false
        }
    }
    
}
