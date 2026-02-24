//
//  PostcardBrowseView.swift
//  mushroomHunter
//
//  Purpose:
//  - Hosts the postcard tab browse flow with search, register sheet, and listing grid.
//
import SwiftUI

/// Push/deep-link route consumed by Postcard browse navigation stack.
struct PostcardBrowsePushRoute: Identifiable, Hashable {
    /// Unique id so repeated route payloads can still navigate.
    let id: UUID = UUID()
    /// Target postcard listing id to open.
    let postcardId: String
    /// Indicates destination should auto-open order context.
    let isOpeningOrderPage: Bool
    /// Indicates destination should force backend refresh on first load.
    let isForceRefresh: Bool
}

// MARK: - Browse

/// Root postcard browse screen used by the Postcard tab.
struct PostcardBrowseView: View {
    /// Shared session state used for wallet values and profile refresh.
    @EnvironmentObject private var session: UserSessionStore
    /// Browse view model that loads and filters postcard listings.
    @StateObject private var vm = PostcardBrowseViewModel()
    /// Controls presentation of the search alert.
    @State private var isSearchFieldVisible: Bool = false
    /// Controls presentation of the postcard register sheet.
    @State private var isRegisterSheetPresented: Bool = false
    /// Refresh trigger incremented after creating a postcard.
    @State private var browseDataRefreshToken: Int = 0
    /// Current color scheme used for theme background rendering.
    @Environment(\.colorScheme) private var scheme
    /// Controls keyboard focus for inline search field.
    @FocusState private var isSearchFieldFocused: Bool
    /// Pending push route provided by app-level notification router.
    @Binding private var pendingPushRoute: PostcardBrowsePushRoute?
    /// Active push route currently pushed in postcard navigation stack.
    @State private var activePushRoute: PostcardBrowsePushRoute? = nil
    /// Spacing used between postcard grid columns.
    private let cardColumnSpacing: CGFloat = 8

    init(pendingPushRoute: Binding<PostcardBrowsePushRoute?> = .constant(nil)) { // Initializes this type.
        _pendingPushRoute = pendingPushRoute
    }

    /// Main postcard browse UI tree.
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if let err = vm.errorMessage {
                        Text(err)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                    }

                    headerBar

                    if isSearchFieldVisible {
                        HStack(spacing: 8) {
                            TextField(LocalizedStringKey("postcard_search_placeholder"), text: $vm.query)
                                .focused($isSearchFieldFocused)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .onSubmit {
                                    Task { await vm.performConfirmedSearch() }
                                }

                            Spacer(minLength: 0)

                            Button {
                                isSearchFieldFocused = false
                                isSearchFieldVisible = false
                                Task { await vm.clearConfirmedSearch() }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("postcard_search_clear_button")
                            .accessibilityLabel(LocalizedStringKey("postcard_search_clear_accessibility"))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .padding(.horizontal)
                    }

                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        ForEach(vm.filteredListings) { listing in
                            NavigationLink {
                                PostcardView(listing: listing)
                            } label: {
                                PostcardCardView(listing: listing)
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .buttonStyle(.plain)
                            .contentShape(RoundedRectangle(cornerRadius: 12))
                            .accessibilityIdentifier("postcard_link_\(listing.id)")
                        }
                    }
                    .padding(.horizontal)

                    if !vm.listings.isEmpty {
                        if vm.isLoadingNextPage {
                            ProgressView("Loading more postcards…")
                                .padding(.top, 8)
                        } else if vm.isHasMorePages {
                            Button {
                                Task { await vm.loadNextPage() }
                            } label: {
                                Text("Load more")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .padding(.horizontal)
                            .padding(.top, 4)
                        }
                    }

                    if vm.filteredListings.isEmpty && !vm.isLoading {
                        ContentUnavailableView(
                            LocalizedStringKey("postcard_empty_title"),
                            systemImage: "magnifyingglass",
                            description: Text(LocalizedStringKey("postcard_empty_description"))
                        )
                        .padding(.top, 24)
                    }
                }
                .padding(.vertical, 8)
            }
            .navigationTitle(LocalizedStringKey("postcard_title"))
            .navigationDestination(item: $activePushRoute) { route in
                PostcardBrowseDestinationView(route: route)
            }
            .background(Theme.backgroundGradient(for: scheme))
            .overlay {
                if vm.isLoading && vm.filteredListings.isEmpty {
                    ProgressView("Loading postcards…")
                }
            }
        }
        .sheet(isPresented: $isRegisterSheetPresented) {
            NavigationStack {
                PostcardFormView(onSubmitted: {
                    isRegisterSheetPresented = false
                    browseDataRefreshToken += 1
                })
                .navigationTitle(LocalizedStringKey("postcard_register_title"))
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            isRegisterSheetPresented = false
                        } label: {
                            Image(systemName: "xmark")
                        }
                    }
                }
            }
        }
        .onChange(of: vm.selectedCountry) { _, _ in
            vm.normalizeProvinceSelection()
        }
        .onAppear {
            Task {
                await session.refreshProfileFromBackend()
                await vm.refresh()
            }
        }
        .onChange(of: pendingPushRoute) { _, route in
            guard let route else { return }
            activePushRoute = route
            pendingPushRoute = nil
        }
        .task(id: browseDataRefreshToken) {
            await vm.refresh()
        }
        .refreshable {
            await vm.refresh()
        }
    }

    /// Grid layout used by postcard cards.
    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: cardColumnSpacing, alignment: .top),
            GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: cardColumnSpacing, alignment: .top)
        ]
    }

    /// Shared top action bar for honey amount, search, and create actions.
    private var headerBar: some View {
        BrowseViewTopActionBar(
            honey: session.honey,
            stars: session.stars,
            onSearch: {
                isSearchFieldVisible.toggle()
                if isSearchFieldVisible {
                    isSearchFieldFocused = true
                } else {
                    isSearchFieldFocused = false
                }
            },
            onCreate: { isRegisterSheetPresented = true },
            searchAccessibilityLabel: "postcard_search_accessibility",
            createAccessibilityLabel: "postcard_register_accessibility",
            searchButtonIdentifier: "postcard_search_button",
            createButtonIdentifier: "postcard_create_button",
            isStarsVisible: false
        )
        .padding(.horizontal)
    }
}

/// Postcard push destination loader that opens normal postcard detail route in-stack.
private struct PostcardBrowseDestinationView: View {
    /// Route payload to resolve postcard detail destination.
    let route: PostcardBrowsePushRoute
    /// Loaded postcard listing document.
    @State private var listing: PostcardListing? = nil
    /// Indicates listing fetch is in progress.
    @State private var isLoading: Bool = false
    /// Repository used to load listing by id.
    private let repo = FbPostcardRepo()

    var body: some View {
        Group {
            if let listing {
                PostcardView(
                    listing: listing,
                    isOpeningOrderPageOnAppear: route.isOpeningOrderPage,
                    isForceRefreshOnAppear: route.isForceRefresh
                )
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    LocalizedStringKey("postcard_link_unavailable_title"),
                    systemImage: "qrcode",
                    description: Text(LocalizedStringKey("postcard_link_unavailable_message"))
                )
            }
        }
        .task {
            await loadPostcard()
        }
    }

    /// Loads the route postcard id from backend (or fixtures in UI-test mode).
    private func loadPostcard() async {
        guard !route.postcardId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if AppTesting.useMockPostcards {
            if route.postcardId == AppTesting.fixturePostcardId {
                listing = AppTesting.fixturePostcardListing()
            } else if route.postcardId == AppTesting.fixtureOwnedPostcardListing().id {
                listing = AppTesting.fixtureOwnedPostcardListing()
            }
            return
        }
        isLoading = true
        defer { isLoading = false }
        listing = try? await repo.fetchPostcard(postcardId: route.postcardId)
    }
}

/// Card tile shown for each postcard listing in the browse grid.
private struct PostcardCardView: View {
    /// Listing displayed by this card.
    let listing: PostcardListing
    /// Current color scheme used for card background styling.
    @Environment(\.colorScheme) private var scheme
    /// Fixed aspect ratio used for postcard thumbnail area.
    private let imageAspectRatio: CGFloat = 1.0

    /// Card content for a single postcard listing.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .aspectRatio(imageAspectRatio, contentMode: .fit)

                if let urlString = listing.thumbnailUrl ?? listing.imageUrl, let url = URL(string: urlString) {
                    CachedPostcardImageView(
                        imageURL: url,
                        fallbackSystemImageName: "photo",
                        fallbackIconFont: .title
                    )
                    .aspectRatio(imageAspectRatio, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    Image(systemName: "photo")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }

                // Keep price visible on top of the postcard snapshot in the browse card.
                HStack(spacing: 4) {
                    Text("\(listing.priceHoney)")
                        .font(.caption.weight(.semibold))
                    Image("HoneyIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 12, height: 12)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
            }
            .frame(maxWidth: .infinity)

            Text(listing.title)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
                .truncationMode(.tail)

            HStack(spacing: 6) {
                Image(systemName: "mappin.and.ellipse")
                Text(listing.location.shortLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.cardBackground(for: scheme))
                .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
        )
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}
