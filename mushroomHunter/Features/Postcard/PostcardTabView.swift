import SwiftUI

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
    @StateObject private var vm = PostcardBrowseViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let err = vm.errorMessage {
                    Text(err)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                }

                filterBar

                LazyVGrid(columns: gridColumns, spacing: 12) {
                    ForEach(vm.filteredListings) { listing in
                        NavigationLink {
                            PostcardDetailView(listing: listing)
                        } label: {
                            PostcardCardView(listing: listing)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)

                if vm.filteredListings.isEmpty && !vm.isLoading {
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
        .overlay {
            if vm.isLoading && vm.filteredListings.isEmpty {
                ProgressView("Loading postcards…")
            }
        }
        .searchable(text: $vm.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search title / seller / location")
        .onChange(of: vm.query) { _, _ in
            vm.scheduleSearch()
        }
        .onChange(of: vm.selectedCountry) { _, _ in
            vm.normalizeProvinceSelection()
        }
        .task {
            await vm.loadIfNeeded()
        }
        .refreshable {
            await vm.refresh()
        }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    private var filterBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Menu {
                    Picker("Country", selection: $vm.selectedCountry) {
                        Text("All").tag("All")
                        ForEach(vm.availableCountries, id: \.self) { country in
                            Text(country).tag(country)
                        }
                    }
                } label: {
                    Label(vm.selectedCountry, systemImage: "globe")
                }

                Menu {
                    Picker("Province", selection: $vm.selectedProvince) {
                        Text("All").tag("All")
                        ForEach(vm.availableProvinces, id: \.self) { province in
                            Text(province).tag(province)
                        }
                    }
                } label: {
                    Label(vm.selectedProvince, systemImage: "map")
                }

                Menu {
                    Picker("Sort", selection: $vm.sortOrder) {
                        ForEach(PostcardSortOrder.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                } label: {
                    Label(vm.sortOrder.rawValue, systemImage: "arrow.up.arrow.down")
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

                if let urlString = listing.imageUrl, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            Image(systemName: "photo")
                                .font(.title)
                                .foregroundStyle(.secondary)
                        case .empty:
                            ProgressView()
                        @unknown default:
                            Image(systemName: "photo")
                                .font(.title)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Image(systemName: "photo")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
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

                    if let urlString = listing.imageUrl, let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure:
                                Image(systemName: "photo")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                            case .empty:
                                ProgressView()
                            @unknown default:
                                Image(systemName: "photo")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    } else {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
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

// MARK: - Preview

#Preview {
    PostcardTabView()
}
