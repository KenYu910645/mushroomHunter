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
            let msg = "Please enter a honey bid before joining."
            self.joinErrorMessage = msg
            self.errorMessage = msg
            return
        }
        guard session.canAffordHoney(trimmedBid) else {
            let msg = "Not enough honey. You have \(session.honey) 🍯."
            self.joinErrorMessage = msg
            self.errorMessage = msg
            return
        }
        // Optimistically mark loading to disable UI if needed
        isLoading = true
        defer { isLoading = false }
        do {
            try await withTimeout(seconds: 10) {
                try await self.actions.joinRoom(
                    roomId: listing.id,
                    initialBidHoney: trimmedBid,
                    userName: self.session.displayName,
                    friendCode: self.session.friendCode,
                    stars: self.session.stars
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

    init(session: SessionStore) {
        self.session = session
        _vm = StateObject(wrappedValue: BrowseViewModel(session: session))
    }
    
    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Browse")
                .toolbar { toolbarContent }
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
        .alert("Join Room", isPresented: $showJoinAlert, presenting: pendingJoinListing) { listing in
            TextField("Bid (honey)", text: $bidText)
                .keyboardType(.numberPad)
                .onChange(of: bidText) { _, newValue in
                    let filtered = newValue.filter { $0.isNumber }
                    if filtered != newValue { bidText = filtered }
                }

            Button("Join") {
                let bid = parseBid(bidText)
                Task { await vm.join(listing, bid: bid) }
            }

            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Enter honey bid. You have \(session.honey) 🍯.")
        }
    }
    
    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.listings.isEmpty {
            ProgressView("Loading rooms…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
        } else {
            List {
                if let err = vm.errorMessage {
                    Section {
                        Text(err)
                            .foregroundStyle(.red)
                    }
                }
                
                Section {
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
                            "No rooms found",
                            systemImage: "magnifyingglass",
                            description: Text("Try clearing filters or searching a different keyword.")
                        )
                        .listRowBackground(Color.clear)
                    }
                } header: {
                    Text("Available Rooms")
                }
            }
            .listStyle(.insetGrouped)
            .background(Color(.systemGroupedBackground))
            .refreshable {
                await vm.fetchListings()
            }
            .searchable(text: $vm.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search room / type / host")
        }
    }
    
    // MARK: - Toolbar / Filters
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 12) {
                Button {
                    showHostSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .accessibilityLabel("Create host room")
                
                Menu {
                    Picker("Mushroom Type", selection: $vm.selectedMushroomType) {
                        ForEach(vm.mushroomTypes, id: \.self) { t in
                            Text(t).tag(t)
                        }
                    }
                    
                    Toggle("Only show available", isOn: $vm.showOnlyAvailable)
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
        }
    }
    
    // MARK: - Row UI
    private struct RoomRowContent: View {
        let listing: RoomListing
        
        var isFull: Bool { listing.joinedPlayers >= listing.maxPlayers }
        
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
                        Text(listing.title)
                            .font(.headline)
                            .lineLimit(1)
                        
                        HStack(spacing: 8) {
                            Label(listing.mushroomType, systemImage: "leaf")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            if let host = listing.hostName, !host.isEmpty {
                                Text("Host: \(host)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        HStack(spacing: 8) {
                            Text("Players: \(listing.joinedPlayers)/\(listing.maxPlayers)")
                                .font(.subheadline)
                                .foregroundStyle(isFull ? .red : .secondary)
                            
                            if let mins = expiresInMinutes {
                                Text("Expires: \(mins)m")
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

    private func parseBid(_ text: String) -> Honey {
        let digits = text.filter { $0.isNumber }
        return Int(digits) ?? 0
    }
}
