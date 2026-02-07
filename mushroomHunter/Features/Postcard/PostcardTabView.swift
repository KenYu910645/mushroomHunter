import SwiftUI

// MARK: - Root Tab

struct PostcardTabView: View {
    @State private var showRegisterSheet: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                PostcardBrowseView(onRegister: { showRegisterSheet = true })
            }
            .navigationTitle("PostCard")
        }
        .sheet(isPresented: $showRegisterSheet) {
            NavigationStack {
                PostcardRegisterView()
                    .navigationTitle("Register")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button {
                                showRegisterSheet = false
                            } label: {
                                Image(systemName: "xmark")
                            }
                        }
                    }
            }
        }
    }
}

// MARK: - Browse

struct PostcardBrowseView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var vm = PostcardBrowseViewModel()
    @State private var showSearchAlert: Bool = false
    let onRegister: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let err = vm.errorMessage {
                    Text(err)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                }

                headerBar

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
        .alert("Search Postcards", isPresented: $showSearchAlert) {
            TextField("Search title / seller / location", text: $vm.query)
            Button("Clear") { vm.query = "" }
            Button("Done") {}
        } message: {
            Text("Type to filter postcards.")
        }
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

    private var headerBar: some View {
        HStack {
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
                .accessibilityLabel("Search postcards")

                Button {
                    onRegister()
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .accessibilityLabel("Register postcard")

                Menu {
                    Section("Country") {
                        Picker("Country", selection: $vm.selectedCountry) {
                            Text("All").tag("All")
                            ForEach(vm.availableCountries, id: \.self) { country in
                                Text(country).tag(country)
                            }
                        }
                    }
                    Section("Province") {
                        Picker("Province", selection: $vm.selectedProvince) {
                            Text("All").tag("All")
                            ForEach(vm.availableProvinces, id: \.self) { province in
                                Text(province).tag(province)
                            }
                        }
                    }
                    Section("Sort") {
                        Picker("Sort", selection: $vm.sortOrder) {
                            ForEach(PostcardSortOrder.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Filters")
            }
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
    @EnvironmentObject private var session: SessionStore
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
                VStack(alignment: .leading, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemBackground))
                            .frame(height: 160)
                        VStack(spacing: 6) {
                            Image(systemName: "photo")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text("Snapshot optional (upload disabled)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
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
