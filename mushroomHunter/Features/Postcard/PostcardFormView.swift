//
//  PostcardFormView.swift
//  mushroomHunter
//
//  Purpose:
//  - Provides a unified postcard form for both create and edit flows.
//
import SwiftUI
import PhotosUI

/// Maximum price accepted by the postcard form inputs.
private let postcardMaxPriceHoney: Int = AppConfig.Postcard.maxPriceHoney
/// Maximum stock accepted by the postcard form inputs.
private let postcardMaxStock: Int = AppConfig.Postcard.maxStock
/// Maximum detail length accepted by postcard forms.
private let postcardMaxDetailChars: Int = AppConfig.Postcard.maxDetailChars
/// Maximum title length accepted by postcard forms.
private let postcardMaxTitleChars: Int = AppConfig.Postcard.maxTitleChars
/// Maximum province length accepted by postcard forms.
private let postcardMaxProvinceChars: Int = AppConfig.Postcard.maxProvinceChars
/// Snapshot preview width/height used in postcard forms.
private let postcardSnapshotSize: CGFloat = AppConfig.Postcard.snapshotSize

/// Returns only numeric characters and clamps the value to `max`.
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

/// Trims text to `max` visible characters.
private func clampedText(_ value: String, max: Int) -> String {
    String(value.prefix(max))
}

/// Unified postcard form used by both register and edit entry points.
struct PostcardFormView: View {
    /// Mode that controls whether the form creates or edits a postcard.
    private enum FormMode {
        /// Form is creating a brand-new listing.
        case create
        /// Form is editing an existing listing.
        case edit
    }

    /// Current user session state used by create mode.
    @EnvironmentObject private var session: UserSessionStore
    /// Dismiss handle used by both create and edit modes.
    @Environment(\.dismiss) private var dismiss
    /// Current color scheme for themed backgrounds.
    @Environment(\.colorScheme) private var scheme

    /// Active form mode.
    private let mode: FormMode
    /// Existing listing for edit mode; nil in create mode.
    private let listing: PostcardListing?
    /// Callback when create flow succeeds.
    private let onSubmitted: () -> Void
    /// Callback when delete flow succeeds.
    private let onDeleted: () -> Void

    /// Title input state.
    @State private var title: String
    /// Price input state.
    @State private var priceText: String
    /// Country picker state.
    @State private var countryCode: String
    /// Province input state.
    @State private var province: String
    /// Detail input state.
    @State private var detail: String
    /// Stock input state.
    @State private var stockText: String

    /// Title field focus state.
    @State private var isTitleFieldFocused: Bool = false
    /// Price field focus state.
    @State private var isPriceFieldFocused: Bool = false
    /// Province field focus state.
    @State private var isProvinceFieldFocused: Bool = false
    /// Stock field focus state.
    @State private var isStockFieldFocused: Bool = false
    /// Detail field focus state.
    @State private var isDetailFieldFocused: Bool = false

    /// Selected photo picker item.
    @State private var selectedItem: PhotosPickerItem? = nil
    /// Cropped image selected for upload.
    @State private var selectedImage: UIImage? = nil

    /// Ongoing submit/upload flag.
    @State private var isSubmitting: Bool = false
    /// Error alert visibility state.
    @State private var isErrorAlertPresented: Bool = false
    /// Error alert message content.
    @State private var errorAlertMessage: String = ""
    /// Inline upload error text.
    @State private var uploadError: String? = nil
    /// Last uploaded image URL shown in create mode.
    @State private var uploadedImageURL: URL? = nil
    /// Delete confirmation dialog visibility.
    @State private var isDeleteConfirmPresented: Bool = false

    /// Repository used for create/update/delete listing operations.
    private let repo = FbPostcardRepo()
    /// Uploader used for image processing and storage upload.
    private let uploader = PostcardImageUploader()

    /// Initializes the unified form in create mode.
    init(onSubmitted: @escaping () -> Void = {}) {
        self.mode = .create
        self.listing = nil
        self.onSubmitted = onSubmitted
        self.onDeleted = {}
        _title = State(initialValue: NSLocalizedString("postcard_default_title", comment: ""))
        _priceText = State(initialValue: "10")
        _countryCode = State(initialValue: "TW")
        _province = State(initialValue: NSLocalizedString("postcard_default_province", comment: ""))
        _detail = State(initialValue: NSLocalizedString("postcard_detail_placeholder", comment: ""))
        _stockText = State(initialValue: "1")
    }

    /// Initializes the unified form in edit mode.
    init(listing: PostcardListing, onDeleted: @escaping () -> Void) {
        self.mode = .edit
        self.listing = listing
        self.onSubmitted = {}
        self.onDeleted = onDeleted
        _title = State(initialValue: listing.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? NSLocalizedString("postcard_default_title", comment: "")
            : listing.title)
        _priceText = State(initialValue: "\(max(10, listing.priceHoney))")
        _countryCode = State(initialValue: HostViewModel.countryCode(forName: listing.location.country) ?? "TW")
        _province = State(initialValue: listing.location.province.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? NSLocalizedString("postcard_default_province", comment: "")
            : listing.location.province)
        _detail = State(initialValue: listing.location.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? NSLocalizedString("postcard_detail_placeholder", comment: "")
            : listing.location.detail)
        _stockText = State(initialValue: "\(max(1, listing.stock))")
    }

    /// Indicates whether this form is currently in edit mode.
    private var isEditMode: Bool {
        mode == .edit
    }

    /// Indicates whether this form is currently in create mode.
    private var isCreateMode: Bool {
        mode == .create
    }

    /// Resolved country display name for the selected country code.
    private var countryName: String {
        HostViewModel.countryName(for: countryCode)
    }

    /// Localized submit button key for the active mode.
    private var submitButtonTitleKey: LocalizedStringKey {
        isEditMode ? LocalizedStringKey("host_save_button") : LocalizedStringKey("postcard_submit_button")
    }

    /// Builds the shared create/edit form UI.
    var body: some View {
        Form {
            snapshotSection
            infoSection
            submitSection
            if isEditMode { deleteSection }
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
        .overlay {
            if isErrorAlertPresented {
                HoneyMessageBox(
                    title: NSLocalizedString("common_error", comment: ""),
                    message: errorAlertMessage,
                    buttons: [
                        HoneyMessageBoxButton(
                            id: "postcard_form_error_ok",
                            title: NSLocalizedString("common_ok", comment: "")
                        ) {
                            isErrorAlertPresented = false
                        }
                    ]
                )
            } else if isDeleteConfirmPresented, isEditMode {
                HoneyMessageBox(
                    title: NSLocalizedString("postcard_msg_remove_confirm_title", comment: ""),
                    message: "",
                    buttons: [
                        HoneyMessageBoxButton(
                            id: "postcard_form_remove_confirm",
                            title: NSLocalizedString("postcard_remove_button", comment: ""),
                            role: .destructive
                        ) {
                            isDeleteConfirmPresented = false
                            Task { await removePostcard() }
                        },
                        HoneyMessageBoxButton(
                            id: "postcard_form_remove_cancel",
                            title: NSLocalizedString("common_cancel", comment: ""),
                            role: .cancel
                        ) {
                            isDeleteConfirmPresented = false
                        }
                    ]
                )
            }
        }
        .toolbar {
            if isEditMode {
                ToolbarItem(placement: .topBarLeading) {
                    Button(LocalizedStringKey("common_cancel")) {
                        dismiss()
                    }
                }
            }
        }
    }

    /// Snapshot picker section shared by both modes.
    private var snapshotSection: some View {
        Section(LocalizedStringKey("postcard_snapshot_section")) {
            VStack(alignment: .leading, spacing: 12) {
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    snapshotPreview
                }
                .frame(maxWidth: .infinity, alignment: .center)

                if isCreateMode && isSubmitting {
                    ProgressView(LocalizedStringKey("postcard_uploading"))
                }

                if AppTesting.useMockPostcards && isCreateMode {
                    Button(LocalizedStringKey("common_done")) {
                        Task { await submitForm() }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("postcard_form_quick_submit_button")
                }

                if let err = uploadError {
                    Text(err)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if isCreateMode, let uploadedImageURL {
                    Text("\(NSLocalizedString("postcard_uploaded_prefix", comment: "")) \(uploadedImageURL.absoluteString)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    /// Snapshot preview content shown inside the photo picker.
    private var snapshotPreview: some View {
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
            } else if let listing,
                      let urlString = listing.imageUrl,
                      let url = URL(string: urlString) {
                CachedPostcardImageView(
                    imageURL: url,
                    fallbackSystemImageName: "photo",
                    fallbackIconFont: .title2
                )
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

    /// Main listing data section shared by both modes.
    private var infoSection: some View {
        Section(LocalizedStringKey("postcard_info_section")) {
            HStack(spacing: 12) {
                Text(LocalizedStringKey("postcard_title_field"))
                Spacer()
                SelectAllTextField(
                    placeholderKey: "postcard_default_title",
                    text: $title,
                    isFirstResponder: $isTitleFieldFocused,
                    textContentType: .none,
                    autocapitalization: .words,
                    autocorrection: .yes,
                    textAlignment: .right
                )
                .frame(height: 22)
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier("postcard_form_title_field")
            }

            HStack(spacing: 12) {
                Text(LocalizedStringKey("postcard_price_field"))
                Spacer()
                SelectAllTextField(
                    placeholderKey: "postcard_default_price",
                    text: $priceText,
                    isFirstResponder: $isPriceFieldFocused,
                    keyboardType: .numberPad,
                    textContentType: .none,
                    autocapitalization: .none,
                    autocorrection: .no,
                    textAlignment: .right
                ) { newValue in
                    let clamped = clampedNumericText(newValue, max: postcardMaxPriceHoney)
                    if clamped != newValue { priceText = clamped }
                }
                .frame(height: 22)
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier("postcard_form_price_field")
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
                SelectAllTextField(
                    placeholderKey: "postcard_default_province",
                    text: $province,
                    isFirstResponder: $isProvinceFieldFocused,
                    textContentType: .addressCity,
                    autocapitalization: .words,
                    autocorrection: .yes,
                    textAlignment: .right
                )
                .frame(height: 22)
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier("postcard_form_province_field")
            }

            HStack(spacing: 12) {
                Text(LocalizedStringKey("postcard_stock_field"))
                Spacer()
                SelectAllTextField(
                    placeholderKey: "postcard_default_stock",
                    text: $stockText,
                    isFirstResponder: $isStockFieldFocused,
                    keyboardType: .numberPad,
                    textContentType: .none,
                    autocapitalization: .none,
                    autocorrection: .no,
                    textAlignment: .right
                ) { newValue in
                    let clamped = clampedNumericText(newValue, max: postcardMaxStock)
                    if clamped != newValue { stockText = clamped }
                }
                .frame(height: 22)
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier("postcard_form_stock_field")
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(LocalizedStringKey("postcard_detail_field"))
                    Spacer()
                }

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.secondarySystemBackground))

                    SelectAllTextEditor(
                        text: $detail,
                        isFirstResponder: $isDetailFieldFocused
                    )
                        .padding(.horizontal, 2)
                        .frame(minHeight: 110)
                        .accessibilityIdentifier("postcard_form_detail_editor")
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
    }

    /// Submit action section shared by both modes.
    private var submitSection: some View {
        Section {
            if isCreateMode {
                Button(submitButtonTitleKey) {
                    Task { await submitForm() }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .buttonStyle(.borderedProminent)
                .disabled(isSubmitting || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("postcard_form_submit_button")
            } else {
                Button(submitButtonTitleKey) {
                    Task { await submitForm() }
                }
                .disabled(isSubmitting)
                .accessibilityIdentifier("postcard_form_submit_button")
            }
        }
    }

    /// Edit-only delete action section.
    private var deleteSection: some View {
        Section {
            Button(LocalizedStringKey("postcard_remove_button"), role: .destructive) {
                isDeleteConfirmPresented = true
            }
            .disabled(isSubmitting)
        }
    }

    /// Loads and crops the selected photo picker image.
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

    /// Runs create or edit submit flow based on current mode.
    private func submitForm() async {
        if isEditMode {
            await submitEdit()
        } else {
            await submitCreate()
        }
    }

    /// Validates inputs, uploads image, and creates a new postcard listing.
    private func submitCreate() async {
        uploadError = nil
        isErrorAlertPresented = false
        errorAlertMessage = ""

        guard !isSubmitting else { return }

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

        if AppTesting.useMockPostcards {
            onSubmitted()
            return
        }

        guard let image = selectedImage else {
            presentError(NSLocalizedString("postcard_upload_select_error", comment: ""))
            return
        }

        let data: Data
        let thumbnailData: Data
        do {
            data = try uploader.prepareUploadJPEGData(from: image)
            thumbnailData = try uploader.prepareThumbnailJPEGData(from: image)
        } catch {
            presentError((error as? LocalizedError)?.errorDescription ?? NSLocalizedString("postcard_upload_process_error", comment: ""))
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        var imageURL: URL? = nil
        var thumbnailImageURL: URL? = nil
        do {
            let uploaded = try await uploader.uploadPostcardImage(data: data, ownerId: session.authUid)
            let uploadedThumbnail = try await uploader.uploadPostcardThumbnail(data: thumbnailData, ownerId: session.authUid)
            imageURL = uploaded
            thumbnailImageURL = uploadedThumbnail
            uploadedImageURL = uploaded

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
                sellerFriendCode: session.friendCode,
                sellerFcmToken: session.fcmToken ?? "",
                imageUrl: uploaded.absoluteString,
                thumbnailUrl: uploadedThumbnail.absoluteString
            )

            resetCreateForm()
            onSubmitted()
        } catch {
            if let imageURL {
                await uploader.deleteUploadedImage(at: imageURL)
            }
            if let thumbnailImageURL {
                await uploader.deleteUploadedImage(at: thumbnailImageURL)
            }
            presentError((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// Validates inputs and updates the existing postcard listing.
    private func submitEdit() async {
        guard let listing else { return }
        guard !isSubmitting else { return }

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

        isSubmitting = true
        defer { isSubmitting = false }

        var uploadedImageURLToRollback: URL? = nil
        var uploadedThumbnailURLToRollback: URL? = nil
        do {
            var newImageUrl: String? = nil
            var newThumbnailUrl: String? = nil
            if let image = selectedImage {
                let data: Data
                let thumbnailData: Data
                do {
                    data = try uploader.prepareUploadJPEGData(from: image)
                    thumbnailData = try uploader.prepareThumbnailJPEGData(from: image)
                } catch {
                    presentError((error as? LocalizedError)?.errorDescription ?? NSLocalizedString("postcard_upload_process_error", comment: ""))
                    return
                }
                let uploaded = try await uploader.uploadPostcardImage(data: data, ownerId: listing.sellerId)
                let uploadedThumbnail = try await uploader.uploadPostcardThumbnail(data: thumbnailData, ownerId: listing.sellerId)
                uploadedImageURLToRollback = uploaded
                uploadedThumbnailURLToRollback = uploadedThumbnail
                newImageUrl = uploaded.absoluteString
                newThumbnailUrl = uploadedThumbnail.absoluteString
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
                sellerFriendCode: session.friendCode,
                sellerFcmToken: session.fcmToken ?? "",
                imageUrl: newImageUrl,
                thumbnailUrl: newThumbnailUrl
            )

            if newImageUrl != nil, let oldImageUrl = listing.imageUrl, let oldImage = URL(string: oldImageUrl) {
                await uploader.deleteUploadedImage(at: oldImage)
            }
            if newThumbnailUrl != nil,
               let oldThumbnailUrl = listing.thumbnailUrl,
               let oldThumbnail = URL(string: oldThumbnailUrl) {
                await uploader.deleteUploadedImage(at: oldThumbnail)
            }
            dismiss()
        } catch {
            if let uploadedImageURLToRollback {
                await uploader.deleteUploadedImage(at: uploadedImageURLToRollback)
            }
            if let uploadedThumbnailURLToRollback {
                await uploader.deleteUploadedImage(at: uploadedThumbnailURLToRollback)
            }
            presentError((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// Deletes the listing in edit mode.
    private func removePostcard() async {
        guard let listing else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await repo.deletePostcard(postcardId: listing.id)
            dismiss()
            onDeleted()
        } catch {
            presentError((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// Presents the given error text in both inline and alert channels.
    private func presentError(_ message: String) {
        uploadError = message
        errorAlertMessage = message
        isErrorAlertPresented = true
    }

    /// Resets create form fields after successful postcard creation.
    private func resetCreateForm() {
        title = NSLocalizedString("postcard_default_title", comment: "")
        priceText = "10"
        countryCode = "TW"
        province = NSLocalizedString("postcard_default_province", comment: "")
        detail = NSLocalizedString("postcard_detail_placeholder", comment: "")
        stockText = "1"
        selectedItem = nil
        selectedImage = nil
        uploadedImageURL = nil
    }
}
