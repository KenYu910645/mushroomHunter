//
//  RoomBrowseView.swift
//  mushroomHunter
//
//  Purpose:
//  - Implements the Mushroom tab browse screen, filtering, and join flow.
//
//  Defined in this file:
//  - RoomBrowseView and row rendering helpers.
//
import SwiftUI

/// Push/deep-link route consumed by Mushroom browse navigation stack.
struct RoomBrowsePushRoute: Identifiable, Hashable {
    /// Unique id so repeated route payloads can still navigate.
    let id: UUID = UUID()
    /// Target room id to open.
    let roomId: String
    /// Indicates destination should auto-open confirmation queue.
    let isOpeningConfirmationQueue: Bool
    /// Indicates destination should force backend refresh on first load.
    let isForceRefresh: Bool
}

// MARK: - View

struct RoomBrowseView: View {
    private let session: UserSessionStore // Session object passed from tab root (honey/profile refresh + child view models).
    @Binding private var pendingPushRoute: RoomBrowsePushRoute? // Pending route provided by app-level notification router.
    @EnvironmentObject private var notificationInbox: EventInboxStore // Shared notification inbox state used by the top-right bell button.
    @StateObject private var vm: RoomBrowseViewModel // Owns loading/filter/join state for this screen.
    @State private var showHostSheet: Bool = false // Controls host-room sheet presentation.
    @State private var pendingJoinListing: RoomListing? = nil // Selected listing for join prompt context.
    @State private var bidText: String = "" // Join prompt text input (digits only).
    @State private var joinGreetingMessage: String = NSLocalizedString("browse_join_greeting_default", comment: "") // Greeting message submitted together with join deposit.
    @State private var isJoinGreetingFocused: Bool = false // Controls first-responder focus for join greeting editor.
    @State private var isSearchFieldVisible: Bool = false // Controls inline search field visibility.
    @State private var bidFieldFocused: Bool = false // Controls first-responder focus for the bid entry field.
    @State private var isNotificationInboxPresented: Bool = false // Controls notification inbox sheet presentation.
    @FocusState private var isSearchFieldFocused: Bool // Controls keyboard focus for inline search field.
    @Environment(\.colorScheme) private var scheme // Used for themed background.
    @State private var activePushRoute: RoomBrowsePushRoute? = nil // Active push route currently being pushed in navigation stack.

    init(session: UserSessionStore, pendingPushRoute: Binding<RoomBrowsePushRoute?> = .constant(nil)) { // Initializes this type.
        self.session = session
        _pendingPushRoute = pendingPushRoute
        _vm = StateObject(wrappedValue: RoomBrowseViewModel(session: session))
    }
    
    /// Main browse screen composition:
    /// - list/skeleton content
    /// - host-room sheet
    /// - join sheet
    /// - inline search field
    var body: some View {
        NavigationStack {
            content
                .navigationTitle(LocalizedStringKey("browse_title"))
                .navigationDestination(item: $activePushRoute) { route in
                    RoomView(
                        vm: RoomViewModel(
                            roomId: route.roomId,
                            session: session,
                            seededRole: vm.roleSeed(for: route.roomId)
                        ),
                        isOpeningConfirmationQueueOnAppear: route.isOpeningConfirmationQueue,
                        isForceRefreshOnAppear: route.isForceRefresh
                    )
                }
                .onAppear {
                    // Keep honey/profile fields fresh when entering tab.
                    if !AppTesting.isUITesting {
                        Task { await session.refreshProfileFromBackend() }
                    }
                    // Load cache-first room list on screen entry.
                    Task { await vm.loadListingsOnAppear() }
                }
                .onChange(of: pendingPushRoute) { _, route in
                    guard let route else { return }
                    activePushRoute = route
                    pendingPushRoute = nil
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            Task { @MainActor in
                                await notificationInbox.refreshFromServer()
                                isNotificationInboxPresented = true
                            }
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "bell")
                                if notificationInbox.unreadCount > 0 {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 8, height: 8)
                                        .offset(x: 4, y: -3)
                                }
                            }
                        }
                        .accessibilityLabel(LocalizedStringKey("browse_notification_accessibility"))
                        .accessibilityIdentifier("browse_notification_button")
                    }
                }
        }
        .sheet(
            isPresented: $showHostSheet,
            onDismiss: {
                Task { await vm.fetchListings(forceRefresh: true) }
            }
        ) {
            // Opens room creation flow from browse header.
            RoomCreateEditView(vm: HostViewModel(session: session))
                .environmentObject(session)
        }
        .sheet(isPresented: $isNotificationInboxPresented) {
            EventInboxView { route in
                routeEventInboxItem(route)
            }
            .environmentObject(notificationInbox)
        }
        .sheet(item: $pendingJoinListing) { listing in
            NavigationStack {
                Form {
                    Section {
                        SmartTextField(
                            placeholderKey: "browse_join_bid_placeholder",
                            text: $bidText,
                            isFirstResponder: $bidFieldFocused,
                            keyboardType: .numberPad,
                            textContentType: .none,
                            autocapitalization: .none,
                            autocorrection: .no,
                            textAlignment: .right
                        ) { newValue in
                            let filtered = newValue.filter { $0.isNumber }
                            if filtered != newValue { bidText = filtered }
                        }
                        .frame(height: 22)
                    } header: {
                        Text(LocalizedStringKey("browse_join_room_title"))
                    } footer: {
                        Text(String(format: NSLocalizedString("browse_join_message", comment: ""), session.honey))
                    }

                    Section {
                        ZStack(alignment: .topLeading) {
                            if joinGreetingMessage.isEmpty {
                                Text(LocalizedStringKey("browse_join_greeting_placeholder"))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                                    .padding(.leading, 6)
                            }
                            SmartTextEditor(
                                text: $joinGreetingMessage,
                                isFirstResponder: $isJoinGreetingFocused,
                                autocapitalization: .sentences,
                                autocorrection: .yes
                            ) { latestValue in
                                let maxLength = 100
                                if latestValue.count > maxLength {
                                    joinGreetingMessage = String(latestValue.prefix(maxLength))
                                }
                            }
                            .frame(minHeight: 88)
                        }
                    } header: {
                        Text(LocalizedStringKey("browse_join_greeting_header"))
                    }

                    Section {
                        Button(LocalizedStringKey("common_join")) {
                            let bid = parseBid(bidText)
                            pendingJoinListing = nil
                            isJoinGreetingFocused = false
                            Task { await vm.join(listing, deposit: bid, greetingMessage: joinGreetingMessage) }
                        }
                        .disabled(joinGreetingMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .navigationTitle(LocalizedStringKey("browse_join_room_title"))
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(LocalizedStringKey("common_cancel")) {
                            pendingJoinListing = nil
                        }
                    }
                }
                .onAppear {
                    bidFieldFocused = true
                    if joinGreetingMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        joinGreetingMessage = NSLocalizedString("browse_join_greeting_default", comment: "")
                    }
                }
                .onDisappear {
                    bidFieldFocused = false
                    isJoinGreetingFocused = false
                }
            }
        }
        .overlay {
            if vm.showJoinLimitAlert {
                MessageBox(
                    title: NSLocalizedString("room_msg_join_limit_title", comment: ""),
                    message: vm.joinLimitMessage,
                    buttons: [
                        MessageBoxButton(
                            id: "room_browse_join_limit_ok",
                            title: NSLocalizedString("common_ok", comment: "")
                        ) {
                            vm.showJoinLimitAlert = false
                        }
                    ]
                )
            }
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
            ScrollView {
                VStack(spacing: 12) {
                    if let err = vm.errorMessage {
                        Text(err)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                    }

                    TopActionBar(
                        honey: session.honey,
                        stars: session.stars,
                        onSearch: {
                            isSearchFieldVisible.toggle()
                            if isSearchFieldVisible {
                                isSearchFieldFocused = true
                            } else {
                                isSearchFieldFocused = false
                                vm.query = ""
                            }
                        },
                        onCreate: { showHostSheet = true },
                        searchAccessibilityLabel: "browse_search_accessibility",
                        createAccessibilityLabel: "browse_create_accessibility",
                        searchButtonIdentifier: "browse_search_button",
                        createButtonIdentifier: "browse_create_button",
                        isStarsVisible: false
                    )
                    .padding(.horizontal)

                    if isSearchFieldVisible {
                        HStack(spacing: 8) {
                            TextField(LocalizedStringKey("browse_search_placeholder"), text: $vm.query)
                                .focused($isSearchFieldFocused)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .submitLabel(.search)
                                .onSubmit {
                                    Task { await vm.performConfirmedSearch() }
                                }

                            Spacer(minLength: 0)

                            Button {
                                vm.query = ""
                                isSearchFieldFocused = false
                                isSearchFieldVisible = false
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("browse_search_clear_button")
                            .accessibilityLabel(LocalizedStringKey("browse_search_clear_accessibility"))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .padding(.horizontal)
                    }

                    // Each row provides:
                    // - navigation to details
                    // - mock-only quick join button for UI testing
                    LazyVStack(spacing: 0) {
                        ForEach(vm.filteredListings) { listing in
                            HStack(alignment: .top, spacing: 12) {
                                NavigationLink {
                                    RoomView(
                                        vm: RoomViewModel(
                                            roomId: listing.id,
                                            session: session,
                                            seededRole: vm.roleSeed(for: listing.id)
                                        )
                                    )
                                } label: {
                                    RoomRowContent(
                                        listing: listing,
                                        ownershipTag: vm.ownershipTag(for: listing.id)
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("browse_room_link_\(listing.id)")

                                Spacer(minLength: 0)

                                if AppTesting.useMockRooms {
                                    Button {
                                        pendingJoinListing = listing
                                        bidText = "\(max(AppConfig.Mushroom.minFixedRaidCost, listing.joinedPlayers > 0 ? AppConfig.Mushroom.defaultFixedRaidCost : AppConfig.Mushroom.minFixedRaidCost))"
                                        joinGreetingMessage = NSLocalizedString("browse_join_greeting_default", comment: "")
                                    } label: {
                                        Text(LocalizedStringKey("common_join"))
                                    }
                                    .buttonStyle(.bordered)
                                    .accessibilityIdentifier("browse_quick_join_button_\(listing.id)")
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)

                            if listing.id != vm.filteredListings.last?.id {
                                Divider()
                                    .padding(.horizontal)
                            }
                        }
                    }

                    if vm.filteredListings.isEmpty {
                        ContentUnavailableView(
                            LocalizedStringKey("browse_empty_title"),
                            systemImage: "magnifyingglass",
                        )
                        .padding(.top, 24)
                    }
                }
                .padding(.vertical, 8)
            }
            .refreshable {
                await vm.fetchListings(forceRefresh: true)
            }
            .background(Theme.backgroundGradient(for: scheme))
        }
    }
    
    // MARK: - Row UI
    private struct RoomRowContent: View {
        let listing: RoomListing // Source listing displayed in this row.
        let ownershipTag: RoomBrowseViewModel.OwnershipTag? // Optional ownership tag for joined/hosted rows.
        
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
                        
                        HStack(spacing: 8) {
                            if !listing.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: "mappin.and.ellipse")
                                    Text(RoomLocationLocalization.displayLabel(forStoredLocation: listing.location))
                                }
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            }

                            if let mins = expiresInMinutes {
                                Text(String(format: NSLocalizedString("browse_expires_format", comment: ""), mins))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 0)

                            if let ownershipTag {
                                RoomOwnershipTagChip(titleKey: ownershipTag.titleKey)
                            }
                        }
                    }
                    
                    Spacer()
                }
            }
        }

    }

    /// Compact ownership badge used to separate joined/hosted rows from general browse listings.
    private struct RoomOwnershipTagChip: View {
        /// Localized ownership label rendered by this chip.
        let titleKey: LocalizedStringKey

        /// Badge UI for ownership marker.
        var body: some View {
            ColorfulTag(
                titleKey: titleKey,
                tone: .ownership,
                horizontalPadding: 8,
                verticalPadding: 3,
                font: .caption2.weight(.semibold)
            )
        }
    }

    /// Parses numeric bid text into honey amount.
    private func parseBid(_ text: String) -> Honey {
        let digits = text.filter { $0.isNumber }
        return Int(digits) ?? 0
    }

    /// Routes a tapped notification inbox row into existing app-level deep-link channels.
    /// - Parameter route: Inbox route metadata attached to the tapped row.
    private func routeEventInboxItem(_ route: EventInboxRoute) {
        switch route.kind {
        case .room:
            guard let roomId = route.roomId, roomId.isEmpty == false else { return }
            if route.isOpeningConfirmationQueue {
                NotificationCenter.default.post(name: .didOpenRoomConfirmationFromPush, object: roomId)
            } else {
                NotificationCenter.default.post(name: .didOpenRoomFromPush, object: roomId)
            }
        case .postcard:
            guard let postcardId = route.postcardId, postcardId.isEmpty == false else { return }
            if route.isOpeningOrderPage {
                NotificationCenter.default.post(
                    name: .didOpenPostcardOrderFromPush,
                    object: [
                        "postcardId": postcardId,
                        "orderId": route.orderId ?? ""
                    ]
                )
            } else {
                NotificationCenter.default.post(name: .didOpenPostcardFromLink, object: postcardId)
            }
        case .none:
            break
        }
    }

}
