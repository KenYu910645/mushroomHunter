//
//  RoomBrowseView.swift
//  mushroomHunter
//
//  Purpose:
//  - Implements the Mushroom tab browse screen, filtering, and join flow.
//
//  Defined in this file:
//  - BrowseViewModel, RoomBrowseView, and row rendering helpers.
//
import SwiftUI
import Combine
import FirebaseFirestore

// MARK: - ViewModel

@MainActor
final class BrowseViewModel: ObservableObject {
    @Published var listings: [RoomListing] = [] // Raw room data fetched from backend/mock source.
    @Published var isLoading: Bool = false // True while fetching listings or executing a join action.
    @Published var errorMessage: String? = nil // User-facing fetch/join error text shown in list section.
    @Published var showJoinLimitAlert: Bool = false // Controls presentation of "max joined rooms reached" alert.
    @Published var joinLimitMessage: String = "" // Message body shown in join-limit alert.

    @Published var query: String = "" // Free-text query used by local filter.
    @Published var showOnlyAvailable: Bool = true // When true, hide rooms that are already full.

    private let repo = FirebaseBrowseRepository() // Read-only room list source.
    private let actions = FirebaseRoomActionsRepository() // Join action source (writes attendee/honey-related data).
    private unowned let session: SessionStore // Shared session state (honey, profile fields, limits).

    init(session: SessionStore) { // Initializes this type.
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
            // ✅ Normal: user pulled to refresh / view reloaded / task replaced
            return
        } catch {
            print("❌ fetchListings error:", error)
            self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
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
        // Optimistically mark loading to disable UI if needed
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
            // Optionally refresh listings after joining to update counts
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
    /// - text search (title/host name)
    var filteredListings: [RoomListing] {
        listings.filter { listing in
            if showOnlyAvailable && listing.joinedPlayers >= listing.maxPlayers { return false }

            let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if q.isEmpty { return true }
            let qq = q.lowercased()
            return listing.title.lowercased().contains(qq)
                || (listing.hostName ?? "").lowercased().contains(qq)
        }
    }
}

// MARK: - View

struct RoomBrowseView: View {
    private let session: SessionStore // Session object passed from tab root (honey/profile refresh + child view models).
    @StateObject private var vm: BrowseViewModel // Owns loading/filter/join state for this screen.
    @State private var showHostSheet: Bool = false // Controls host-room sheet presentation.
    @State private var pendingJoinListing: RoomListing? = nil // Selected listing for join prompt context.
    @State private var bidText: String = "" // Join prompt text input (digits only).
    @State private var showJoinAlert: Bool = false // Controls join prompt alert.
    @State private var showSearchAlert: Bool = false // Controls search prompt alert.
    @Environment(\.colorScheme) private var scheme // Used for themed background.

    init(session: SessionStore) { // Initializes this type.
        self.session = session
        _vm = StateObject(wrappedValue: BrowseViewModel(session: session))
    }
    
    /// Main browse screen composition:
    /// - list/skeleton content
    /// - host-room sheet
    /// - join/search alerts
    var body: some View {
        NavigationStack {
            content
                .navigationTitle(LocalizedStringKey("browse_title"))
                .onAppear {
                    // Keep honey/profile fields fresh when entering tab.
                    if !AppTesting.isUITesting {
                        Task { await session.refreshProfileFromBackend() }
                    }
                    // Always refresh list when screen appears.
                    Task { await vm.fetchListings() }
                }
        }
        .sheet(isPresented: $showHostSheet) {
            // Opens room creation flow from browse header.
            RoomHostView(vm: HostViewModel(session: session))
                .environmentObject(session)
        }
        .alert(LocalizedStringKey("browse_join_room_title"), isPresented: $showJoinAlert, presenting: pendingJoinListing) { listing in
            TextField(LocalizedStringKey("browse_join_bid_placeholder"), text: $bidText)
                .keyboardType(.numberPad)
                .onChange(of: bidText) { _, newValue in
                    let filtered = newValue.filter { $0.isNumber }
                    if filtered != newValue { bidText = filtered }
                }

            Button(LocalizedStringKey("common_join")) {
                let bid = parseBid(bidText)
                Task { await vm.join(listing, deposit: bid) }
            }

            Button(LocalizedStringKey("common_cancel"), role: .cancel) {}
        } message: { _ in
            Text(String(format: NSLocalizedString("browse_join_message", comment: ""), session.honey))
        }
        .alert(LocalizedStringKey("room_join_limit_title"), isPresented: $vm.showJoinLimitAlert) {
            Button(LocalizedStringKey("common_ok")) {}
        } message: {
            Text(vm.joinLimitMessage)
        }
        .alert(LocalizedStringKey("browse_search_title"), isPresented: $showSearchAlert) {
            TextField(LocalizedStringKey("browse_search_placeholder"), text: $vm.query)
            Button(LocalizedStringKey("common_clear")) { vm.query = "" }
            Button(LocalizedStringKey("common_done")) {}
        } message: {
            Text(LocalizedStringKey("browse_search_message"))
        }
    }
    
    /// Main content body with two states:
    /// - full-screen loading indicator when no data yet
    /// - room list with header actions and pull-to-refresh
    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.listings.isEmpty {
            ProgressView(LocalizedStringKey("browse_loading"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.backgroundGradient(for: scheme))
        } else {
            VStack(spacing: 12) {
                BrowseViewTopActionBar(
                    honey: session.honey,
                    onSearch: { showSearchAlert = true },
                    onCreate: { showHostSheet = true },
                    searchAccessibilityLabel: "browse_search_accessibility",
                    createAccessibilityLabel: "browse_create_accessibility",
                    searchButtonIdentifier: "browse_search_button",
                    createButtonIdentifier: "browse_create_button"
                )
                .padding(.horizontal)
                .padding(.top, 8)

                List {
                    if let err = vm.errorMessage {
                        Text(err)
                            .foregroundStyle(.red)
                    }

                    // Each row provides:
                    // - navigation to details
                    // - mock-only quick join button for UI testing
                    ForEach(vm.filteredListings) { listing in
                        HStack(alignment: .top, spacing: 12) {
                            NavigationLink {
                                RoomDetailsView(
                                    vm: RoomDetailsViewModel(roomId: listing.id, session: session)
                                )
                            } label: {
                                RoomRowContent(listing: listing)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("browse_room_link_\(listing.id)")

                            Spacer(minLength: 0)

                            if AppTesting.useMockRooms {
                                Button {
                                    pendingJoinListing = listing
                                    bidText = "\(max(AppConfig.Mushroom.minFixedRaidCost, listing.joinedPlayers > 0 ? AppConfig.Mushroom.defaultFixedRaidCost : AppConfig.Mushroom.minFixedRaidCost))"
                                    showJoinAlert = true
                                } label: {
                                    Text(LocalizedStringKey("common_join"))
                                }
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("browse_quick_join_button_\(listing.id)")
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    if vm.filteredListings.isEmpty {
                        ContentUnavailableView(
                            LocalizedStringKey("browse_empty_title"),
                            systemImage: "magnifyingglass",
                        )
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .refreshable {
                    await vm.fetchListings()
                }
            }
            .background(Theme.backgroundGradient(for: scheme))
        }
    }
    
    // MARK: - Row UI
    private struct RoomRowContent: View {
        let listing: RoomListing // Source listing displayed in this row.
        
        private var displayedJoined: Int { // Normalized joined count used for safer UI display.
            min(listing.maxPlayers, max(0, listing.joinedPlayers))
        }

        var isFull: Bool { displayedJoined >= listing.maxPlayers } // True when room is at/over capacity.
        
        private var expiresInMinutes: Int? { // Remaining minutes until expiry, clamped to non-negative.
            guard let expiresAt = listing.expiresAt else { return nil }
            let delta = Int(expiresAt.timeIntervalSinceNow / 60.0)
            return max(delta, 0)
        }
        
        /// Row layout shown in browse list.
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(listing.title)
                                .font(.headline)
                                .lineLimit(1)

                            Spacer()

                            Text(String(format: NSLocalizedString("browse_attendee_format", comment: ""), displayedJoined, listing.maxPlayers))
                                .font(.subheadline)
                                .foregroundStyle(isFull ? .red : .secondary)
                        }
                        
                        if !listing.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "mappin.and.ellipse")
                                Text(listing.location)
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 8) {
                            if let mins = expiresInMinutes {
                                Text(String(format: NSLocalizedString("browse_expires_format", comment: ""), mins))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    Spacer()
                }
            }
        }

    }

    /// Parses numeric bid text into honey amount.
    private func parseBid(_ text: String) -> Honey {
        let digits = text.filter { $0.isNumber }
        return Int(digits) ?? 0
    }

}
