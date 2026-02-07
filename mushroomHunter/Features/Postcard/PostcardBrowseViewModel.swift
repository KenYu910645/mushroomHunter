import Foundation
import SwiftUI
import Combine

@MainActor
final class PostcardBrowseViewModel: ObservableObject {
    @Published var listings: [PostcardListing] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    @Published var query: String = ""
    @Published var selectedCountry: String = "All"
    @Published var selectedProvince: String = "All"
    @Published var sortOrder: PostcardSortOrder = .newest

    private let repo = FirebasePostcardRepository()
    private var searchTask: Task<Void, Never>? = nil

    func loadIfNeeded() async {
        if listings.isEmpty {
            await refresh()
        }
    }

    func refresh() async {
        await fetchForQuery(query)
    }

    func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            await fetchForQuery(query)
        }
    }

    func fetchForQuery(_ rawQuery: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let tokens = SearchTokenBuilder.queryTokens(from: rawQuery)
        do {
            let results: [PostcardListing]
            if let first = tokens.first {
                results = try await withTimeout(seconds: 10) {
                    try await self.repo.searchByToken(first)
                }
            } else {
                results = try await withTimeout(seconds: 10) {
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

    func normalizeProvinceSelection() {
        if selectedProvince != "All" && !availableProvinces.contains(selectedProvince) {
            selectedProvince = "All"
        }
    }
}
