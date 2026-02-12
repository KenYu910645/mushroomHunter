import SwiftUI
import PhotosUI

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
                            PostcardCardView(listing: listing, cardWidth: cardWidth)
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

    // 2-column layout: horizontal padding(16 + 16) + inter-item spacing(12)
    private var cardWidth: CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        return max(120, (screenWidth - 44) / 2.0)
    }

    private var headerBar: some View {
        HStack {
            HStack(spacing: 6) {
                Image("HoneyIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
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
    let cardWidth: CGFloat
    @Environment(\.colorScheme) private var scheme
    private let imageAspectRatio: CGFloat = 4.0 / 3.0

    private var imageHeight: CGFloat {
        cardWidth / imageAspectRatio
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
                    .frame(height: imageHeight)

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
                    .frame(height: imageHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Image(systemName: "photo")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: imageHeight)

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
    private let imageAspectRatio: CGFloat = 4.0 / 3.0
    private let detailImageMaxWidth: CGFloat = 300

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemBackground))
                        .frame(maxWidth: .infinity)
                        .aspectRatio(imageAspectRatio, contentMode: .fit)

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
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    } else {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: detailImageMaxWidth)
                .frame(maxWidth: .infinity, alignment: .center)
                .aspectRatio(imageAspectRatio, contentMode: .fit)

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
    @State private var showErrorAlert: Bool = false
    @State private var errorAlertMessage: String = ""
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedImage: UIImage? = nil
    @State private var isUploading: Bool = false
    @State private var uploadError: String? = nil
    @State private var uploadedImageUrl: URL? = nil

    private let uploader = FirebasePostcardImageUploader()
    private let repo = FirebasePostcardRepository()

    var body: some View {
        Form {
            Section(LocalizedStringKey("postcard_snapshot_section")) {
                VStack(alignment: .leading, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemBackground))
                            .frame(height: 160)

                        if let uiImage = selectedImage {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else {
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

                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        Label(LocalizedStringKey("postcard_select_photo_button"), systemImage: "photo.on.rectangle")
                    }

                    if isUploading {
                        ProgressView(LocalizedStringKey("postcard_uploading"))
                    }

                    if let err = uploadError {
                        Text(err)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    if let url = uploadedImageUrl {
                        Text("\(NSLocalizedString("postcard_uploaded_prefix", comment: "")) \(url.absoluteString)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
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
                    Task { await submitPostcard() }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .buttonStyle(.borderedProminent)
                .disabled(isUploading || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundGradient(for: scheme))
        .onChange(of: selectedItem) { _, newValue in
            guard let newValue else { return }
            Task { await loadSelectedPhoto(newValue) }
        }
        .alert(LocalizedStringKey("postcard_submitted_title"), isPresented: $showSubmitAlert) {
            Button(LocalizedStringKey("common_ok")) {}
        } message: {
            Text(LocalizedStringKey("postcard_submitted_message"))
        }
        .alert(LocalizedStringKey("common_error"), isPresented: $showErrorAlert) {
            Button(LocalizedStringKey("common_ok")) {}
        } message: {
            Text(errorAlertMessage)
        }
    }

    private func loadSelectedPhoto(_ item: PhotosPickerItem) async {
        uploadError = nil
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                selectedImage = image
            } else {
                uploadError = NSLocalizedString("postcard_upload_load_error", comment: "")
            }
        } catch {
            uploadError = error.localizedDescription
        }
    }

    private func submitPostcard() async {
        uploadError = nil
        showSubmitAlert = false
        showErrorAlert = false
        errorAlertMessage = ""

        guard !isUploading else { return }

        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }

        let price = Int(priceText.filter { $0.isNumber }) ?? 0
        guard price > 0 else {
            presentError(NSLocalizedString("postcard_validation_price_error", comment: ""))
            return
        }

        let stock = Int(stockText.filter { $0.isNumber }) ?? 0
        guard stock > 0 else {
            presentError(NSLocalizedString("postcard_validation_stock_error", comment: ""))
            return
        }

        let cleanCountry = country.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanProvince = province.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanCountry.isEmpty, !cleanProvince.isEmpty else {
            presentError(NSLocalizedString("postcard_validation_location_error", comment: ""))
            return
        }

        guard let image = selectedImage else {
            presentError(NSLocalizedString("postcard_upload_select_error", comment: ""))
            return
        }
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            presentError(NSLocalizedString("postcard_upload_process_error", comment: ""))
            return
        }

        isUploading = true
        defer { isUploading = false }

        do {
            let imageUrl = try await uploader.uploadPostcardImage(data: data, ownerId: session.authUid)
            uploadedImageUrl = imageUrl

            try await repo.createPostcard(
                title: cleanTitle,
                priceHoney: price,
                location: PostcardLocation(
                    country: cleanCountry,
                    province: cleanProvince,
                    detail: detail.trimmingCharacters(in: .whitespacesAndNewlines)
                ),
                stock: stock,
                sellerName: session.displayName.isEmpty ? "Unknown" : session.displayName,
                imageUrl: imageUrl.absoluteString
            )

            resetForm()
            showSubmitAlert = true
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            presentError(message)
        }
    }

    private func presentError(_ message: String) {
        uploadError = message
        errorAlertMessage = message
        showErrorAlert = true
    }

    private func resetForm() {
        title = ""
        priceText = ""
        country = ""
        province = ""
        detail = ""
        stockText = "1"
        selectedItem = nil
        selectedImage = nil
        uploadedImageUrl = nil
    }
}

// MARK: - Preview

#Preview {
    PostcardTabView()
}
