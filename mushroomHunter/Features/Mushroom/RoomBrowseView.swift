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

// MARK: - View

struct RoomBrowseView: View {
    private let session: UserSessionStore // Session object passed from tab root (honey/profile refresh + child view models).
    @StateObject private var vm: RoomBrowseViewModel // Owns loading/filter/join state for this screen.
    @State private var showHostSheet: Bool = false // Controls host-room sheet presentation.
    @State private var pendingJoinListing: RoomListing? = nil // Selected listing for join prompt context.
    @State private var bidText: String = "" // Join prompt text input (digits only).
    @State private var joinGreetingMessage: String = NSLocalizedString("browse_join_greeting_default", comment: "") // Greeting message submitted together with join deposit.
    @State private var isJoinGreetingFocused: Bool = false // Controls first-responder focus for join greeting editor.
    @State private var isSearchFieldVisible: Bool = false // Controls inline search field visibility.
    @State private var bidFieldFocused: Bool = false // Controls first-responder focus for the bid entry field.
    @FocusState private var isSearchFieldFocused: Bool // Controls keyboard focus for inline search field.
    @Environment(\.colorScheme) private var scheme // Used for themed background.

    init(session: UserSessionStore) { // Initializes this type.
        self.session = session
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
            RoomFormView(vm: HostViewModel(session: session))
                .environmentObject(session)
        }
        .sheet(item: $pendingJoinListing) { listing in
            NavigationStack {
                Form {
                    Section {
                        SelectAllTextField(
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
                            SelectAllTextEditor(
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
                    } footer: {
                        Text(LocalizedStringKey("browse_join_greeting_footer"))
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
                HoneyMessageBox(
                    title: NSLocalizedString("room_msg_join_limit_title", comment: ""),
                    message: vm.joinLimitMessage,
                    buttons: [
                        HoneyMessageBoxButton(
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
            VStack(spacing: 12) {
                BrowseViewTopActionBar(
                    honey: session.honey,
                    onSearch: {
                        isSearchFieldVisible.toggle()
                        if isSearchFieldVisible {
                            isSearchFieldFocused = true
                        } else {
                            isSearchFieldFocused = false
                        }
                    },
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

                    if isSearchFieldVisible {
                        HStack(spacing: 8) {
                            TextField(LocalizedStringKey("browse_search_placeholder"), text: $vm.query)
                                .focused($isSearchFieldFocused)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .onSubmit {
                                    Task { await vm.performConfirmedSearch() }
                                }

                            Spacer(minLength: 0)

                            Button {
                                vm.query = ""
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
                        .padding(.vertical, 2)
                    }

                    // Each row provides:
                    // - navigation to details
                    // - mock-only quick join button for UI testing
                    ForEach(vm.filteredListings) { listing in
                        HStack(alignment: .top, spacing: 12) {
                            NavigationLink {
                                RoomView(
                                    vm: RoomViewModel(roomId: listing.id, session: session)
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
                                    joinGreetingMessage = NSLocalizedString("browse_join_greeting_default", comment: "")
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
