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

    /// Reloads profile backend fields and all room/postcard collections in parallel.
    func refreshAllProfileData(session: UserSessionStore) async {
        if AppTesting.isUITesting {
            hostedRooms = []
            joinedRooms = []
            onShelfPostcards = []
            onShelfPendingOrderPostcardIds = []
            orderedPostcards = []
            hostedRoomsErrorMessage = nil
            joinedRoomsErrorMessage = nil
            onShelfPostcardsErrorMessage = nil
            orderedPostcardsErrorMessage = nil
            isHostedRoomsLoading = false
            isJoinedRoomsLoading = false
            isOnShelfPostcardsLoading = false
            isOrderedPostcardsLoading = false
            return
        }
        await session.refreshProfileFromBackend()
        async let joinedRoomsLoad: Void = loadJoinedRooms(session: session)
        async let hostedRoomsLoad: Void = loadHostedRooms(session: session)
        async let onShelfPostcardsLoad: Void = loadOnShelfPostcards(session: session)
        async let orderedPostcardsLoad: Void = loadOrderedPostcards(session: session)
        _ = await (joinedRoomsLoad, hostedRoomsLoad, onShelfPostcardsLoad, orderedPostcardsLoad)
    }

    /// Loads rooms hosted by the current user.
    func loadHostedRooms(session: UserSessionStore) async {
        if AppTesting.isUITesting { return }
        guard session.isLoggedIn else { return }

        isHostedRoomsLoading = true
        hostedRoomsErrorMessage = nil
        defer { isHostedRoomsLoading = false }

        do {
            hostedRooms = try await hostRepo.fetchMyHostedRooms(limit: AppConfig.Mushroom.profileListFetchLimit)
        } catch is CancellationError {
            return
        } catch {
            print("❌ loadHostedRooms error:", error)
            hostedRoomsErrorMessage = resolvedErrorMessage(from: error)
        }
    }

    /// Loads rooms joined by the current user.
    func loadJoinedRooms(session: UserSessionStore) async {
        if AppTesting.isUITesting { return }
        guard session.isLoggedIn else { return }

        isJoinedRoomsLoading = true
        joinedRoomsErrorMessage = nil
        defer { isJoinedRoomsLoading = false }

        do {
            joinedRooms = try await hostRepo.fetchMyJoinedRooms(limit: AppConfig.Mushroom.profileListFetchLimit)
        } catch is CancellationError {
            return
        } catch {
            print("❌ loadJoinedRooms error:", error)
            joinedRoomsErrorMessage = resolvedErrorMessage(from: error)
        }
    }

    /// Loads active listings owned by the current user.
    func loadOnShelfPostcards(session: UserSessionStore) async {
        if AppTesting.isUITesting { return }
        guard let userId = session.authUid, userId.isEmpty == false else { return }

        isOnShelfPostcardsLoading = true
        onShelfPostcardsErrorMessage = nil
        defer { isOnShelfPostcardsLoading = false }

        do {
            async let listingsLoad: [PostcardListing] = postcardRepo.fetchMyListings(
                userId: userId,
                limit: AppConfig.Postcard.profileListFetchLimit
            )
            async let pendingOrderIdsLoad: Set<String> = postcardRepo.fetchSellerPendingOrderPostcardIds(
                userId: userId
            )
            onShelfPostcards = try await listingsLoad
            onShelfPendingOrderPostcardIds = try await pendingOrderIdsLoad
        } catch is CancellationError {
            return
        } catch {
            print("❌ loadOnShelfPostcards error:", error)
            onShelfPostcardsErrorMessage = resolvedErrorMessage(from: error)
            onShelfPendingOrderPostcardIds = []
        }
    }

    /// Loads ordered postcards for the current user.
    func loadOrderedPostcards(session: UserSessionStore) async {
        if AppTesting.isUITesting { return }
        guard let userId = session.authUid, userId.isEmpty == false else { return }

        isOrderedPostcardsLoading = true
        orderedPostcardsErrorMessage = nil
        defer { isOrderedPostcardsLoading = false }

        do {
            orderedPostcards = try await postcardRepo.fetchMyOrderedPostcards(
                userId: userId,
                limit: AppConfig.Postcard.profileListFetchLimit
            )
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
}
