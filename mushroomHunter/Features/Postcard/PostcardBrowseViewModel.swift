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
final class PostcardBrowseViewModel: ObservableObject {
    @Published var listings: [PostcardListing] = [] // State or dependency property.
    @Published var isLoading: Bool = false // State or dependency property.
    @Published var errorMessage: String? = nil // State or dependency property.
    @Published var query: String = "" // State or dependency property.
    @Published var selectedCountry: String = "All" // State or dependency property.
    @Published var selectedProvince: String = "All" // State or dependency property.
    @Published var sortOrder: PostcardSortOrder = .newest // State or dependency property.
    private let repo = FirebasePostcardRepository()
    private var searchTask: Task<Void, Never>? = nil

    func loadIfNeeded() async { // Handles loadIfNeeded flow.
        if listings.isEmpty {
            await refresh()
        }
    }

    func refresh() async { // Handles refresh flow.
        await fetchForQuery(query)
    }

    func scheduleSearch() { // Handles scheduleSearch flow.
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: AppConfig.Postcard.searchDebounceNanoseconds)
            await fetchForQuery(query)
        }
    }

    func fetchForQuery(_ rawQuery: String) async { // Handles fetchForQuery flow.
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

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
                || $0.sellerName.lowercased().contains(q)
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

    var availableCountries: [String] {
        let set = Set(listings.map { $0.location.country }.filter { !$0.isEmpty })
        return Array(set).sorted()
    }

    var availableProvinces: [String] {
        let filtered = listings.filter { listing in
            selectedCountry == "All" || listing.location.country == selectedCountry
        }
        let set = Set(filtered.map { $0.location.province }.filter { !$0.isEmpty })
        return Array(set).sorted()
    }

    func normalizeProvinceSelection() { // Handles normalizeProvinceSelection flow.
        if selectedProvince != "All" && !availableProvinces.contains(selectedProvince) {
            selectedProvince = "All"
        }
    }
}
