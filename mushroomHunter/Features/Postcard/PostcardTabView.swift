import SwiftUI

// MARK: - Models

struct PostcardLocation: Equatable {
    var country: String
    var province: String
    var detail: String

    var shortLabel: String {
        let c = country.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = province.trimmingCharacters(in: .whitespacesAndNewlines)
        if c.isEmpty && p.isEmpty { return "Unknown" }
        if c.isEmpty { return p }
        if p.isEmpty { return c }
        return "\(c), \(p)"
    }

    var fullLabel: String {
        let base = shortLabel
        let d = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if d.isEmpty || base == "Unknown" { return base }
        return "\(base) · \(d)"
    }
}

struct PostcardListing: Identifiable, Equatable {
    let id: String
    let title: String
    let priceHoney: Int
    let location: PostcardLocation
    let sellerName: String
    let stock: Int
}

// MARK: - Root Tab

struct PostcardTabView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case browse = "Browse"
        case register = "Register"

        var id: String { rawValue }
    }

    @State private var section: Section = .browse

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Postcard", selection: $section) {
                    ForEach(Section.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                switch section {
                case .browse:
                    PostcardBrowseView()
                case .register:
                    PostcardRegisterView()
                }
            }
            .navigationTitle("PostCard")
        }
    }
}

// MARK: - Browse

struct PostcardBrowseView: View {
    @State private var query: String = ""
    @State private var selectedCountry: String = "All"
    @State private var selectedProvince: String = "All"
    @State private var sortOrder: SortOrder = .newest

    private enum SortOrder: String, CaseIterable, Identifiable {
        case newest = "Newest"
        case lowestPrice = "Lowest Price"

        var id: String { rawValue }
    }

    private let listings: [PostcardListing] = PostcardSampleData.listings

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                filterBar

                LazyVGrid(columns: gridColumns, spacing: 12) {
                    ForEach(filteredListings) { listing in
                        NavigationLink {
                            PostcardDetailView(listing: listing)
                        } label: {
                            PostcardCardView(listing: listing)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)

                if filteredListings.isEmpty {
                    ContentUnavailableView(
                        "No postcards found",
                        systemImage: "magnifyingglass",
                        description: Text("Try a different search or clear filters.")
                    )
                    .padding(.top, 24)
                }
            }
            .padding(.vertical, 8)
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search title / seller / location")
    }

    private var gridColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    private var filteredListings: [PostcardListing] {
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
            return result.reversed()
        case .lowestPrice:
            return result.sorted { $0.priceHoney < $1.priceHoney }
        }
    }

    private var filterBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Menu {
                    Picker("Country", selection: $selectedCountry) {
                        Text("All").tag("All")
                        ForEach(PostcardSampleData.countries, id: \.self) { country in
                            Text(country).tag(country)
                        }
                    }
                } label: {
                    Label(selectedCountry, systemImage: "globe")
                }

                Menu {
                    Picker("Province", selection: $selectedProvince) {
                        Text("All").tag("All")
                        ForEach(PostcardSampleData.provinces, id: \.self) { province in
                            Text(province).tag(province)
                        }
                    }
                } label: {
                    Label(selectedProvince, systemImage: "map")
                }

                Menu {
                    Picker("Sort", selection: $sortOrder) {
                        ForEach(SortOrder.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                } label: {
                    Label(sortOrder.rawValue, systemImage: "arrow.up.arrow.down")
                }
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
    }
}

private struct PostcardCardView: View {
    let listing: PostcardListing

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
                    .frame(height: 120)
                Image(systemName: "photo")
                    .font(.title)
                    .foregroundStyle(.secondary)
            }

            Text(listing.title)
                .font(.headline)
                .lineLimit(1)

            HStack(spacing: 6) {
                Image(systemName: "mappin.and.ellipse")
                Text(listing.location.shortLabel)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Text("\(listing.priceHoney) 🍯")
                    .font(.subheadline)
                Spacer()
                Text("x\(listing.stock)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
        )
    }
}

// MARK: - Detail

struct PostcardDetailView: View {
    let listing: PostcardListing
    @State private var showBuyConfirm: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemBackground))
                        .frame(height: 220)
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(listing.title)
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(listing.location.fullLabel)
                        .foregroundStyle(.secondary)

                    Text("Seller: \(listing.sellerName)")
                        .foregroundStyle(.secondary)

                    HStack {
                        Text("Price")
                        Spacer()
                        Text("\(listing.priceHoney) 🍯")
                            .fontWeight(.semibold)
                    }

                    HStack {
                        Text("Stock")
                        Spacer()
                        Text("\(listing.stock)")
                            .fontWeight(.semibold)
                    }
                }

                Button {
                    showBuyConfirm = true
                } label: {
                    Text("Buy")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .navigationTitle("Postcard")
        .alert("Confirm Purchase", isPresented: $showBuyConfirm) {
            Button("Confirm") {}
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Honey will be held until you confirm received.")
        }
    }
}

// MARK: - Register

struct PostcardRegisterView: View {
    @State private var title: String = ""
    @State private var priceText: String = ""
    @State private var country: String = ""
    @State private var province: String = ""
    @State private var detail: String = ""
    @State private var stockText: String = "1"
    @State private var showSubmitAlert: Bool = false

    var body: some View {
        Form {
            Section("Snapshot") {
                HStack {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Upload postcard snapshot")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Select") {}
                }
            }

            Section("Postcard Info") {
                TextField("Title", text: $title)
                    .textInputAutocapitalization(.words)

                TextField("Price (honey)", text: $priceText)
                    .keyboardType(.numberPad)
                    .onChange(of: priceText) { _, newValue in
                        let filtered = newValue.filter { $0.isNumber }
                        if filtered != newValue { priceText = filtered }
                    }

                TextField("Country", text: $country)
                TextField("Province", text: $province)
                TextField("Detail (optional)", text: $detail)

                TextField("Stock", text: $stockText)
                    .keyboardType(.numberPad)
                    .onChange(of: stockText) { _, newValue in
                        let filtered = newValue.filter { $0.isNumber }
                        if filtered != newValue { stockText = filtered }
                    }
            }

            Section {
                Button("Submit Postcard") {
                    showSubmitAlert = true
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .alert("Submitted", isPresented: $showSubmitAlert) {
            Button("OK") {}
        } message: {
            Text("Postcard submission will be wired to Firebase next.")
        }
    }
}

// MARK: - Sample Data

private enum PostcardSampleData {
    static let countries = ["Japan", "USA", "Canada", "UK"]
    static let provinces = ["Tokyo", "California", "Ontario", "London"]

    static let listings: [PostcardListing] = [
        PostcardListing(
            id: "pc1",
            title: "Cherry Blossom Station",
            priceHoney: 120,
            location: PostcardLocation(country: "Japan", province: "Tokyo", detail: "Meguro"),
            sellerName: "Ken",
            stock: 3
        ),
        PostcardListing(
            id: "pc2",
            title: "Golden Gate Sunset",
            priceHoney: 180,
            location: PostcardLocation(country: "USA", province: "California", detail: "San Francisco"),
            sellerName: "Ava",
            stock: 1
        ),
        PostcardListing(
            id: "pc3",
            title: "Old Town Street",
            priceHoney: 90,
            location: PostcardLocation(country: "Canada", province: "Ontario", detail: "Toronto"),
            sellerName: "Niko",
            stock: 4
        )
    ]
}

// MARK: - Preview

#Preview {
    PostcardTabView()
}
