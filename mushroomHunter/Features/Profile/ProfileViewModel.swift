//
//  ProfileViewModel.swift
//  mushroomHunter
//
//  Purpose:
//  - Owns profile tab data loading state and repository interactions.
//
import Foundation
import Combine

/// View model that manages profile tab room/postcard collection state.
@MainActor
final class ProfileViewModel: ObservableObject {
    /// Hosted-room loading indicator state.
    @Published var isHostedRoomsLoading: Bool = false

    /// Hosted-room fetch error message.
    @Published var hostedRoomsErrorMessage: String? = nil

    /// Hosted-room summaries shown in profile.
    @Published var hostedRooms: [HostedRoomSummary] = []
    /// Pending join-request counts grouped by hosted room id.
    @Published var hostedPendingJoinRequestCountsByRoomId: [String: Int] = [:]

    /// Joined-room loading indicator state.
    @Published var isJoinedRoomsLoading: Bool = false

    /// Joined-room fetch error message.
    @Published var joinedRoomsErrorMessage: String? = nil

    /// Joined-room summaries shown in profile.
    @Published var joinedRooms: [JoinedRoomSummary] = []

    /// On-shelf postcard loading indicator state.
    @Published var isOnShelfPostcardsLoading: Bool = false

    /// On-shelf postcard fetch error message.
    @Published var onShelfPostcardsErrorMessage: String? = nil

    /// On-shelf postcard listings shown in profile.
    @Published var onShelfPostcards: [PostcardListing] = []

    /// On-shelf listing ids that currently have pending seller orders.
    @Published var onShelfPendingOrderPostcardIds: Set<String> = []
    /// Pending seller-order counts grouped by on-shelf postcard id.
    @Published var onShelfPendingOrderCountsByPostcardId: [String: Int] = [:]

    /// Ordered postcard loading indicator state.
    @Published var isOrderedPostcardsLoading: Bool = false

    /// Ordered postcard fetch error message.
    @Published var orderedPostcardsErrorMessage: String? = nil

    /// Ordered postcard summaries shown in profile.
    @Published var orderedPostcards: [OrderedPostcardSummary] = []

    /// Repository for room profile queries.
    private let hostRepo = FbProfileListRepo()

    /// Repository for postcard profile queries.
    private let postcardRepo = FbPostcardRepo()
    /// Shared app-level cache for profile list payloads.
    private let cache = AppDataCache.shared

    /// Snapshot payload used by app-level profile list cache.
    private struct ProfileListsCachePayload: Codable {
        /// Hosted-room summaries.
        let hostedRooms: [HostedRoomSummary]
        /// Joined-room summaries.
        let joinedRooms: [JoinedRoomSummary]
        /// Pending join-request counts grouped by hosted room id.
        let hostedPendingJoinRequestCountsByRoomId: [String: Int]
        /// On-shelf postcard listings.
        let onShelfPostcards: [PostcardListing]
        /// On-shelf postcard ids that currently have pending seller orders.
        let onShelfPendingOrderPostcardIds: [String]
        /// Pending seller-order counts grouped by on-shelf postcard id.
        let onShelfPendingOrderCountsByPostcardId: [String: Int]
        /// Ordered postcard summaries.
        let orderedPostcards: [OrderedPostcardSummary]
    }

    /// Loads profile sections on initial screen entry with cache-first strategy.
    /// - Parameter session: Current authenticated session.
    func loadOnAppear(session: UserSessionStore) async {
        if AppTesting.isUITesting {
            await resetForUITestingMode()
            return
        }
        _ = await loadListsFromCache(session: session)
        updateProfileActionBadgeCount(session: session)
        await refreshAllProfileData(session: session, forceRefresh: true)
    }

    /// Reloads profile backend fields and all room/postcard collections in parallel.
    func refreshAllProfileData(session: UserSessionStore, forceRefresh isForceRefresh: Bool = true) async {
        if AppTesting.isUITesting {
            await resetForUITestingMode()
            return
        }
        await session.refreshProfileFromBackend()
        async let joinedRoomsLoad: Void = loadJoinedRooms(session: session, forceRefresh: isForceRefresh)
        async let hostedRoomsLoad: Void = loadHostedRooms(session: session, forceRefresh: isForceRefresh)
        async let onShelfPostcardsLoad: Void = loadOnShelfPostcards(session: session, forceRefresh: isForceRefresh)
        async let orderedPostcardsLoad: Void = loadOrderedPostcards(session: session, forceRefresh: isForceRefresh)
        _ = await (joinedRoomsLoad, hostedRoomsLoad, onShelfPostcardsLoad, orderedPostcardsLoad)
        updateProfileActionBadgeCount(session: session)
        await persistListsCache(session: session)
    }

    /// Loads rooms hosted by the current user.
    func loadHostedRooms(session: UserSessionStore, forceRefresh isForceRefresh: Bool = false) async {
        if AppTesting.isUITesting { return }
        guard session.isLoggedIn else { return }
        if !isForceRefresh { return }

        isHostedRoomsLoading = true
        hostedRoomsErrorMessage = nil
        defer { isHostedRoomsLoading = false }

        do {
            hostedRooms = try await hostRepo.fetchMyHostedRooms(limit: AppConfig.Mushroom.profileListFetchLimit)
            hostedPendingJoinRequestCountsByRoomId = try await hostRepo.fetchHostPendingJoinRequestCounts(
                roomIds: hostedRooms.map { $0.id }
            )
            updateProfileActionBadgeCount(session: session)
            await persistListsCache(session: session)
        } catch is CancellationError {
            return
        } catch {
            print("❌ loadHostedRooms error:", error)
            hostedRoomsErrorMessage = resolvedErrorMessage(from: error)
            hostedPendingJoinRequestCountsByRoomId = [:]
        }
    }

    /// Loads rooms joined by the current user.
    func loadJoinedRooms(session: UserSessionStore, forceRefresh isForceRefresh: Bool = false) async {
        if AppTesting.isUITesting { return }
        guard session.isLoggedIn else { return }
        if !isForceRefresh { return }

        isJoinedRoomsLoading = true
        joinedRoomsErrorMessage = nil
        defer { isJoinedRoomsLoading = false }

        do {
            joinedRooms = try await hostRepo.fetchMyJoinedRooms(limit: AppConfig.Mushroom.profileListFetchLimit)
            updateProfileActionBadgeCount(session: session)
            await persistListsCache(session: session)
        } catch is CancellationError {
            return
        } catch {
            print("❌ loadJoinedRooms error:", error)
            joinedRoomsErrorMessage = resolvedErrorMessage(from: error)
        }
    }

    /// Loads active listings owned by the current user.
    func loadOnShelfPostcards(session: UserSessionStore, forceRefresh isForceRefresh: Bool = false) async {
        if AppTesting.isUITesting { return }
        guard let userId = session.authUid, userId.isEmpty == false else { return }
        if !isForceRefresh { return }

        isOnShelfPostcardsLoading = true
        onShelfPostcardsErrorMessage = nil
        defer { isOnShelfPostcardsLoading = false }

        do {
            async let listingsLoad: [PostcardListing] = postcardRepo.fetchMyListings(
                userId: userId,
                limit: AppConfig.Postcard.profileListFetchLimit
            )
            async let pendingOrderCountsLoad: [String: Int] = postcardRepo.fetchSellerPendingOrderCountsByPostcardId(
                userId: userId
            )
            onShelfPostcards = try await listingsLoad
            onShelfPendingOrderCountsByPostcardId = try await pendingOrderCountsLoad
            onShelfPendingOrderPostcardIds = Set(onShelfPendingOrderCountsByPostcardId.keys)
            updateProfileActionBadgeCount(session: session)
            await persistListsCache(session: session)
        } catch is CancellationError {
            return
        } catch {
            print("❌ loadOnShelfPostcards error:", error)
            onShelfPostcardsErrorMessage = resolvedErrorMessage(from: error)
            onShelfPendingOrderPostcardIds = []
            onShelfPendingOrderCountsByPostcardId = [:]
        }
    }

    /// Loads ordered postcards for the current user.
    func loadOrderedPostcards(session: UserSessionStore, forceRefresh isForceRefresh: Bool = false) async {
        if AppTesting.isUITesting { return }
        guard let userId = session.authUid, userId.isEmpty == false else { return }
        if !isForceRefresh { return }

        isOrderedPostcardsLoading = true
        orderedPostcardsErrorMessage = nil
        defer { isOrderedPostcardsLoading = false }

        do {
            orderedPostcards = try await postcardRepo.fetchMyOrderedPostcards(
                userId: userId,
                limit: AppConfig.Postcard.profileListFetchLimit
            )
            updateProfileActionBadgeCount(session: session)
            await persistListsCache(session: session)
        } catch is CancellationError {
            return
        } catch {
            print("❌ loadOrderedPostcards error:", error)
            orderedPostcardsErrorMessage = resolvedErrorMessage(from: error)
        }
    }

    /// Converts an error into the best available user-facing message.
    private func resolvedErrorMessage(from error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    /// Clears all profile section states for deterministic UI-test mode.
    private func resetForUITestingMode() async {
        hostedRooms = []
        joinedRooms = []
        onShelfPostcards = []
        onShelfPendingOrderPostcardIds = []
        onShelfPendingOrderCountsByPostcardId = [:]
        hostedPendingJoinRequestCountsByRoomId = [:]
        orderedPostcards = []
        hostedRoomsErrorMessage = nil
        joinedRoomsErrorMessage = nil
        onShelfPostcardsErrorMessage = nil
        orderedPostcardsErrorMessage = nil
        isHostedRoomsLoading = false
        isJoinedRoomsLoading = false
        isOnShelfPostcardsLoading = false
        isOrderedPostcardsLoading = false
    }

    /// Loads cached profile lists for the current user.
    /// - Parameter session: Active session used to derive cache namespace key.
    /// - Returns: `true` when cached payload existed and was applied.
    private func loadListsFromCache(session: UserSessionStore) async -> Bool {
        guard let payload = await cache.load(key: cacheKey(session: session), as: ProfileListsCachePayload.self) else {
            return false
        }
        hostedRooms = payload.value.hostedRooms
        joinedRooms = payload.value.joinedRooms
        hostedPendingJoinRequestCountsByRoomId = payload.value.hostedPendingJoinRequestCountsByRoomId
        onShelfPostcards = payload.value.onShelfPostcards
        onShelfPendingOrderPostcardIds = Set(payload.value.onShelfPendingOrderPostcardIds)
        onShelfPendingOrderCountsByPostcardId = payload.value.onShelfPendingOrderCountsByPostcardId
        orderedPostcards = payload.value.orderedPostcards

        hostedRoomsErrorMessage = nil
        joinedRoomsErrorMessage = nil
        onShelfPostcardsErrorMessage = nil
        orderedPostcardsErrorMessage = nil
        return true
    }

    /// Persists current profile list state into app-level cache.
    /// - Parameter session: Active session used to derive cache namespace key.
    private func persistListsCache(session: UserSessionStore) async {
        let payload = ProfileListsCachePayload(
            hostedRooms: hostedRooms,
            joinedRooms: joinedRooms,
            hostedPendingJoinRequestCountsByRoomId: hostedPendingJoinRequestCountsByRoomId,
            onShelfPostcards: onShelfPostcards,
            onShelfPendingOrderPostcardIds: Array(onShelfPendingOrderPostcardIds),
            onShelfPendingOrderCountsByPostcardId: onShelfPendingOrderCountsByPostcardId,
            orderedPostcards: orderedPostcards
        )
        await cache.save(payload, key: cacheKey(session: session))
    }

    /// Builds user-scoped cache key to prevent cross-account payload reuse.
    /// - Parameter session: Active user session.
    /// - Returns: Stable cache key string.
    private func cacheKey(session: UserSessionStore) -> String {
        let userId = session.authUid ?? "anonymous"
        return "profile.lists.\(userId).v3"
    }

    /// Recomputes aggregated actionable item count for profile-tab and app-icon badges.
    /// - Parameter session: Session object that stores the shared badge count.
    private func updateProfileActionBadgeCount(session: UserSessionStore) {
        let joinerPendingConfirmationCount = joinedRooms.reduce(0) { partial, room in
            let isWaitingConfirmation = room.attendeeStatus == .waitingConfirmation
            return partial + (isWaitingConfirmation ? 1 : 0)
        }
        let hostPendingJoinRequestCount = hostedPendingJoinRequestCountsByRoomId.values.reduce(0, +)
        let sellerPendingOrderCount = onShelfPendingOrderCountsByPostcardId.values.reduce(0, +)
        let buyerPendingReceiveCount = orderedPostcards.reduce(0) { partial, summary in
            let isWaitingBuyerReceive = summary.status == .shipped
            return partial + (isWaitingBuyerReceive ? 1 : 0)
        }
        let totalActionableCount = joinerPendingConfirmationCount
            + hostPendingJoinRequestCount
            + sellerPendingOrderCount
            + buyerPendingReceiveCount
        session.updateProfileActionBadgeCount(totalActionableCount)
    }
}
