//
//  PostcardBrowseViewModel.swift
//  mushroomHunter
//
//  Purpose:
//  - Owns postcard browse state, filter/search options, and data loading.
//
//  Defined in this file:
//  - PostcardBrowseViewModel query/filter/sort logic for listings.
//
import Foundation
import SwiftUI
import Combine

@MainActor
/// View model that manages postcard browse loading, filtering, and search.
final class PostcardBrowseViewModel: ObservableObject {
    /// Ownership tag displayed for pinned user-related postcard slots.
    enum OwnershipTag {
        /// Listing currently sold by the signed-in user.
        case onShelf
        /// Listing currently sold by the signed-in user but all stock has been purchased.
        case runOut
        /// Listing currently ordered by the signed-in user.
        case ordered

        /// Localized title key shown in ownership tag chip.
        var titleKey: LocalizedStringKey {
            switch self {
            case .onShelf:
                return LocalizedStringKey("postcard_tag_on_shelf")
            case .runOut:
                return LocalizedStringKey("postcard_tag_run_out")
            case .ordered:
                return LocalizedStringKey("postcard_tag_ordered")
            }
        }
    }

    /// Raw listings fetched from Firestore before local filters are applied.
    @Published var listings: [PostcardListing] = []
    /// On-shelf listings that must remain pinned above browse results.
    @Published var pinnedOnShelfListings: [PostcardListing] = []
    /// Ordered listings that must remain pinned above browse results.
    @Published var pinnedOrderedListings: [PostcardListing] = []
    /// Indicates whether an async fetch is currently running.
    @Published var isLoading: Bool = false
    /// Error text presented by the browse view when fetching fails.
    @Published var errorMessage: String? = nil
    /// Indicates whether a pagination request is currently running.
    @Published var isLoadingNextPage: Bool = false
    /// Indicates whether backend currently has more browse pages.
    @Published var isHasMorePages: Bool = false
    /// Free-text search input entered by the user.
    @Published var query: String = ""
    /// Country filter value (`All` means no filter).
    @Published var selectedCountry: String = "All"
    /// Province filter value (`All` means no filter).
    @Published var selectedProvince: String = "All"
    /// Current sort mode for browse results.
    @Published var sortOrder: PostcardSortOrder = .newest
    /// Firebase-backed repository used to fetch postcard listings.
    private let repo = FbPostcardRepo()
    /// Shared structured payload cache used for postcard browse stale-first loading.
    private let cache = RoomCache.shared
    /// Shared dirty-bit state used to force backend refresh after postcard mutations/events.
    private let dirtyBits = CacheDirtyBitStore.shared
    /// Stable cache key for postcard browse list payload.
    private let browseCacheKey = "postcard.browse.listings.v1"
    /// Cursor for loading the next browse page.
    private var nextPageCursor: FbPostcardRepo.ListingPageCursor? = nil
    /// Last query committed to backend search.
    private var confirmedQuery: String = ""
    /// Active backend token for paged search mode.
    private var activeSearchToken: String? = nil
    /// On-shelf listing ids used for ownership tag lookup.
    private var onShelfListingIds: Set<String> = []
    /// Ordered listing ids used for ownership tag lookup.
    private var orderedListingIds: Set<String> = []
    /// Listing ids deleted in current session; used to suppress stale backend/cache echoes.
    private var locallyDeletedListingIds: Set<String> = []

    /// Applies local tutorial scene data for first-entry postcard browse walkthrough.
    /// This bypasses Firebase and mirrors real postcard browse card composition.
    func loadPostcardBrowseTutorialScene() {
        isLoading = false
        errorMessage = nil
        query = ""
        confirmedQuery = ""
        selectedCountry = "All"
        selectedProvince = "All"
        sortOrder = .newest
        nextPageCursor = nil
        isLoadingNextPage = false
        isHasMorePages = false
        activeSearchToken = nil

        let tutorialScenario = TutorialScene.PostcardBrowse.scenario
        listings = tutorialScenario.fakeListings
        pinnedOnShelfListings = tutorialScenario.fakeListings.filter { listing in
            tutorialScenario.onShelfListingIds.contains(listing.id)
        }
        pinnedOrderedListings = tutorialScenario.fakeListings.filter { listing in
            tutorialScenario.orderedListingIds.contains(listing.id)
        }
        onShelfListingIds = tutorialScenario.onShelfListingIds
        orderedListingIds = tutorialScenario.orderedListingIds
    }

    /// Loads data only when no listings have been fetched yet.
    func loadIfNeeded(session: UserSessionStore) async {
        if listings.isEmpty {
            await refresh(session: session)
        }
    }

    /// Loads postcard browse on appear with dirty-bit aware refresh policy.
    /// - Parameter session: Current signed-in session.
    func loadOnAppear(session: UserSessionStore) async {
        let isBrowseDirty = await dirtyBits.isPostcardBrowseDirty()
        let isHasVisibleListings = listings.isEmpty == false
            || pinnedOnShelfListings.isEmpty == false
            || pinnedOrderedListings.isEmpty == false
        if !isBrowseDirty && !isHasVisibleListings && confirmedQuery.isEmpty {
            _ = await loadBrowseListingsFromCache()
        }
        await reloadBrowse(session: session, isExplicitRefresh: false)
    }

    /// Refreshes browse data for the current query value.
    func refresh(session: UserSessionStore) async {
        await reloadBrowse(session: session, isExplicitRefresh: true)
    }

    /// Executes backend search using the current query text.
    func performConfirmedSearch(session: UserSessionStore) async {
        confirmedQuery = query
        _ = await fetchForQuery(confirmedQuery, session: session)
    }

    /// Clears search query and restores default recent results.
    func clearConfirmedSearch(session: UserSessionStore) async {
        query = ""
        confirmedQuery = ""
        _ = await fetchForQuery(confirmedQuery, session: session)
    }

    /// Reloads the entire postcard browse composition with a consistent refresh contract.
    /// - Parameters:
    ///   - session: Current signed-in session.
    ///   - isExplicitRefresh: True when triggered by pull-to-refresh or another user-initiated refresh action.
    private func reloadBrowse(session: UserSessionStore, isExplicitRefresh: Bool) async {
        if isExplicitRefresh {
            await dirtyBits.markPostcardBrowseDirty()
        }
        _ = await fetchForQuery(
            confirmedQuery,
            session: session,
            isForcingServer: true
        )
    }

    /// Fetches listings from backend using the provided raw query text.
    /// - Parameter rawQuery: User-entered search text before tokenization.
    @discardableResult
    func fetchForQuery(
        _ rawQuery: String,
        session: UserSessionStore,
        isForcingServer: Bool = false
    ) async -> Bool {
        errorMessage = nil
        nextPageCursor = nil
        let tokens = SearchTokenBuilder.queryTokens(from: rawQuery)
        activeSearchToken = tokens.first
        let isLoadSuccess = await loadNextPage(isReset: true, isForcingServer: isForcingServer)
        await refreshPinnedListings(session: session, isForcingServer: isForcingServer)
        if isLoadSuccess && activeSearchToken == nil {
            await cache.save(listings, key: browseCacheKey)
        }
        if isLoadSuccess {
            await dirtyBits.clearPostcardBrowseDirty()
        }
        return isLoadSuccess
    }

    /// Loads the next browse page using current confirmed search context.
    @discardableResult
    func loadNextPage(isReset: Bool = false, isForcingServer: Bool = false) async -> Bool {
        if isReset {
            isLoading = true
            errorMessage = nil
        } else {
            if isLoading || isLoadingNextPage || !isHasMorePages { return false }
            isLoadingNextPage = true
        }

        defer {
            if isReset {
                isLoading = false
            } else {
                isLoadingNextPage = false
            }
        }

        if AppTesting.useMockPostcards {
            listings = [
                AppTesting.fixturePostcardListing(),
                AppTesting.fixtureSoldOutPostcardListing(),
                AppTesting.fixtureOwnedPostcardListing()
            ]
            isHasMorePages = false
            return true
        }

        do {
            let result = try await withTimeout(seconds: AppConfig.Network.requestTimeoutSeconds) {
                if let searchToken = self.activeSearchToken {
                    return try await self.repo.searchByTokenPage(
                        searchToken,
                        limit: AppConfig.Postcard.browseListFetchLimit,
                        cursor: isReset ? nil : self.nextPageCursor,
                        isForcingServer: isForcingServer
                    )
                }
                return try await self.repo.fetchRecentPage(
                    limit: AppConfig.Postcard.browseListFetchLimit,
                    cursor: isReset ? nil : self.nextPageCursor,
                    isForcingServer: isForcingServer
                )
            }

            if isReset {
                listings = result.listings.filter { listing in
                    locallyDeletedListingIds.contains(listing.id) == false
                }
            } else {
                listings.append(contentsOf: result.listings.filter { listing in
                    locallyDeletedListingIds.contains(listing.id) == false
                })
            }
            nextPageCursor = result.nextCursor
            isHasMorePages = result.isHasMore && result.nextCursor != nil
            return true
        } catch is CancellationError {
            return false
        } catch {
            print("❌ fetch postcards page error:", error)
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if isReset {
                listings = []
                isHasMorePages = false
            }
            return false
        }
    }

    /// Listings after stock/country/province/query filters and sorting.
    /// Query filter currently matches title and location fields.
    var filteredListings: [PostcardListing] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let visiblePinnedListings = mergedPinnedListings.filter { listing in
            matchesBrowseFilters(for: listing, normalizedQuery: normalizedQuery)
        }
        let result = listings.filter { listing in
            matchesBrowseFilters(for: listing, normalizedQuery: normalizedQuery)
        }
        let pinnedListingIds = Set(visiblePinnedListings.map(\.id))
        let unpinnedListings = result.filter { pinnedListingIds.contains($0.id) == false }
        let inStockListings = sortListings(unpinnedListings.filter { $0.stock > 0 })
        let soldOutListings = sortListings(unpinnedListings.filter { $0.stock <= 0 })
        let browseListings = inStockListings + soldOutListings
        return visiblePinnedListings + browseListings
    }

    /// Resolves ownership tag for a postcard row id.
    /// - Parameter postcardId: Listing id shown in browse grid.
    /// - Returns: Ownership tag (`On-shelf` or `Ordered`) when applicable.
    func ownershipTag(for postcardId: String) -> OwnershipTag? {
        if onShelfListingIds.contains(postcardId) {
            let listing = mergedPinnedListings.first { $0.id == postcardId }
            if listing?.stock ?? 0 <= 0 {
                return .runOut
            }
            return .onShelf
        }
        if orderedListingIds.contains(postcardId) {
            return .ordered
        }
        return nil
    }

    /// Distinct sorted list of countries present in fetched listings.
    var availableCountries: [String] {
        let set = Set(listings.map { $0.location.country }.filter { !$0.isEmpty })
        return Array(set).sorted()
    }

    /// Distinct sorted list of provinces for the currently selected country.
    var availableProvinces: [String] {
        let filtered = listings.filter { listing in
            selectedCountry == "All" || listing.location.country == selectedCountry
        }
        let set = Set(filtered.map { $0.location.province }.filter { !$0.isEmpty })
        return Array(set).sorted()
    }

    /// Resets province to `All` if the current selection is no longer valid.
    func normalizeProvinceSelection() {
        if selectedProvince != "All" && !availableProvinces.contains(selectedProvince) {
            selectedProvince = "All"
        }
    }

    /// Merged pinned listings ordered by on-shelf first, then ordered.
    private var mergedPinnedListings: [PostcardListing] {
        var mergedPinnedListings: [PostcardListing] = []
        var seenListingIds: Set<String> = []
        for listing in pinnedOnShelfListings + pinnedOrderedListings {
            guard seenListingIds.contains(listing.id) == false else { continue }
            mergedPinnedListings.append(listing)
            seenListingIds.insert(listing.id)
        }
        return mergedPinnedListings
    }

    /// Returns whether a listing should stay visible for the current browse filters.
    /// - Parameters:
    ///   - listing: Listing to validate against stock/location/search filters.
    ///   - normalizedQuery: Lowercased query text already trimmed by caller.
    /// - Returns: `true` when listing matches all active browse filters.
    private func matchesBrowseFilters(for listing: PostcardListing, normalizedQuery: String) -> Bool {
        if selectedCountry != "All" && listing.location.country != selectedCountry {
            return false
        }
        if selectedProvince != "All" && listing.location.province != selectedProvince {
            return false
        }
        if normalizedQuery.isEmpty {
            return true
        }

        return listing.title.lowercased().contains(normalizedQuery)
            || listing.location.country.lowercased().contains(normalizedQuery)
            || listing.location.province.lowercased().contains(normalizedQuery)
            || listing.location.fullLabel.lowercased().contains(normalizedQuery)
    }

    /// Applies the current browse sort to one homogeneous stock bucket.
    /// - Parameter listings: Listings that share the same sold-out/in-stock priority tier.
    /// - Returns: Listings sorted by the user-selected browse order.
    private func sortListings(_ listings: [PostcardListing]) -> [PostcardListing] {
        switch sortOrder {
        case .newest:
            return listings.sorted { $0.createdAt > $1.createdAt }
        case .lowestPrice:
            return listings.sorted { $0.priceHoney < $1.priceHoney }
        }
    }

    /// Marks one listing as locally deleted and removes it from all visible browse datasets.
    /// - Parameter postcardId: Listing id confirmed deleted by seller action.
    func markListingDeletedLocally(postcardId: String) {
        locallyDeletedListingIds.insert(postcardId)
        listings.removeAll { $0.id == postcardId }
        pinnedOnShelfListings.removeAll { $0.id == postcardId }
        pinnedOrderedListings.removeAll { $0.id == postcardId }
        onShelfListingIds.remove(postcardId)
        orderedListingIds.remove(postcardId)
    }

    /// Refreshes user-owned on-shelf and ordered postcard slots for pinned browse display.
    /// - Parameter session: Current signed-in session.
    private func refreshPinnedListings(session: UserSessionStore, isForcingServer: Bool) async {
        guard AppTesting.useMockPostcards == false else {
            pinnedOnShelfListings = []
            pinnedOrderedListings = []
            onShelfListingIds = []
            orderedListingIds = []
            return
        }
        guard let userId = session.authUid, userId.isEmpty == false else {
            pinnedOnShelfListings = []
            pinnedOrderedListings = []
            onShelfListingIds = []
            orderedListingIds = []
            return
        }

        do {
            async let onShelfLoad = repo.fetchMyListings(
                userId: userId,
                limit: AppConfig.Postcard.profileListFetchLimit,
                isForcingServer: isForcingServer
            )
            async let orderedLoad = repo.fetchMyOrderedPostcards(
                userId: userId,
                limit: AppConfig.Postcard.profileListFetchLimit,
                isForcingServer: isForcingServer
            )
            let onShelfListings = try await onShelfLoad
            let orderedSummaries = try await orderedLoad
            let visibleOnShelfListings = onShelfListings.filter { listing in
                locallyDeletedListingIds.contains(listing.id) == false
            }
            let visibleOrderedListings = orderedSummaries
                .map(\.listing)
                .filter { listing in
                    locallyDeletedListingIds.contains(listing.id) == false
                }
            pinnedOnShelfListings = visibleOnShelfListings
            pinnedOrderedListings = visibleOrderedListings
            onShelfListingIds = Set(visibleOnShelfListings.map(\.id))
            orderedListingIds = Set(visibleOrderedListings.map(\.id))
        } catch {
            print("❌ refreshPinnedListings error:", error)
            pinnedOnShelfListings = []
            pinnedOrderedListings = []
            onShelfListingIds = []
            orderedListingIds = []
        }
    }

    /// Loads postcard browse listings from structured cache into current state.
    /// - Returns: `true` when cache exists and is applied.
    private func loadBrowseListingsFromCache() async -> Bool {
        guard let payload = await cache.load(key: browseCacheKey, as: [PostcardListing].self) else {
            return false
        }
        listings = payload.value.filter { listing in
            locallyDeletedListingIds.contains(listing.id) == false
        }
        errorMessage = nil
        return true
    }
}
