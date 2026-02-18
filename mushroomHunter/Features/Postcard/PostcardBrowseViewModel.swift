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

    /// Loads data only when no listings have been fetched yet.
    func loadIfNeeded() async {
        if listings.isEmpty {
            await refresh()
        }
    }

    /// Refreshes browse data for the current query value.
    func refresh() async {
        await fetchForQuery("")
    }

    /// Executes backend search using the current query text.
    func performConfirmedSearch() async {
        await fetchForQuery(query)
    }

    /// Clears search query and restores default recent results.
    func clearConfirmedSearch() async {
        query = ""
        await fetchForQuery("")
    }

    /// Fetches listings from backend using the provided raw query text.
    /// - Parameter rawQuery: User-entered search text before tokenization.
    func fetchForQuery(_ rawQuery: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        if AppTesting.useMockPostcards {
            listings = [
                AppTesting.fixturePostcardListing(),
                AppTesting.fixtureOwnedPostcardListing()
            ]
            return
        }

        let tokens = SearchTokenBuilder.queryTokens(from: rawQuery)
        do {
            let results: [PostcardListing]
            if let first = tokens.first {
                results = try await withTimeout(seconds: AppConfig.Network.requestTimeoutSeconds) {
                    try await self.repo.searchByToken(first)
                }
            } else {
                results = try await withTimeout(seconds: AppConfig.Network.requestTimeoutSeconds) {
                    try await self.repo.fetchRecent()
                }
            }
            self.listings = results
        } catch is CancellationError {
            return
        } catch {
            print("❌ fetch postcards error:", error)
            self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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
