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
    /// Raw listings fetched from Firestore before local filters are applied.
    @Published var listings: [PostcardListing] = []
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
    /// Cursor for loading the next browse page.
    private var nextPageCursor: FbPostcardRepo.ListingPageCursor? = nil
    /// Last query committed to backend search.
    private var confirmedQuery: String = ""
    /// Active backend token for paged search mode.
    private var activeSearchToken: String? = nil

    /// Loads data only when no listings have been fetched yet.
    func loadIfNeeded() async {
        if listings.isEmpty {
            await refresh()
        }
    }

    /// Refreshes browse data for the current query value.
    func refresh() async {
        await fetchForQuery(confirmedQuery)
    }

    /// Executes backend search using the current query text.
    func performConfirmedSearch() async {
        confirmedQuery = query
        await fetchForQuery(confirmedQuery)
    }

    /// Clears search query and restores default recent results.
    func clearConfirmedSearch() async {
        query = ""
        confirmedQuery = ""
        await fetchForQuery(confirmedQuery)
    }

    /// Fetches listings from backend using the provided raw query text.
    /// - Parameter rawQuery: User-entered search text before tokenization.
    func fetchForQuery(_ rawQuery: String) async {
        errorMessage = nil
        nextPageCursor = nil
        let tokens = SearchTokenBuilder.queryTokens(from: rawQuery)
        activeSearchToken = tokens.first
        await loadNextPage(isReset: true)
    }

    /// Loads the next browse page using current confirmed search context.
    func loadNextPage(isReset: Bool = false) async {
        if isReset {
            isLoading = true
            errorMessage = nil
        } else {
            if isLoading || isLoadingNextPage || !isHasMorePages { return }
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
                AppTesting.fixtureOwnedPostcardListing()
            ]
            isHasMorePages = false
            return
        }

        do {
            let result = try await withTimeout(seconds: AppConfig.Network.requestTimeoutSeconds) {
                if let searchToken = self.activeSearchToken {
                    return try await self.repo.searchByTokenPage(
                        searchToken,
                        limit: AppConfig.Postcard.browseListFetchLimit,
                        cursor: isReset ? nil : self.nextPageCursor
                    )
                }
                return try await self.repo.fetchRecentPage(
                    limit: AppConfig.Postcard.browseListFetchLimit,
                    cursor: isReset ? nil : self.nextPageCursor
                )
            }

            if isReset {
                listings = result.listings
            } else {
                listings.append(contentsOf: result.listings)
            }
            nextPageCursor = result.nextCursor
            isHasMorePages = result.isHasMore && result.nextCursor != nil
        } catch is CancellationError {
            return
        } catch {
            print("❌ fetch postcards page error:", error)
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if isReset {
                listings = []
                isHasMorePages = false
            }
        }
    }

    /// Listings after stock/country/province/query filters and sorting.
    /// Query filter currently matches title and location fields.
    var filteredListings: [PostcardListing] {
        var result = listings.filter { $0.stock > 0 }

        if selectedCountry != "All" {
            result = result.filter { $0.location.country == selectedCountry }
        }
        if selectedProvince != "All" {
            result = result.filter { $0.location.province == selectedProvince }
        }

        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            result = result.filter {
                $0.title.lowercased().contains(q)
                || $0.location.country.lowercased().contains(q)
                || $0.location.province.lowercased().contains(q)
                || $0.location.fullLabel.lowercased().contains(q)
            }
        }

        switch sortOrder {
        case .newest:
            return result.sorted { $0.createdAt > $1.createdAt }
        case .lowestPrice:
            return result.sorted { $0.priceHoney < $1.priceHoney }
        }
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
}
