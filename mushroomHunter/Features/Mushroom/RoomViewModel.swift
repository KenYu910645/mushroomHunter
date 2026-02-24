//
//  RoomViewModel.swift
//  mushroomHunter
//
//  Purpose:
//  - Owns room details screen state, loading, and room action orchestration.
//
//  Defined in this file:
//  - RoomViewModel async data flow and action handlers.
//
import SwiftUI
import Combine

// MARK: - ViewModel

@MainActor
final class RoomViewModel: ObservableObject {
    
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
    private unowned let session: UserSessionStore
    private let repo = FbRoomRepo()
    private let actions = FbRoomActionsRepo()
    private let cache = AppDataCache.shared // Shared app-level cache used for stale-first room detail loading.
    
    // MARK: Init
    
    init(roomId: String, session: UserSessionStore) { // Initializes this type.
        self.roomId = roomId
        self.session = session
        if AppTesting.useMockRooms, roomId == AppTesting.fixtureRoomId {
            self.room = AppTesting.fixtureRoom(includeCurrentUser: AppTesting.useMockJoinedRoom)
            recomputeRole()
            recomputeConfirmationStates()
            sortAttendees(by: attendeeSort)
        }
    }
    
    // MARK: Public API
    
    func load(forceRefresh isForceRefresh: Bool = false) async { // Handles load flow.
        if !isForceRefresh, await loadRoomFromCache() {
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        if AppTesting.useMockRooms, roomId == AppTesting.fixtureRoomId {
            let includeCurrentUser = AppTesting.useMockJoinedRoom
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
            await cache.save(merged, key: roomCacheKey(roomId: roomId))
            
            recomputeRole()
            recomputeConfirmationStates()
            sortAttendees(by: attendeeSort)
        } catch {
            print("❌ RoomDetails load error:", error)
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    @discardableResult
    func respondToRaidConfirmation(confirmationId: String, settlementOutcome: RaidSettlementOutcome) async -> Bool { // Handles respondToRaidConfirmation flow.
        guard let uid = session.authUid else { return false }
        do {
            try await actions.respondToRaidConfirmation(
                roomId: roomId,
                attendeeUid: uid,
                confirmationId: confirmationId,
                settlementOutcome: settlementOutcome
            )
            await load(forceRefresh: true)
            return true
        } catch {
            print("❌ respondToRaidConfirmation error:", error)
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    /// Returns attendee ids that should receive escrow settlement requests for this raid.
    func raidSettlementTargetAttendeeIds() -> [String] { // Handles raidSettlementTargetAttendeeIds flow.
        guard let room else { return [] }
        return room.attendees
            .filter { attendee in
                attendee.status != .host &&
                attendee.status != .askingToJoin &&
                attendee.depositHoney >= room.fixedRaidCost
            }
            .map(\.id)
    }

    func rateHost(stars: Int) async { // Handles rateHost flow.
        guard let room, let uid = session.authUid else { return }
        do {
            try await actions.rateHostAfterConfirmation(roomId: room.id, attendeeUid: uid, stars: stars)
            await load(forceRefresh: true)
            await session.refreshProfileFromBackend()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func rateAttendee(attendeeId: String, stars: Int) async { // Handles rateAttendee flow.
        guard let room else { return }
        do {
            try await actions.rateAttendeeAfterConfirmation(roomId: room.id, attendeeUid: attendeeId, stars: stars)
            await load(forceRefresh: true)
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

    func isAskingToJoin(attendeeId: String) -> Bool { // Handles isAskingToJoin flow.
        attendeeById(attendeeId)?.status == .askingToJoin
    }

    func attendeeById(_ attendeeId: String) -> RoomAttendee? { // Handles attendeeById flow.
        room?.attendees.first(where: { $0.id == attendeeId })
    }

    func resendRejectedConfirmation(attendeeId: String) async { // Handles resendRejectedConfirmation flow.
        guard let room else { return }
        do {
            try await actions.resendRejectedConfirmation(roomId: room.id, attendeeUid: attendeeId)
            await load(forceRefresh: true)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func giveUpRejectedConfirmation(attendeeId: String) async { // Handles giveUpRejectedConfirmation flow.
        guard let room else { return }
        do {
            try await actions.giveUpRejectedConfirmation(roomId: room.id, attendeeUid: attendeeId)
            await load(forceRefresh: true)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func approveJoinApplication(attendeeId: String) async { // Handles approveJoinApplication flow.
        guard let room else { return }
        do {
            try await actions.approveJoinApplication(roomId: room.id, attendeeUid: attendeeId)
            await load(forceRefresh: true)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func rejectJoinApplication(attendeeId: String) async { // Handles rejectJoinApplication flow.
        guard let room else { return }
        do {
            try await actions.rejectJoinApplication(roomId: room.id, attendeeUid: attendeeId)
            await load(forceRefresh: true)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
    
    // MARK: Actions
    
    /// Viewer -> Attendee
    func join(initialDeposit: Honey, greetingMessage: String) async { // Handles join flow.
        guard let room else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let trimmedGreetingMessage = greetingMessage.trimmingCharacters(in: .whitespacesAndNewlines)

        if AppTesting.useMockRooms, room.id == AppTesting.fixtureRoomId {
            let trimmedDeposit = max(0, initialDeposit)
            guard trimmedDeposit >= max(AppConfig.Mushroom.minFixedRaidCost, room.fixedRaidCost) else {
                errorMessage = String(format: NSLocalizedString("room_error_min_deposit", comment: ""), room.fixedRaidCost)
                return
            }
            guard !trimmedGreetingMessage.isEmpty else {
                errorMessage = NSLocalizedString("room_error_enter_greeting", comment: "")
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
            guard !trimmedGreetingMessage.isEmpty else {
                errorMessage = NSLocalizedString("room_error_enter_greeting", comment: "")
                return
            }
            guard session.canAffordHoney(trimmedDeposit) else {
                errorMessage = String(format: NSLocalizedString("room_error_not_enough_honey", comment: ""), session.honey)
                return
            }
            let friendCode = session.friendCode // digits only, from your UserSessionStore
            let balanceAfter = max(0, session.honey - trimmedDeposit)
            try await actions.joinRoom(
                roomId: room.id,
                initialDepositHoney: trimmedDeposit,
                greetingMessage: trimmedGreetingMessage,
                userName: session.displayName,
                friendCode: friendCode,
                stars: session.stars,
                attendeeHoney: balanceAfter
            )
            _ = session.spendHoney(trimmedDeposit)
            await load(forceRefresh: true) // refresh room + attendees
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

        if AppTesting.useMockRooms, room.id == AppTesting.fixtureRoomId {
            let currentDeposit = currentUserDepositHoney() ?? 0
            if currentDeposit > 0 {
                session.addHoney(currentDeposit)
            }
            self.room = AppTesting.fixtureRoom(includeCurrentUser: false)
            recomputeRole()
            recomputeConfirmationStates()
            sortAttendees(by: attendeeSort)
            return
        }
        
        do {
            let currentDeposit = currentUserDepositHoney() ?? 0
            try await actions.leaveRoom(roomId: room.id, attendeeHoney: session.honey)
            if currentDeposit > 0 {
                session.addHoney(currentDeposit)
            }
            await load(forceRefresh: true)
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
            await load(forceRefresh: true)
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
            await load(forceRefresh: true)
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
            await cache.remove(key: roomCacheKey(roomId: room.id))
            self.room = nil
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
            let allNonHostAttendeeUids = room.attendees
                .filter { $0.status != .host }
                .map(\.id)
            try await actions.finishRaid(
                roomId: room.id,
                attendeeUids: attendeeIds,
                allNonHostAttendeeUids: allNonHostAttendeeUids
            )
            await load(forceRefresh: true)
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
        session.authUid ?? (AppTesting.useMockRooms ? AppTesting.userId : nil)
    }

    func currentUserDepositHoney() -> Honey? { // Handles currentUserDepositHoney flow.
        guard let room, let uid = currentUserId else { return nil }
        guard uid != room.hostId else { return nil }
        return room.attendees.first(where: { $0.id == uid })?.depositHoney
    }

    var isCurrentUserAllowedToEditDeposit: Bool {
        currentUserAttendeeStatus == .ready
    }

    private var currentUserAttendeeStatus: AttendeeStatus? {
        guard let room, let uid = currentUserId else { return nil }
        return room.attendees.first(where: { $0.id == uid })?.status
    }

    /// Returns current user pending confirmation queue from latest to oldest.
    func currentUserPendingConfirmationQueueLatestFirst() -> [(id: String, requestedAt: Date)] {
        guard let room, let uid = currentUserId else { return [] }
        guard let attendee = room.attendees.first(where: { $0.id == uid }) else { return [] }
        let queue = attendee.pendingConfirmationQueueLatestFirst
        if queue.isEmpty, attendee.status == .waitingConfirmation {
            return [
                (
                    id: "legacy-\(attendee.id)",
                    requestedAt: room.lastSuccessfulRaidAt ?? attendee.joinedAt ?? Date.distantPast
                )
            ]
        }
        return queue
    }
    
    // MARK: Private helpers
    private func recomputeRole() {
        guard let room else {
            role = .viewer
            return
        }
        
        let uid = currentUserId
        
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
            .filter { $0.isWaitingConfirmation }
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

        if let uid = currentUserId,
           let me = room.attendees.first(where: { $0.id == uid }) {
            pendingConfirmationForCurrentUser = me.isWaitingConfirmation
        } else {
            pendingConfirmationForCurrentUser = false
        }
    }

    /// Returns the stable cache key for one room detail payload.
    /// - Parameter roomId: Target room identifier.
    /// - Returns: Namespaced cache key.
    private func roomCacheKey(roomId: String) -> String {
        "mushroom.room.detail.\(roomId)"
    }

    /// Applies cached room payload when available.
    /// - Returns: `true` when cached room was loaded into view-model state.
    private func loadRoomFromCache() async -> Bool {
        guard let payload = await cache.load(key: roomCacheKey(roomId: roomId), as: RoomDetail.self) else {
            return false
        }
        room = payload.value
        errorMessage = nil
        recomputeRole()
        recomputeConfirmationStates()
        sortAttendees(by: attendeeSort)
        return true
    }
    
}
