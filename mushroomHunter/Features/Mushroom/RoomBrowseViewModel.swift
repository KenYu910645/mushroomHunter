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
import Combine
import Combine

/// View model for the Mushroom browse screen.
@MainActor
final class RoomBrowseViewModel: ObservableObject {
    @Published var listings: [RoomListing] = [] // Raw room data fetched from backend/mock source.
    @Published var isLoading: Bool = false // True while fetching listings or executing a join action.
    @Published var errorMessage: String? = nil // User-facing fetch/join error text shown in list section.
    @Published var showJoinLimitAlert: Bool = false // Controls presentation of "max joined rooms reached" alert.
    @Published var joinLimitMessage: String = "" // Message body shown in join-limit alert.

    @Published var query: String = "" // Free-text query used by local filter.
    @Published var showOnlyAvailable: Bool = true // When true, hide rooms that are already full.

    private let repo = FbRoomBrowseRepo() // Read-only room list source.
    private let actions = FbRoomActionsRepo() // Join action source (writes attendee/honey-related data).
    private unowned let session: UserSessionStore // Shared session state (honey, profile fields, limits).

    init(session: UserSessionStore) { // Initializes this type.
        self.session = session
    }

    /// Fetches latest open room listings from backend (or fixture in UI-test mode).
    func fetchListings() async { // Handles fetchListings flow.
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
        } catch is CancellationError {
            // Normal: user pulled to refresh, view reloaded, or task replaced.
            return
        } catch {
            print("❌ fetchListings error:", error)
            self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Refreshes backend room listings when user confirms a search.
    /// Search filtering itself remains local on the fetched page.
    func performConfirmedSearch() async {
        await fetchListings()
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
    func join(_ listing: RoomListing, deposit: Honey) async { // Handles join flow.
        if AppTesting.useMockRooms {
            guard deposit > 0 else {
                let msg = NSLocalizedString("browse_error_enter_bid", comment: "")
                self.errorMessage = msg
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
                    userName: self.session.displayName,
                    friendCode: self.session.friendCode,
                    stars: self.session.stars,
                    attendeeHoney: balanceAfter
                )
            }
            _ = session.spendHoney(trimmedDeposit)
            // Optionally refresh listings after joining to update counts.
            await fetchListings()
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
    /// - text search (title/location/host name)
    var filteredListings: [RoomListing] {
        listings.filter { listing in
            if showOnlyAvailable && listing.joinedPlayers >= listing.maxPlayers { return false }

            let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if q.isEmpty { return true }
            let qq = q.lowercased()
            return listing.title.lowercased().contains(qq)
                || listing.location.lowercased().contains(qq)
                || (listing.hostName ?? "").lowercased().contains(qq)
        }
    }
}
