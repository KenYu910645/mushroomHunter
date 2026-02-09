import SwiftUI

// MARK: - Root Tab

struct PostcardTabView: View {
    @State private var showRegisterSheet: Bool = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                PostcardBrowseView(onRegister: { showRegisterSheet = true })
            }
            .navigationTitle(LocalizedStringKey("postcard_title"))
            .background(Theme.backgroundGradient(for: scheme))
        }
        .sheet(isPresented: $showRegisterSheet) {
            NavigationStack {
                PostcardRegisterView()
                    .navigationTitle(LocalizedStringKey("postcard_register_title"))
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
    @Environment(\.colorScheme) private var scheme
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
                        LocalizedStringKey("postcard_empty_title"),
                        systemImage: "magnifyingglass",
                        description: Text(LocalizedStringKey("postcard_empty_description"))
                    )
                    .padding(.top, 24)
                }
            }
            .padding(.vertical, 8)
        }
        .background(Theme.backgroundGradient(for: scheme))
        .overlay {
            if vm.isLoading && vm.filteredListings.isEmpty {
                ProgressView("Loading postcards…")
            }
        }
        .alert(LocalizedStringKey("postcard_search_title"), isPresented: $showSearchAlert) {
            TextField(LocalizedStringKey("postcard_search_placeholder"), text: $vm.query)
            Button(LocalizedStringKey("common_clear")) { vm.query = "" }
            Button(LocalizedStringKey("common_done")) {}
        } message: {
            Text(LocalizedStringKey("postcard_search_message"))
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
        .onAppear {
            Task { await session.refreshProfileFromBackend() }
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
                .accessibilityLabel(LocalizedStringKey("postcard_search_accessibility"))

                Button {
                    onRegister()
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .accessibilityLabel(LocalizedStringKey("postcard_register_accessibility"))

                Menu {
                    Section {
                        Picker(LocalizedStringKey("postcard_country"), selection: $vm.selectedCountry) {
                            Text(LocalizedStringKey("common_all")).tag("All")
                            ForEach(vm.availableCountries, id: \.self) { country in
                                Text(country).tag(country)
                            }
                        }
                    } header: {
                        Text(LocalizedStringKey("postcard_country"))
                    }
                    Section {
                        Picker(LocalizedStringKey("postcard_province"), selection: $vm.selectedProvince) {
                            Text(LocalizedStringKey("common_all")).tag("All")
                            ForEach(vm.availableProvinces, id: \.self) { province in
                                Text(province).tag(province)
                            }
                        }
                    } header: {
                        Text(LocalizedStringKey("postcard_province"))
                    }
                    Section {
                        Picker(LocalizedStringKey("postcard_sort"), selection: $vm.sortOrder) {
                            ForEach(PostcardSortOrder.allCases) { option in
                                Text(LocalizedStringKey(option.localizedKey))
                                    .tag(option)
                            }
                        }
                    } header: {
                        Text(LocalizedStringKey("postcard_sort"))
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel(LocalizedStringKey("common_filters"))
            }
        }
        .padding(.horizontal)
    }
}

private struct PostcardCardView: View {
    let listing: PostcardListing
    @Environment(\.colorScheme) private var scheme

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
                Text(String(format: NSLocalizedString("postcard_price_honey_format", comment: ""), listing.priceHoney))
                    .font(.subheadline)
                Spacer()
                Text(String(format: NSLocalizedString("postcard_stock_format", comment: ""), listing.stock))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.cardBackground(for: scheme))
                .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
        )
    }
}

// MARK: - Detail

struct PostcardDetailView: View {
    let listing: PostcardListing
    @State private var showBuyConfirm: Bool = false
    @Environment(\.colorScheme) private var scheme

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

                    Text(String(format: NSLocalizedString("postcard_seller_format", comment: ""), listing.sellerName))
                        .foregroundStyle(.secondary)

                    HStack {
                        Text(LocalizedStringKey("postcard_price_label"))
                        Spacer()
                        Text(String(format: NSLocalizedString("postcard_price_honey_format", comment: ""), listing.priceHoney))
                            .fontWeight(.semibold)
                    }

                    HStack {
                        Text(LocalizedStringKey("postcard_stock_label"))
                        Spacer()
                        Text(String(format: NSLocalizedString("postcard_stock_plain_format", comment: ""), listing.stock))
                            .fontWeight(.semibold)
                    }
                }

                Button {
                    showBuyConfirm = true
                } label: {
                    Text(LocalizedStringKey("postcard_buy_button"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .background(Theme.backgroundGradient(for: scheme))
        .navigationTitle(LocalizedStringKey("postcard_title"))
        .alert(LocalizedStringKey("postcard_confirm_title"), isPresented: $showBuyConfirm) {
            Button(LocalizedStringKey("common_confirm")) {}
            Button(LocalizedStringKey("common_cancel"), role: .cancel) {}
        } message: {
            Text(LocalizedStringKey("postcard_confirm_message"))
        }
    }
}

// MARK: - Register

struct PostcardRegisterView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.colorScheme) private var scheme
    @State private var title: String = ""
    @State private var priceText: String = ""
    @State private var country: String = ""
    @State private var province: String = ""
    @State private var detail: String = ""
    @State private var stockText: String = "1"
    @State private var showSubmitAlert: Bool = false

    var body: some View {
        Form {
            Section(LocalizedStringKey("postcard_snapshot_section")) {
                VStack(alignment: .leading, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemBackground))
                            .frame(height: 160)
                        VStack(spacing: 6) {
                            Image(systemName: "photo")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text(LocalizedStringKey("postcard_snapshot_hint"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section(LocalizedStringKey("postcard_info_section")) {
                TextField(LocalizedStringKey("postcard_title_field"), text: $title)
                    .textInputAutocapitalization(.words)

                TextField(LocalizedStringKey("postcard_price_field"), text: $priceText)
                    .keyboardType(.numberPad)
                    .onChange(of: priceText) { _, newValue in
                        let filtered = newValue.filter { $0.isNumber }
                        if filtered != newValue { priceText = filtered }
                    }

                TextField(LocalizedStringKey("postcard_country_field"), text: $country)
                TextField(LocalizedStringKey("postcard_province_field"), text: $province)
                TextField(LocalizedStringKey("postcard_detail_field"), text: $detail)

                TextField(LocalizedStringKey("postcard_stock_field"), text: $stockText)
                    .keyboardType(.numberPad)
                    .onChange(of: stockText) { _, newValue in
                        let filtered = newValue.filter { $0.isNumber }
                        if filtered != newValue { stockText = filtered }
                    }
            }

            Section {
                Button(LocalizedStringKey("postcard_submit_button")) {
                    showSubmitAlert = true
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundGradient(for: scheme))
        .alert(LocalizedStringKey("postcard_submitted_title"), isPresented: $showSubmitAlert) {
            Button(LocalizedStringKey("common_ok")) {}
        } message: {
            Text(LocalizedStringKey("postcard_submitted_message"))
        }
    }
}

// MARK: - Preview

#Preview {
    PostcardTabView()
}
