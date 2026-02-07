import SwiftUI
import Combine
import FirebaseFirestore

// MARK: - ViewModel

@MainActor
final class BrowseViewModel: ObservableObject {
    @Published var listings: [RoomListing] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    @Published var query: String = ""
    @Published var selectedMushroomType: String = "All"
    @Published var showOnlyAvailable: Bool = true

    // Keep consistent with your backend values (attribute strings)
    let mushroomTypes: [String] = ["All", "Normal", "Fire", "Water", "Crystal", "Electric", "Poisonous"]

    private let repo = FirebaseBrowseRepository()
    private let actions = FirebaseRoomActionsRepository()
    private unowned let session: SessionStore

    init(session: SessionStore) {
        self.session = session
    }

    func fetchListings() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let docs = try await withTimeout(seconds: 10) {
                try await self.repo.fetchOpenListings(limit: 50)
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

    @Published var joinErrorMessage: String? = nil

    func join(_ listing: RoomListing, bid: Honey) async {
        let trimmedBid = max(0, bid)
        guard trimmedBid > 0 else {
            let msg = NSLocalizedString("browse_error_enter_bid", comment: "")
            self.joinErrorMessage = msg
            self.errorMessage = msg
            return
        }
        guard session.canAffordHoney(trimmedBid) else {
            let msg = String(format: NSLocalizedString("browse_error_not_enough_honey", comment: ""), session.honey)
            self.joinErrorMessage = msg
            self.errorMessage = msg
            return
        }
        // Optimistically mark loading to disable UI if needed
        isLoading = true
        defer { isLoading = false }
        do {
            try await withTimeout(seconds: 10) {
                let balanceAfter = max(0, self.session.honey - trimmedBid)
                try await self.actions.joinRoom(
                    roomId: listing.id,
                    initialBidHoney: trimmedBid,
                    userName: self.session.displayName,
                    friendCode: self.session.friendCode,
                    stars: self.session.stars,
                    attendeeHoney: balanceAfter
                )
            }
            _ = session.spendHoney(trimmedBid)
            // Optionally refresh listings after joining to update counts
            await fetchListings()
        } catch {
            print("❌ join error:", error)
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            self.joinErrorMessage = message
            self.errorMessage = message
        }
    }

    var filteredListings: [RoomListing] {
        listings.filter { listing in
            if showOnlyAvailable && listing.joinedPlayers >= listing.maxPlayers { return false }
            if selectedMushroomType != "All" && listing.mushroomType != selectedMushroomType { return false }

            let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if q.isEmpty { return true }
            let qq = q.lowercased()
            return listing.title.lowercased().contains(qq)
                || listing.mushroomType.lowercased().contains(qq)
                || (listing.hostName ?? "").lowercased().contains(qq)
        }
    }
}

// MARK: - View

struct BrowseView: View {
    private let session: SessionStore
    @StateObject private var vm: BrowseViewModel
    @State private var showHostSheet: Bool = false
    @State private var pendingJoinListing: RoomListing? = nil
    @State private var bidText: String = ""
    @State private var showJoinAlert: Bool = false
    @State private var showSearchAlert: Bool = false

    init(session: SessionStore) {
        self.session = session
        _vm = StateObject(wrappedValue: BrowseViewModel(session: session))
    }
    
    var body: some View {
        NavigationStack {
            content
                .navigationTitle(LocalizedStringKey("browse_title"))
                .task {
                    if vm.listings.isEmpty {
                        await vm.fetchListings()
                    }
                }
        }
        .sheet(isPresented: $showHostSheet) {
            HostView(vm: HostViewModel(session: session))
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
                Task { await vm.join(listing, bid: bid) }
            }

            Button(LocalizedStringKey("common_cancel"), role: .cancel) {}
        } message: { _ in
            Text(String(format: NSLocalizedString("browse_join_message", comment: ""), session.honey))
        }
        .alert(LocalizedStringKey("browse_search_title"), isPresented: $showSearchAlert) {
            TextField(LocalizedStringKey("browse_search_placeholder"), text: $vm.query)
            Button(LocalizedStringKey("common_clear")) { vm.query = "" }
            Button(LocalizedStringKey("common_done")) {}
        } message: {
            Text(LocalizedStringKey("browse_search_message"))
        }
    }
    
    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.listings.isEmpty {
            ProgressView(LocalizedStringKey("browse_loading"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
        } else {
            List {
                Section(
                    header: HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "drop.fill")
                                .foregroundStyle(.yellow)
                            Text("\(session.honey)")
                                .font(.subheadline.weight(.semibold))
                        }

                        Spacer()

                        HStack(spacing: 12) {
                            Button {
                                showSearchAlert = true
                            } label: {
                                Image(systemName: "magnifyingglass")
                            }
                            .accessibilityLabel(LocalizedStringKey("browse_search_accessibility"))

                            Button {
                                showHostSheet = true
                            } label: {
                                Image(systemName: "plus.circle.fill")
                            }
                            .accessibilityLabel(LocalizedStringKey("browse_create_accessibility"))

                            Menu {
                                Picker(LocalizedStringKey("browse_mushroom_type"), selection: $vm.selectedMushroomType) {
                                    ForEach(vm.mushroomTypes, id: \.self) { t in
                                        Text(localizedMushroomType(t)).tag(t)
                                    }
                                }

                                Toggle(LocalizedStringKey("browse_only_available"), isOn: $vm.showOnlyAvailable)
                            } label: {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                            }
                        }
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                ) {
                    if let err = vm.errorMessage {
                        Text(err)
                            .foregroundStyle(.red)
                    }

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

                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                    }
                    
                    if vm.filteredListings.isEmpty {
                        ContentUnavailableView(
                            LocalizedStringKey("browse_empty_title"),
                            systemImage: "magnifyingglass",
                            description: Text(LocalizedStringKey("browse_empty_description"))
                        )
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .background(Color(.systemGroupedBackground))
            .refreshable {
                await vm.fetchListings()
            }
        }
    }
    
    // MARK: - Row UI
    private struct RoomRowContent: View {
        let listing: RoomListing
        
        var isFull: Bool { listing.joinedPlayers >= listing.maxPlayers }
        
        private var targetSummary: String {
            let color = formatTargetValue(listing.targetColor, allLabelKey: "target_color")
            let attribute = formatTargetValue(listing.targetAttribute, allLabelKey: "target_attribute")
            let size = formatTargetValue(listing.targetSize, allLabelKey: "target_size")
            return "\(color)/\(attribute)/\(size)"
        }

        // Compute "expires in" minutes if expiresAt exists
        private var expiresInMinutes: Int? {
            guard let expiresAt = listing.expiresAt else { return nil }
            let delta = Int(expiresAt.timeIntervalSinceNow / 60.0)
            return max(delta, 0)
        }
        
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(listing.title)
                                .font(.headline)
                                .lineLimit(1)

                            Spacer()

                            if !listing.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: "mappin.and.ellipse")
                                    Text(listing.location)
                                }
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            }
                        }
                        
                        HStack(spacing: 8) {
                            Text(targetSummary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        if let host = listing.hostName, !host.isEmpty {
                            HStack(spacing: 6) {
                                Text(String(format: NSLocalizedString("browse_host_format", comment: ""), host))
                                Image(systemName: "star.fill")
                                Text("\(listing.hostStars)")
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                        
                        HStack(spacing: 8) {
                            Text(String(format: NSLocalizedString("browse_attendee_format", comment: ""), listing.joinedPlayers, listing.maxPlayers))
                                .font(.subheadline)
                                .foregroundStyle(isFull ? .red : .secondary)
                            
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

        private func formatTargetValue(_ value: String, allLabelKey: String) -> String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let allLabel = NSLocalizedString(allLabelKey, comment: "")
            if trimmed.isEmpty { return String(format: NSLocalizedString("target_all_format", comment: ""), allLabel) }
            let lower = trimmed.lowercased()
            if lower == "all" || lower == "any" { return String(format: NSLocalizedString("target_all_format", comment: ""), allLabel) }
            return trimmed.capitalized
        }
    }

    private func parseBid(_ text: String) -> Honey {
        let digits = text.filter { $0.isNumber }
        return Int(digits) ?? 0
    }

    private func localizedMushroomType(_ type: String) -> LocalizedStringKey {
        switch type {
        case "All": return "mushroom_type_all"
        case "Normal": return "mushroom_type_normal"
        case "Fire": return "mushroom_type_fire"
        case "Water": return "mushroom_type_water"
        case "Crystal": return "mushroom_type_crystal"
        case "Electric": return "mushroom_type_electric"
        case "Poisonous": return "mushroom_type_poisonous"
        default: return LocalizedStringKey(type)
        }
    }
}
