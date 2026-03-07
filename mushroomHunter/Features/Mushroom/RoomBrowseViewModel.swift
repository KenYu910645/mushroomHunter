//
//  RoomBrowseViewModel.swift
//  mushroomHunter
//
//  Purpose:
//  - Holds browse-screen state and actions for room listings and joins.
//
//  Defined in this file:
//  - RoomBrowseViewModel.
//
import Foundation
import SwiftUI
import Combine

/// View model for the Mushroom browse screen.
@MainActor
final class RoomBrowseViewModel: ObservableObject {
    /// Ownership tag displayed for pinned user-related room rows in browse list.
    enum OwnershipTag {
        /// Room where current user joined as attendee.
        case joined
        /// Room where current user is the host.
        case host

        /// Localized title key shown in the ownership tag chip.
        var titleKey: LocalizedStringKey {
            switch self {
            case .joined:
                return LocalizedStringKey("browse_tag_joined")
            case .host:
                return LocalizedStringKey("browse_tag_host")
            }
        }
    }

    @Published var listings: [RoomListing] = [] // Raw room data fetched from backend/mock source.
    @Published var pinnedListings: [RoomListing] = [] // Joined/hosted rooms that must stay at top of browse list.
    @Published var isLoading: Bool = false // True while fetching listings or executing a join action.
    @Published var errorMessage: String? = nil // User-facing fetch/join error text shown in list section.
    @Published var showJoinLimitAlert: Bool = false // Controls presentation of "max joined rooms reached" alert.
    @Published var joinLimitMessage: String = "" // Message body shown in join-limit alert.

    @Published var query: String = "" // Free-text query used by local filter.
    @Published var showOnlyAvailable: Bool = true // When true, hide rooms that are already full.

    private let repo = FbRoomBrowseRepo() // Read-only room list source.
    private let profileRepo = FbProfileListRepo() // Joined/hosted room summary source for current user.
    private let actions = FbRoomActionsRepo() // Join action source (writes attendee/honey-related data).
    private unowned let session: UserSessionStore // Shared session state (honey, profile fields, limits).
    private let cache = RoomCache.shared // Shared Mushroom cache used for stale-first browse loading.
    private let dirtyBits = CacheDirtyBitStore.shared // Shared dirty-bit state used to force backend refresh after room mutations/events.
    private let browseCacheKey = "mushroom.browse.listings.v1" // Stable cache key for browse room listing payload.
    private var hostRoomIds: Set<String> = [] // Hosted room ids used for ownership tag lookup.
    private var joinedRoomIds: Set<String> = [] // Joined room ids used for ownership tag lookup.

    init(session: UserSessionStore) { // Initializes this type.
        self.session = session
    }

    /// Applies local tutorial scene data for first-entry Mushroom browse walkthrough.
    /// This bypasses Firebase and mirrors real browse-list composition.
    func loadMushroomBrowseTutorialScene() {
        isLoading = false
        errorMessage = nil
        showOnlyAvailable = true
        query = ""
        let tutorialScenario = TutorialConfig.MushroomBrowse.scenario
        hostRoomIds = tutorialScenario.hostRoomIds
        joinedRoomIds = tutorialScenario.joinedRoomIds

        let now = Date()
        let tutorialRows = tutorialScenario.fakeRooms.map { room in
            RoomListing(
                id: room.id,
                title: room.title,
                mushroomType: room.mushroomType,
                joinedPlayers: room.joinedPlayers,
                maxPlayers: room.maxPlayers,
                hostUid: room.hostUid,
                hostStars: room.hostStars,
                location: room.location,
                createdAt: now.addingTimeInterval(room.createdAtOffsetSeconds),
                lastSuccessfulRaidAt: now.addingTimeInterval(room.lastSuccessfulRaidAtOffsetSeconds),
                expiresAt: nil
            )
        }
        listings = tutorialRows
        pinnedListings = tutorialRows.filter { listing in
            hostRoomIds.contains(listing.id) || joinedRoomIds.contains(listing.id)
        }
    }

    /// Loads browse listings with stale-first strategy.
    /// Uses cache on enter and always follows with a server refresh.
    func loadListingsOnAppear() async { // Handles loadListingsOnAppear flow.
        let isBrowseDirty = await dirtyBits.isMushroomBrowseDirty()
        if isBrowseDirty {
            await fetchListings(forceRefresh: true)
            return
        }
        let isCacheLoaded = await loadListingsFromCache()
        if isCacheLoaded {
            await fetchListings(forceRefresh: true)
            return
        }
        await fetchListings(forceRefresh: true)
    }

    /// Fetches latest open room listings from backend (or fixture in UI-test mode).
    /// - Parameter isForceRefresh: `true` to always query Firestore and overwrite cache.
    func fetchListings(forceRefresh isForceRefresh: Bool = false) async { // Handles fetchListings flow.
        let isBrowseDirty = await dirtyBits.isMushroomBrowseDirty()
        let isShouldForceRefresh = isForceRefresh || isBrowseDirty
        if !isShouldForceRefresh, await loadListingsFromCache() {
            await refreshPinnedListings()
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        if AppTesting.useMockRooms {
            listings = [AppTesting.fixtureListing()]
            return
        }

        do {
            let docs = try await withTimeout(seconds: AppConfig.Network.requestTimeoutSeconds) {
                try await self.repo.fetchOpenListings(limit: AppConfig.Mushroom.browseListFetchLimit)
            }
            self.listings = docs
            await cache.save(docs, key: browseCacheKey)
            await dirtyBits.clearMushroomBrowseDirty()
            await refreshPinnedListings()
        } catch is CancellationError {
            // Normal: user pulled to refresh, view reloaded, or task replaced.
            return
        } catch {
            print("❌ fetchListings error:", error)
            self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            await refreshPinnedListings()
        }
    }

    /// Refreshes backend room listings when user confirms a search.
    /// Search filtering itself remains local on the fetched page.
    func performConfirmedSearch() async {
        await fetchListings(forceRefresh: true)
    }

    /// Attempts to join a room with user-entered honey deposit.
    ///
    /// Validation done here:
    /// - Deposit must be positive.
    /// - User must have enough honey balance.
    ///
    /// Side effects:
    /// - On success, spends honey locally and refreshes listing counts.
    /// - On max-join-limit error, surfaces dedicated alert state.
    func join(_ listing: RoomListing, deposit: Honey, greetingMessage: String) async { // Handles join flow.
        let trimmedGreetingMessage = greetingMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if AppTesting.useMockRooms {
            guard deposit > 0 else {
                let msg = NSLocalizedString("browse_error_enter_bid", comment: "")
                self.errorMessage = msg
                return
            }
            guard !trimmedGreetingMessage.isEmpty else {
                let message = NSLocalizedString("browse_error_enter_greeting", comment: "")
                self.errorMessage = message
                return
            }
            _ = session.spendHoney(deposit)
            return
        }

        let trimmedDeposit = max(0, deposit)
        guard trimmedDeposit > 0 else {
            let msg = NSLocalizedString("browse_error_enter_bid", comment: "")
            self.errorMessage = msg
            return
        }
        guard !trimmedGreetingMessage.isEmpty else {
            let message = NSLocalizedString("browse_error_enter_greeting", comment: "")
            self.errorMessage = message
            return
        }
        guard session.canAffordHoney(trimmedDeposit) else {
            let msg = String(format: NSLocalizedString("browse_error_not_enough_honey", comment: ""), session.honey)
            self.errorMessage = msg
            return
        }
        // Optimistically mark loading to disable UI if needed.
        isLoading = true
        defer { isLoading = false }
        do {
            try await withTimeout(seconds: AppConfig.Network.requestTimeoutSeconds) {
                let balanceAfter = max(0, self.session.honey - trimmedDeposit)
                try await self.actions.joinRoom(
                    roomId: listing.id,
                    initialDepositHoney: trimmedDeposit,
                    greetingMessage: trimmedGreetingMessage,
                    userName: self.session.displayName,
                    friendCode: self.session.friendCode,
                    stars: self.session.stars,
                    attendeeHoney: balanceAfter
                )
            }
            await dirtyBits.markMushroomBrowseDirty()
            await dirtyBits.markMushroomRoomDirty(roomId: listing.id)
            _ = session.spendHoney(trimmedDeposit)
            // Optionally refresh listings after joining to update counts.
            await fetchListings(forceRefresh: true)
        } catch {
            print("❌ join error:", error)
            if let actionError = error as? RoomActionError,
               case .maxJoinRoomsReached = actionError {
                self.joinLimitMessage = actionError.errorDescription ?? ""
                self.showJoinLimitAlert = true
            } else {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.errorMessage = message
            }
        }
    }

    /// Derived list shown by UI after applying:
    /// - availability filter
    /// - text search (title/location)
    var filteredListings: [RoomListing] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedQuery = trimmedQuery.lowercased()
        let visiblePinnedListings = pinnedListings.filter { listing in
            matchesBrowseFilters(for: listing, normalizedQuery: normalizedQuery)
        }
        let visibleListings = listings.filter { listing in
            matchesBrowseFilters(for: listing, normalizedQuery: normalizedQuery)
        }
        let pinnedListingIds = Set(visiblePinnedListings.map(\.id))
        let sortedVisibleListings = visibleListings
            .sorted(by: comparePriority)
            .filter { pinnedListingIds.contains($0.id) == false }
        return visiblePinnedListings + sortedVisibleListings
    }

    /// Returns ownership tag for a room id when current user belongs to that room.
    /// - Parameter roomId: Room id shown in browse row.
    /// - Returns: Ownership tag (`Joined` or `Host`) when applicable.
    func ownershipTag(for roomId: String) -> OwnershipTag? {
        if hostRoomIds.contains(roomId) {
            return .host
        }
        if joinedRoomIds.contains(roomId) {
            return .joined
        }
        return nil
    }

    /// Returns the best-effort role seed for room detail initial rendering.
    /// - Parameter roomId: Room id that will be opened.
    /// - Returns: Host/attendee role when browse ownership metadata is available.
    func roleSeed(for roomId: String) -> RoomRole? {
        switch ownershipTag(for: roomId) {
        case .host:
            return .host
        case .joined:
            return .attendee
        case .none:
            return nil
        }
    }

    /// Compares two listings using score-based browse priority.
    /// Higher score ranks earlier.
    private func comparePriority(_ lhs: RoomListing, _ rhs: RoomListing) -> Bool {
        let now = Date()
        let lhsScore = priorityScore(for: lhs, now: now)
        let rhsScore = priorityScore(for: rhs, now: now)
        if lhsScore != rhsScore { return lhsScore > rhsScore }

        let lhsCreatedAt = lhs.createdAt ?? .distantPast
        let rhsCreatedAt = rhs.createdAt ?? .distantPast
        if lhsCreatedAt != rhsCreatedAt { return lhsCreatedAt > rhsCreatedAt }

        return lhs.id < rhs.id
    }

    /// Returns browse priority score derived from host stars and dormancy age.
    /// Score formula:
    /// - reward: hostStars * host-star weight
    /// - penalty: hours beyond dormancy threshold * dormant-hour penalty
    /// No penalty is applied when dormancy is below threshold.
    private func priorityScore(for listing: RoomListing, now: Date) -> Double {
        let starReward = Double(listing.hostStars) * AppConfig.Mushroom.browsePriorityHostStarWeight
        let dormantPenalty = dormantPenaltyHours(for: listing, now: now) * AppConfig.Mushroom.browsePriorityDormantHourPenalty
        return starReward - dormantPenalty
    }

    /// Returns hours exceeded beyond dormancy threshold, or zero when still below threshold.
    private func dormantPenaltyHours(for listing: RoomListing, now: Date) -> Double {
        let referenceDate = listing.lastSuccessfulRaidAt ?? listing.createdAt ?? now
        let elapsedHours = now.timeIntervalSince(referenceDate) / 3600
        let thresholdHours = AppConfig.Mushroom.browsePriorityDormantThresholdHours
        return max(0, elapsedHours - thresholdHours)
    }

    /// Returns whether a listing should stay visible for the current browse filters.
    /// - Parameters:
    ///   - listing: Listing to validate against search and availability filters.
    ///   - normalizedQuery: Lowercased query text already trimmed by caller.
    /// - Returns: `true` when listing should remain visible in current browse results.
    private func matchesBrowseFilters(for listing: RoomListing, normalizedQuery: String) -> Bool {
        if showOnlyAvailable && listing.joinedPlayers >= listing.maxPlayers {
            return false
        }
        if normalizedQuery.isEmpty {
            return true
        }

        let localizedLocation = RoomLocationLocalization.displayLabel(forStoredLocation: listing.location).lowercased()
        return listing.title.lowercased().contains(normalizedQuery)
            || listing.location.lowercased().contains(normalizedQuery)
            || localizedLocation.contains(normalizedQuery)
    }

    /// Loads browse listings from app cache into current state.
    /// - Returns: `true` when cache existed and was applied.
    private func loadListingsFromCache() async -> Bool {
        guard let payload = await cache.load(key: browseCacheKey, as: [RoomListing].self) else {
            return false
        }
        listings = payload.value
        errorMessage = nil
        return true
    }

    /// Loads current user's joined/hosted rooms and keeps them pinned at browse top.
    private func refreshPinnedListings() async {
        guard AppTesting.isUITesting == false else {
            pinnedListings = []
            hostRoomIds = []
            joinedRoomIds = []
            return
        }
        guard session.isLoggedIn else {
            pinnedListings = []
            hostRoomIds = []
            joinedRoomIds = []
            return
        }

        do {
            async let hostedRoomSummariesLoad = profileRepo.fetchMyHostedRooms(limit: AppConfig.Mushroom.profileListFetchLimit)
            async let joinedRoomSummariesLoad = profileRepo.fetchMyJoinedRooms(limit: AppConfig.Mushroom.profileListFetchLimit)
            let hostedRoomSummaries = try await hostedRoomSummariesLoad
            let joinedRoomSummaries = try await joinedRoomSummariesLoad

            let hostedIds = hostedRoomSummaries.map(\.id)
            let joinedIds = joinedRoomSummaries.map(\.id)
            hostRoomIds = Set(hostedIds)
            joinedRoomIds = Set(joinedIds)

            let baseListingById = Dictionary(uniqueKeysWithValues: listings.map { ($0.id, $0) })
            let requestedPinnedIds = Array(Set(hostedIds + joinedIds))
            let missingPinnedIds = requestedPinnedIds.filter { baseListingById[$0] == nil }
            let extraPinnedListings = try await repo.fetchListings(roomIds: missingPinnedIds)
            let mergedListingById = baseListingById.merging(
                Dictionary(uniqueKeysWithValues: extraPinnedListings.map { ($0.id, $0) })
            ) { current, _ in
                current
            }
            var orderedPinnedListings: [RoomListing] = []
            var seenPinnedIds: Set<String> = []
            for roomId in hostedIds + joinedIds {
                guard seenPinnedIds.contains(roomId) == false else { continue }
                guard let listing = mergedListingById[roomId] else { continue }
                orderedPinnedListings.append(listing)
                seenPinnedIds.insert(roomId)
            }
            pinnedListings = orderedPinnedListings
        } catch {
            print("❌ refreshPinnedListings error:", error)
            pinnedListings = []
            hostRoomIds = []
            joinedRoomIds = []
        }
    }
}
