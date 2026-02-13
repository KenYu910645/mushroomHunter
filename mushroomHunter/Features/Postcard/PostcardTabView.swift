import SwiftUI
import PhotosUI

private let postcardMaxPriceHoney: Int = 1_000_000_000
private let postcardMaxStock: Int = 1_000_000
private let postcardMaxDetailChars: Int = 100
private let postcardMaxTitleChars: Int = 20
private let postcardMaxProvinceChars: Int = 20
private let postcardSnapshotSize: CGFloat = 180

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

private func clampedText(_ value: String, max: Int) -> String {
    String(value.prefix(max))
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
    private let cardColumnSpacing: CGFloat = 8
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
                            PostcardCardView(listing: listing)
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
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
        [
            GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: cardColumnSpacing, alignment: .top),
            GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: cardColumnSpacing, alignment: .top)
        ]
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
    @Environment(\.colorScheme) private var scheme

    private let imageAspectRatio: CGFloat = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
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
                    .aspectRatio(imageAspectRatio, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    Image(systemName: "photo")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)

            Text(listing.title)
                .font(.headline)
                .lineLimit(1)

            HStack(spacing: 6) {
                Image(systemName: "mappin.and.ellipse")
                Text(listing.location.shortLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                HStack(spacing: 4) {
                    Text("\(listing.priceHoney)")
                        .font(.subheadline)
                    Image("HoneyIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                }
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
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
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
    @State private var sellerFriendCode: String = ""
    @State private var showCopyToast: Bool = false
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

                    HStack(spacing: 6) {
                        Image(systemName: "mappin.and.ellipse")
                        Text(currentListing.location.shortLabel)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        Text(String(format: NSLocalizedString("postcard_seller_format", comment: ""), currentListing.sellerName))
                        Text(formattedFriendCode(sellerFriendCode))
                            .foregroundStyle(.secondary)
                        Button {
                            copyFriendCode(sellerFriendCode)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(LocalizedStringKey("room_copy_host_code_accessibility"))
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    HStack {
                        HStack(spacing: 4) {
                            Text("\(currentListing.priceHoney)")
                                .fontWeight(.semibold)
                                .monospacedDigit()
                            Image("HoneyIcon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 18, height: 18)
                        }
                        Spacer()
                        Text(String(format: NSLocalizedString("postcard_stock_format", comment: ""), currentListing.stock))
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }

                    if !currentListing.location.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(currentListing.location.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
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
        .overlay(alignment: .top) {
            if showCopyToast {
                Text(LocalizedStringKey("common_copied"))
                    .font(.footnote)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private func refreshListing() async {
        do {
            if let refreshed = try await repo.fetchPostcard(postcardId: currentListing.id) {
                currentListing = refreshed
                sellerFriendCode = try await repo.fetchUserFriendCode(userId: refreshed.sellerId)
            } else {
                dismiss()
            }
        } catch {
            // Keep existing content if network refresh fails.
        }
    }

    private func formattedFriendCode(_ raw: String) -> String {
        let digits = raw.filter { $0.isNumber }
        guard !digits.isEmpty else { return "-" }
        if digits.count <= 4 { return digits }
        if digits.count <= 8 {
            let first = digits.prefix(4)
            let second = digits.suffix(max(0, digits.count - 4))
            return "\(first) \(second)"
        }
        let first = digits.prefix(4)
        let second = digits.dropFirst(4).prefix(4)
        let third = digits.dropFirst(8).prefix(4)
        return "\(first) \(second) \(third)"
    }

    private func copyFriendCode(_ raw: String) {
        let digits = raw.filter { $0.isNumber }
        guard !digits.isEmpty else { return }
        UIPasteboard.general.string = digits
        withAnimation(.easeInOut(duration: 0.2)) {
            showCopyToast = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showCopyToast = false
                }
            }
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
    @Environment(\.colorScheme) private var scheme
    @State private var title: String
    @State private var priceText: String
    @State private var countryCode: String
    @State private var province: String
    @State private var detail: String
    @State private var stockText: String
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedImage: UIImage? = nil
    @State private var isSaving: Bool = false
    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""
    @State private var showDeleteConfirm: Bool = false
    @State private var uploadError: String? = nil
    private let repo = FirebasePostcardRepository()
    private let uploader = FirebasePostcardImageUploader()

    init(listing: PostcardListing, onDeleted: @escaping () -> Void) {
        self.listing = listing
        self.onDeleted = onDeleted
        _title = State(initialValue: listing.title)
        _priceText = State(initialValue: "\(listing.priceHoney)")
        _countryCode = State(initialValue: HostViewModel.countryCode(forName: listing.location.country) ?? "TW")
        _province = State(initialValue: listing.location.province)
        _detail = State(initialValue: listing.location.detail)
        _stockText = State(initialValue: "\(listing.stock)")
    }

    private var countryName: String {
        HostViewModel.countryName(for: countryCode)
    }

    var body: some View {
        Form {
            Section(LocalizedStringKey("postcard_snapshot_section")) {
                VStack(alignment: .leading, spacing: 12) {
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.secondarySystemBackground))
                                .frame(width: postcardSnapshotSize, height: postcardSnapshotSize)

                            if let uiImage = selectedImage {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: postcardSnapshotSize, height: postcardSnapshotSize)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            } else if let urlString = listing.imageUrl,
                                      let url = URL(string: urlString) {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    case .failure:
                                        Image(systemName: "photo")
                                            .font(.title2)
                                            .foregroundStyle(.secondary)
                                    case .empty:
                                        ProgressView()
                                    @unknown default:
                                        Image(systemName: "photo")
                                            .font(.title2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(width: postcardSnapshotSize, height: postcardSnapshotSize)
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
                    }
                    .frame(maxWidth: .infinity, alignment: .center)

                    if let err = uploadError {
                        Text(err)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }

            Section(LocalizedStringKey("postcard_info_section")) {
                HStack(spacing: 12) {
                    Text(LocalizedStringKey("postcard_title_field"))
                    Spacer()
                    TextField("Postcard", text: $title)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.words)
                }

                HStack(spacing: 12) {
                    Text(LocalizedStringKey("postcard_price_field"))
                    Spacer()
                    TextField("10", text: $priceText)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                        .onChange(of: priceText) { _, newValue in
                            let clamped = clampedNumericText(newValue, max: postcardMaxPriceHoney)
                            if clamped != newValue { priceText = clamped }
                        }
                }

                HStack(spacing: 12) {
                    Text(LocalizedStringKey("postcard_country_field"))
                    Spacer()
                    Picker("", selection: $countryCode) {
                        ForEach(HostViewModel.availableCountries, id: \.code) { item in
                            Text(item.name).tag(item.code)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                HStack(spacing: 12) {
                    Text(LocalizedStringKey("postcard_province_field"))
                    Spacer()
                    TextField("somewhere", text: $province)
                        .multilineTextAlignment(.trailing)
                }

                HStack(spacing: 12) {
                    Text(LocalizedStringKey("postcard_stock_field"))
                    Spacer()
                    TextField("1", text: $stockText)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                        .onChange(of: stockText) { _, newValue in
                            let clamped = clampedNumericText(newValue, max: postcardMaxStock)
                            if clamped != newValue { stockText = clamped }
                        }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(LocalizedStringKey("postcard_detail_field"))
                        Spacer()
                    }

                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.secondarySystemBackground))

                        if detail.isEmpty {
                            Text("I found this postcard in the forest...")
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                                .padding(.leading, 6)
                        }

                        TextEditor(text: $detail)
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, 2)
                            .frame(minHeight: 110)
                    }
                    .frame(minHeight: 110)

                    HStack {
                        Spacer()
                        Text("\(detail.count)/\(postcardMaxDetailChars)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button(LocalizedStringKey("host_save_button")) {
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
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundGradient(for: scheme))
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
        .onChange(of: selectedItem) { _, newValue in
            guard let newValue else { return }
            Task { await loadSelectedPhoto(newValue) }
        }
        .onChange(of: detail) { _, newValue in
            if newValue.count > postcardMaxDetailChars {
                detail = String(newValue.prefix(postcardMaxDetailChars))
            }
        }
        .onChange(of: title) { _, newValue in
            let clamped = clampedText(newValue, max: postcardMaxTitleChars)
            if clamped != newValue { title = clamped }
        }
        .onChange(of: province) { _, newValue in
            let clamped = clampedText(newValue, max: postcardMaxProvinceChars)
            if clamped != newValue { province = clamped }
        }
    }

    private func loadSelectedPhoto(_ item: PhotosPickerItem) async {
        uploadError = nil
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                selectedImage = try uploader.cropSnapshotImage(image)
            } else {
                uploadError = NSLocalizedString("postcard_upload_load_error", comment: "")
            }
        } catch {
            selectedImage = nil
            uploadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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

        let cleanCountry = countryName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanProvince = province.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanCountry.isEmpty, !cleanProvince.isEmpty else {
            presentError(NSLocalizedString("postcard_validation_location_error", comment: ""))
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            var newImageUrl: String? = nil
            if let image = selectedImage {
                let data: Data
                do {
                    data = try uploader.prepareUploadJPEGData(from: image)
                } catch {
                    presentError((error as? LocalizedError)?.errorDescription ?? NSLocalizedString("postcard_upload_process_error", comment: ""))
                    return
                }
                let uploaded = try await uploader.uploadPostcardImage(data: data, ownerId: listing.sellerId)
                newImageUrl = uploaded.absoluteString
            }

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
                sellerName: listing.sellerName,
                imageUrl: newImageUrl
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
    @State private var countryCode: String = "TW"
    @State private var province: String = ""
    @State private var detail: String = ""
    @State private var stockText: String = ""
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

    private var countryName: String {
        HostViewModel.countryName(for: countryCode)
    }

    var body: some View {
        Form {
            Section(LocalizedStringKey("postcard_snapshot_section")) {
                VStack(alignment: .leading, spacing: 12) {
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.secondarySystemBackground))
                                .frame(width: postcardSnapshotSize, height: postcardSnapshotSize)

                            if let uiImage = selectedImage {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: postcardSnapshotSize, height: postcardSnapshotSize)
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
                    }
                    .frame(maxWidth: .infinity, alignment: .center)

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
                HStack(spacing: 12) {
                    Text(LocalizedStringKey("postcard_title_field"))
                    Spacer()
                    TextField("Postcard", text: $title)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.words)
                }

                HStack(spacing: 12) {
                    Text(LocalizedStringKey("postcard_price_field"))
                    Spacer()
                    TextField("10", text: $priceText)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                        .onChange(of: priceText) { _, newValue in
                            let clamped = clampedNumericText(newValue, max: postcardMaxPriceHoney)
                            if clamped != newValue { priceText = clamped }
                        }
                }

                HStack(spacing: 12) {
                    Text(LocalizedStringKey("postcard_country_field"))
                    Spacer()
                    Picker("", selection: $countryCode) {
                        ForEach(HostViewModel.availableCountries, id: \.code) { item in
                            Text(item.name).tag(item.code)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                HStack(spacing: 12) {
                    Text(LocalizedStringKey("postcard_province_field"))
                    Spacer()
                    TextField("somewhere", text: $province)
                        .multilineTextAlignment(.trailing)
                }

                HStack(spacing: 12) {
                    Text(LocalizedStringKey("postcard_stock_field"))
                    Spacer()
                    TextField("1", text: $stockText)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                        .onChange(of: stockText) { _, newValue in
                            let clamped = clampedNumericText(newValue, max: postcardMaxStock)
                            if clamped != newValue { stockText = clamped }
                        }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(LocalizedStringKey("postcard_detail_field"))
                        Spacer()
                    }

                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.secondarySystemBackground))

                        if detail.isEmpty {
                            Text("I found this postcard in the forest...")
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                                .padding(.leading, 6)
                        }

                        TextEditor(text: $detail)
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, 2)
                            .frame(minHeight: 110)
                    }
                    .frame(minHeight: 110)

                    HStack {
                        Spacer()
                        Text("\(detail.count)/\(postcardMaxDetailChars)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
        .onChange(of: detail) { _, newValue in
            if newValue.count > postcardMaxDetailChars {
                detail = String(newValue.prefix(postcardMaxDetailChars))
            }
        }
        .onChange(of: title) { _, newValue in
            let clamped = clampedText(newValue, max: postcardMaxTitleChars)
            if clamped != newValue { title = clamped }
        }
        .onChange(of: province) { _, newValue in
            let clamped = clampedText(newValue, max: postcardMaxProvinceChars)
            if clamped != newValue { province = clamped }
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
                selectedImage = try uploader.cropSnapshotImage(image)
            } else {
                uploadError = NSLocalizedString("postcard_upload_load_error", comment: "")
            }
        } catch {
            selectedImage = nil
            uploadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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

        let stockInput = clampedNumericText(stockText, max: postcardMaxStock)
        let stock = Int(stockInput.isEmpty ? "1" : stockInput) ?? 0
        guard stock > 0 else {
            presentError(NSLocalizedString("postcard_validation_stock_error", comment: ""))
            return
        }

        let cleanCountry = countryName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanProvince = province.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanCountry.isEmpty, !cleanProvince.isEmpty else {
            presentError(NSLocalizedString("postcard_validation_location_error", comment: ""))
            return
        }

        guard let image = selectedImage else {
            presentError(NSLocalizedString("postcard_upload_select_error", comment: ""))
            return
        }
        let data: Data
        do {
            data = try uploader.prepareUploadJPEGData(from: image)
        } catch {
            presentError((error as? LocalizedError)?.errorDescription ?? NSLocalizedString("postcard_upload_process_error", comment: ""))
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
        countryCode = "TW"
        province = ""
        detail = ""
        stockText = ""
        selectedItem = nil
        selectedImage = nil
        uploadedImageUrl = nil
    }
}

// MARK: - Preview

#Preview {
    PostcardTabView()
}
