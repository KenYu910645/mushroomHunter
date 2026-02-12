import SwiftUI
import PhotosUI

private let postcardMaxPriceHoney: Int = 1_000_000_000
private let postcardMaxStock: Int = 1_000_000

private func clampedNumericText(_ value: String, max: Int) -> String {
    let digits = value.filter { $0.isNumber }
    guard !digits.isEmpty else { return "" }

    let maxText = String(max)
    if digits.count > maxText.count {
        return maxText
    }
    if digits.count == maxText.count && digits > maxText {
        return maxText
    }
    return digits
}

// MARK: - Root Tab

struct PostcardTabView: View {
    @State private var showRegisterSheet: Bool = false
    @State private var browseRefreshToken: Int = 0
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                PostcardBrowseView(
                    refreshToken: browseRefreshToken,
                    onRegister: { showRegisterSheet = true }
                )
            }
            .navigationTitle(LocalizedStringKey("postcard_title"))
            .background(Theme.backgroundGradient(for: scheme))
        }
        .sheet(isPresented: $showRegisterSheet) {
            NavigationStack {
                PostcardRegisterView {
                    showRegisterSheet = false
                    browseRefreshToken += 1
                }
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
    let refreshToken: Int
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
                        .contentShape(RoundedRectangle(cornerRadius: 12))
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
        .onAppear {
            Task {
                await session.refreshProfileFromBackend()
                await vm.refresh()
            }
        }
        .task(id: refreshToken) {
            await vm.refresh()
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
        .frame(width: cardWidth, alignment: .topLeading)
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Detail

struct PostcardDetailView: View {
    @State private var showBuyConfirm: Bool = false
    @State private var showEditSheet: Bool = false
    @State private var currentListing: PostcardListing
    @State private var isBuying: Bool = false
    @State private var showBuySuccessAlert: Bool = false
    @State private var showBuyErrorAlert: Bool = false
    @State private var buyErrorMessage: String = ""
    @State private var showShippingSheet: Bool = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore
    private let repo = FirebasePostcardRepository()
    private let imageAspectRatio: CGFloat = 4.0 / 3.0
    private let detailImageMaxWidth: CGFloat = 300

    init(listing: PostcardListing) {
        _currentListing = State(initialValue: listing)
    }

    private var isSeller: Bool {
        guard let uid = session.authUid else { return false }
        return uid == currentListing.sellerId
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemBackground))
                        .frame(maxWidth: .infinity)
                        .aspectRatio(imageAspectRatio, contentMode: .fit)

                    if let urlString = currentListing.imageUrl, let url = URL(string: urlString) {
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
                    Text(currentListing.title)
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(currentListing.location.fullLabel)
                        .foregroundStyle(.secondary)

                    Text(String(format: NSLocalizedString("postcard_seller_format", comment: ""), currentListing.sellerName))
                        .foregroundStyle(.secondary)

                    HStack {
                        Text(LocalizedStringKey("postcard_price_label"))
                        Spacer()
                        Text(String(format: NSLocalizedString("postcard_price_honey_format", comment: ""), currentListing.priceHoney))
                            .fontWeight(.semibold)
                    }

                    HStack {
                        Text(LocalizedStringKey("postcard_stock_label"))
                        Spacer()
                        Text(String(format: NSLocalizedString("postcard_stock_plain_format", comment: ""), currentListing.stock))
                            .fontWeight(.semibold)
                    }
                }

                if !isSeller {
                    Button {
                        showBuyConfirm = true
                    } label: {
                        if isBuying {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text(LocalizedStringKey("postcard_buy_button"))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBuying)
                }
            }
            .padding()
        }
        .background(Theme.backgroundGradient(for: scheme))
        .navigationTitle(LocalizedStringKey("postcard_title"))
        .toolbar {
            if isSeller {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showEditSheet = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel(LocalizedStringKey("postcard_edit_accessibility"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showShippingSheet = true
                    } label: {
                        Image(systemName: "shippingbox")
                    }
                    .accessibilityLabel(LocalizedStringKey("postcard_shipping_accessibility"))
                }
            }
        }
        .alert(LocalizedStringKey("postcard_confirm_title"), isPresented: $showBuyConfirm) {
            Button(LocalizedStringKey("common_confirm")) {
                Task { await buyPostcard() }
            }
            Button(LocalizedStringKey("common_cancel"), role: .cancel) {}
        } message: {
            Text(LocalizedStringKey("postcard_confirm_message"))
        }
        .alert(LocalizedStringKey("postcard_buy_success_title"), isPresented: $showBuySuccessAlert) {
            Button(LocalizedStringKey("common_ok")) {}
        } message: {
            Text(LocalizedStringKey("postcard_buy_success_message"))
        }
        .alert(LocalizedStringKey("common_error"), isPresented: $showBuyErrorAlert) {
            Button(LocalizedStringKey("common_ok")) {}
        } message: {
            Text(buyErrorMessage)
        }
        .task {
            await refreshListing()
        }
        .refreshable {
            await refreshListing()
        }
        .sheet(isPresented: $showEditSheet, onDismiss: {
            Task { await refreshListing() }
        }) {
            NavigationStack {
                PostcardEditView(listing: currentListing) {
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showShippingSheet) {
            NavigationStack {
                PostcardShippingView(postcard: currentListing)
            }
        }
    }

    private func refreshListing() async {
        do {
            if let refreshed = try await repo.fetchPostcard(postcardId: currentListing.id) {
                currentListing = refreshed
            } else {
                dismiss()
            }
        } catch {
            // Keep existing content if network refresh fails.
        }
    }

    private func buyPostcard() async {
        guard !isBuying else { return }
        isBuying = true
        defer { isBuying = false }

        do {
            _ = try await repo.buyPostcard(postcardId: currentListing.id)
            await session.refreshProfileFromBackend()
            await refreshListing()
            showBuySuccessAlert = true
        } catch {
            buyErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            showBuyErrorAlert = true
        }
    }
}

struct PostcardShippingView: View {
    let postcard: PostcardListing

    @Environment(\.dismiss) private var dismiss
    @State private var recipients: [PostcardShippingRecipient] = []
    @State private var isLoading: Bool = false
    @State private var isSendingOrderId: String? = nil
    @State private var errorMessage: String?
    private let repo = FirebasePostcardRepository()

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            if isLoading && recipients.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if recipients.isEmpty {
                Text(LocalizedStringKey("postcard_shipping_empty"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recipients) { recipient in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(recipient.buyerName)
                            .font(.headline)
                        Text(
                            String(
                                format: NSLocalizedString("postcard_shipping_friend_code_format", comment: ""),
                                recipient.buyerFriendCode.isEmpty ? "-" : recipient.buyerFriendCode
                            )
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                        Button {
                            Task { await markSent(recipient) }
                        } label: {
                            if isSendingOrderId == recipient.id {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text(LocalizedStringKey("postcard_shipping_send_button"))
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSendingOrderId != nil)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle(LocalizedStringKey("postcard_shipping_title"))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(LocalizedStringKey("common_close")) {
                    dismiss()
                }
            }
        }
        .task {
            await loadRecipients()
        }
        .refreshable {
            await loadRecipients()
        }
    }

    private func loadRecipients() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            recipients = try await repo.fetchShippingRecipients(postcardId: postcard.id)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func markSent(_ recipient: PostcardShippingRecipient) async {
        guard isSendingOrderId == nil else { return }
        isSendingOrderId = recipient.id
        defer { isSendingOrderId = nil }

        do {
            try await repo.markPostcardSent(orderId: recipient.id)
            recipients.removeAll { $0.id == recipient.id }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct PostcardEditView: View {
    let listing: PostcardListing
    let onDeleted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var priceText: String
    @State private var country: String
    @State private var province: String
    @State private var detail: String
    @State private var stockText: String
    @State private var isSaving: Bool = false
    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""
    @State private var showDeleteConfirm: Bool = false
    private let repo = FirebasePostcardRepository()

    init(listing: PostcardListing, onDeleted: @escaping () -> Void) {
        self.listing = listing
        self.onDeleted = onDeleted
        _title = State(initialValue: listing.title)
        _priceText = State(initialValue: "\(listing.priceHoney)")
        _country = State(initialValue: listing.location.country)
        _province = State(initialValue: listing.location.province)
        _detail = State(initialValue: listing.location.detail)
        _stockText = State(initialValue: "\(listing.stock)")
    }

    var body: some View {
        Form {
            Section(LocalizedStringKey("postcard_info_section")) {
                TextField(LocalizedStringKey("postcard_title_field"), text: $title)
                    .textInputAutocapitalization(.words)

                TextField(LocalizedStringKey("postcard_price_field"), text: $priceText)
                    .keyboardType(.numberPad)
                    .onChange(of: priceText) { _, newValue in
                        let clamped = clampedNumericText(newValue, max: postcardMaxPriceHoney)
                        if clamped != newValue { priceText = clamped }
                    }

                TextField(LocalizedStringKey("postcard_country_field"), text: $country)
                TextField(LocalizedStringKey("postcard_province_field"), text: $province)
                TextField(LocalizedStringKey("postcard_detail_field"), text: $detail)

                TextField(LocalizedStringKey("postcard_stock_field"), text: $stockText)
                    .keyboardType(.numberPad)
                    .onChange(of: stockText) { _, newValue in
                        let clamped = clampedNumericText(newValue, max: postcardMaxStock)
                        if clamped != newValue { stockText = clamped }
                    }
            }

            Section {
                Button(LocalizedStringKey("common_save")) {
                    Task { await saveChanges() }
                }
                .disabled(isSaving)
            }

            Section {
                Button(LocalizedStringKey("postcard_remove_button"), role: .destructive) {
                    showDeleteConfirm = true
                }
                .disabled(isSaving)
            }
        }
        .navigationTitle(LocalizedStringKey("postcard_edit_title"))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(LocalizedStringKey("common_cancel")) {
                    dismiss()
                }
            }
        }
        .confirmationDialog(
            LocalizedStringKey("postcard_remove_confirm_title"),
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(LocalizedStringKey("postcard_remove_button"), role: .destructive) {
                Task { await removePostcard() }
            }
            Button(LocalizedStringKey("common_cancel"), role: .cancel) {}
        }
        .alert(LocalizedStringKey("common_error"), isPresented: $showErrorAlert) {
            Button(LocalizedStringKey("common_ok")) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func saveChanges() async {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            presentError(NSLocalizedString("postcard_validation_title_error", comment: ""))
            return
        }

        let price = Int(clampedNumericText(priceText, max: postcardMaxPriceHoney)) ?? 0
        guard price > 0 else {
            presentError(NSLocalizedString("postcard_validation_price_error", comment: ""))
            return
        }

        let stock = Int(clampedNumericText(stockText, max: postcardMaxStock)) ?? 0
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

        isSaving = true
        defer { isSaving = false }

        do {
            try await repo.updatePostcard(
                postcardId: listing.id,
                title: cleanTitle,
                priceHoney: price,
                location: PostcardLocation(
                    country: cleanCountry,
                    province: cleanProvince,
                    detail: detail.trimmingCharacters(in: .whitespacesAndNewlines)
                ),
                stock: stock,
                sellerName: listing.sellerName
            )
            dismiss()
        } catch {
            presentError((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func removePostcard() async {
        isSaving = true
        defer { isSaving = false }

        do {
            try await repo.deletePostcard(postcardId: listing.id)
            dismiss()
            onDeleted()
        } catch {
            presentError((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func presentError(_ message: String) {
        errorMessage = message
        showErrorAlert = true
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
    @State private var showErrorAlert: Bool = false
    @State private var errorAlertMessage: String = ""
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedImage: UIImage? = nil
    @State private var isUploading: Bool = false
    @State private var uploadError: String? = nil
    @State private var uploadedImageUrl: URL? = nil

    private let uploader = FirebasePostcardImageUploader()
    private let repo = FirebasePostcardRepository()
    let onSubmitted: () -> Void

    init(onSubmitted: @escaping () -> Void = {}) {
        self.onSubmitted = onSubmitted
    }

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
                        let clamped = clampedNumericText(newValue, max: postcardMaxPriceHoney)
                        if clamped != newValue { priceText = clamped }
                    }

                TextField(LocalizedStringKey("postcard_country_field"), text: $country)
                TextField(LocalizedStringKey("postcard_province_field"), text: $province)
                TextField(LocalizedStringKey("postcard_detail_field"), text: $detail)

                TextField(LocalizedStringKey("postcard_stock_field"), text: $stockText)
                    .keyboardType(.numberPad)
                    .onChange(of: stockText) { _, newValue in
                        let clamped = clampedNumericText(newValue, max: postcardMaxStock)
                        if clamped != newValue { stockText = clamped }
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
        showErrorAlert = false
        errorAlertMessage = ""

        guard !isUploading else { return }

        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }

        let price = Int(clampedNumericText(priceText, max: postcardMaxPriceHoney)) ?? 0
        guard price > 0 else {
            presentError(NSLocalizedString("postcard_validation_price_error", comment: ""))
            return
        }

        let stock = Int(clampedNumericText(stockText, max: postcardMaxStock)) ?? 0
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
                sellerId: session.authUid ?? "",
                sellerName: session.displayName.isEmpty ? "Unknown" : session.displayName,
                imageUrl: imageUrl.absoluteString
            )

            resetForm()
            onSubmitted()
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
