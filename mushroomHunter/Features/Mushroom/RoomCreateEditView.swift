//
//  RoomCreateEditView.swift
//  mushroomHunter
//
//  Purpose:
//  - Implements the room host/create-edit screen in Mushroom feature.
//
//  Defined in this file:
//  - HostViewModel and RoomCreateEditView create/edit form logic and validation.
//
import SwiftUI
import Combine
import UIKit

// MARK: - ViewModel
import Foundation

@MainActor
final class HostViewModel: ObservableObject {
    enum Mode: Equatable {
        case create
        case edit(roomId: String)
    }

    struct CountryItem: Hashable {
        let code: String
        let name: String
    }

    // Dependencies
    private unowned let session: UserSessionStore
    private let repo: FbRoomFormRepo

    let mode: Mode

    // Inputs
    @Published var hostName: String = NSLocalizedString("host_room_default_name", comment: "") // User-entered room title shown in browse/detail screens.
    @Published var countryCode: String = Locale.current.region?.identifier ?? AppConfig.Mushroom.defaultHostCountryCode // Selected ISO country code for room location.
    @Published var city: String = NSLocalizedString("host_city_default", comment: "") // User-entered city/area portion of room location.
    @Published var otherMessage: String = NSLocalizedString("host_default_description", comment: "") // Optional room description displayed to joiners.
    @Published var fixedRaidCost: Int = HostViewModel.resolvedInitialFixedRaidCost() // Minimum honey deposit required for joining.
    // UI State
    @Published var showSuccessAlert: Bool = false // Presents success alert after create/update request finishes.
    @Published var successRoomId: String? = nil // Stores created/updated room id for downstream actions.
    @Published var errorMessage: String? = nil // Inline error text shown above submit action.
    @Published var isSubmitting: Bool = false // Locks inputs and shows progress during submit request.
    @Published var showLimitAlert: Bool = false // Presents host-limit alert when backend rejects room count.
    @Published var limitAlertMessage: String = "" // Localized message content displayed in limit alert.
    @Published var showNameError: Bool = false // Marks room name field as required when empty.
    @Published var showAreaError: Bool = false // Marks city field as required when empty.
    @Published var showRequiredAlert: Bool = false // Presents aggregate required-fields alert on invalid submit.
    // Limits
    static let hostNameMaxChars = 30
    static let otherMaxChars = 100
    static let availableCountries: [CountryItem] = {
        let locale = Locale.current
        let items = Locale.isoRegionCodes.map { code in
            let name = locale.localizedString(forRegionCode: code) ?? code
            return CountryItem(code: code, name: name)
        }
        return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }()

    init(session: UserSessionStore, repo: FbRoomFormRepo = FbRoomFormRepo()) { // Initializes this type.
        self.session = session
        self.repo = repo
        self.mode = .create
        self.fixedRaidCost = Self.resolvedInitialFixedRaidCost()
    }

    init(session: UserSessionStore, room: RoomDetail, repo: FbRoomFormRepo = FbRoomFormRepo()) { // Initializes this type.
        self.session = session
        self.repo = repo
        self.mode = .edit(roomId: room.id)
        seed(from: room)
    }

    var otherCharCount: Int { Self.charCount(otherMessage) }

    var isEditMode: Bool {
        if case .edit = mode { return true }
        return false
    }

    var navigationTitle: String {
        isEditMode
            ? NSLocalizedString("host_edit_title", comment: "")
            : NSLocalizedString("host_create_title", comment: "")
    }

    var primaryActionTitle: String {
        isEditMode
            ? NSLocalizedString("host_save_button", comment: "")
            : NSLocalizedString("host_create_button", comment: "")
    }

    var successAlertTitle: String {
        isEditMode
            ? NSLocalizedString("host_success_updated_title", comment: "")
            : NSLocalizedString("host_success_created_title", comment: "")
    }

    var successAlertMessage: String {
        isEditMode
            ? NSLocalizedString("host_success_updated_message", comment: "")
            : NSLocalizedString("host_success_created_message", comment: "")
    }

    var canSubmit: Bool {
        let nameOK = !hostName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let locOK = !countryDisplayName.isEmpty
            && !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let msgOK = otherCharCount <= Self.otherMaxChars
        return nameOK && locOK && msgOK && !isSubmitting
    }

    func enforceLimits() { // Handles enforceLimits flow.
        if hostName.count > Self.hostNameMaxChars {
            hostName = String(hostName.prefix(Self.hostNameMaxChars))
        }
        if otherCharCount > Self.otherMaxChars {
            otherMessage = Self.trimToChars(otherMessage, maxChars: Self.otherMaxChars)
        }
    }

    func submit() async { // Handles submit flow.
        guard validateRequired() else {
            showRequiredAlert = true
            return
        }
        guard otherCharCount <= Self.otherMaxChars else { return }

        isSubmitting = true
        errorMessage = nil
        successRoomId = nil
        showSuccessAlert = false

        print("🚀 submit(): start creating host room")

        defer { isSubmitting = false }

        if AppTesting.useMockRooms {
            switch mode {
            case .create:
                successRoomId = AppTesting.fixtureRoomId
            case .edit(let roomId):
                successRoomId = roomId
            }
            showSuccessAlert = true
            return
        }

        do {
            let req = FsRoomFormRequest(
            title: hostName,
            location: locationString,
            description: otherMessage,
            hostFriendCode: session.friendCode,
            fixedRaidCost: fixedRaidCost
        )

            switch mode {
            case .create:
                let roomId = try await repo.createRoom(
                    req: req,
                    hostDisplayName: session.displayName,
                    hostStars: session.stars
                )

                print("✅ submit(): created room id =", roomId)
                successRoomId = roomId

            case .edit(let roomId):
                try await repo.updateRoom(roomId: roomId, req: req)
                print("✅ submit(): updated room id =", roomId)
                successRoomId = roomId
            }

            showSuccessAlert = true

        } catch {
            print("❌ submit(): error =", error)
            if let limitError = error as? RoomFormError {
                limitAlertMessage = limitError.errorDescription ?? ""
                showLimitAlert = true
            } else {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func reset() { // Handles reset flow.
        hostName = NSLocalizedString("host_room_default_name", comment: "")
        countryCode = Locale.current.region?.identifier ?? AppConfig.Mushroom.defaultHostCountryCode
        city = NSLocalizedString("host_city_default", comment: "")
        otherMessage = NSLocalizedString("host_default_description", comment: "")
        fixedRaidCost = Self.resolvedInitialFixedRaidCost()
        errorMessage = nil
        successRoomId = nil
        showSuccessAlert = false
        showNameError = false
        showAreaError = false
    }

    private func seed(from room: RoomDetail) {
        hostName = room.title
        if let parsed = parseLocation(room.location) {
            countryCode = parsed.countryCode
            city = parsed.city
        } else {
            countryCode = Locale.current.region?.identifier ?? AppConfig.Mushroom.defaultHostCountryCode
            city = room.location
        }
        let trimmedDescription = room.description.trimmingCharacters(in: .whitespacesAndNewlines)
        otherMessage = trimmedDescription.isEmpty
            ? NSLocalizedString("host_default_description", comment: "")
            : room.description
        fixedRaidCost = room.fixedRaidCost
    }

    // MARK: Word utils
    static func charCount(_ text: String) -> Int {
        text.unicodeScalars.count
    }

    static func trimToChars(_ text: String, maxChars: Int) -> String {
        if text.count <= maxChars { return text }
        return String(text.prefix(maxChars))
    }

    /// Resolves create-form fixed raid payment default based on owner config.
    static func resolvedInitialFixedRaidCost() -> Int {
        if AppConfig.Mushroom.isRaidPaymentAdjustmentEnabled {
            return AppConfig.Mushroom.defaultFixedRaidCost
        }
        return AppConfig.Mushroom.disabledRaidPaymentHoney
    }

    // MARK: Location helpers
    var countryDisplayName: String {
        HostViewModel.countryName(for: countryCode)
    }

    var locationString: String {
        let cityTrim = city.trimmingCharacters(in: .whitespacesAndNewlines)
        if cityTrim.isEmpty { return countryDisplayName }
        return "\(countryDisplayName), \(cityTrim)"
    }

    private func parseLocation(_ raw: String) -> (countryCode: String, city: String)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let separators = [", ", " - ", " – ", " — "]
        for sep in separators {
            let parts = trimmed.components(separatedBy: sep)
            if parts.count >= 2 {
                let countryName = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let cityPart = parts.dropFirst().joined(separator: sep).trimmingCharacters(in: .whitespacesAndNewlines)
                if let code = HostViewModel.countryCode(forName: countryName) {
                    return (code, cityPart.isEmpty ? NSLocalizedString("host_city_default", comment: "") : cityPart)
                }
            }
        }

        if let code = HostViewModel.countryCode(forName: trimmed) {
            return (code, NSLocalizedString("host_city_default", comment: ""))
        }

        return nil
    }

    static func countryName(for code: String) -> String {
        Locale.current.localizedString(forRegionCode: code) ?? code
    }

    static func countryCode(forName name: String) -> String? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        return CountryLocalization.resolvedCountryCode(forStoredCountryValue: trimmedName)
    }

    // MARK: Validation
    @discardableResult
    func validateRequired() -> Bool { // Handles validateRequired flow.
        let nameOK = !hostName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let areaOK = !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        showNameError = !nameOK
        showAreaError = !areaOK
        return nameOK && areaOK
    }
}

// MARK: - View

struct RoomCreateEditView: View {
    /// Text token replaced by inline honey icon in form labels.
    private let honeyIconToken: String = "{honey_icon}"
    /// Inline honey icon size used in tokenized host-form labels.
    private let honeyInlineIconSize: CGFloat = 16
    @Environment(\.dismiss) private var dismiss // Dismiss action for closing the modal form.
    @EnvironmentObject private var session: UserSessionStore // Shared user session injected from app root.
    @Environment(\.colorScheme) private var scheme // Color scheme used to pick themed background gradient.
    @StateObject private var vm: HostViewModel // View model that owns form values and submit state.
    private let onCloseRoom: (() -> Void)?
    @State private var isNameFirstResponder: Bool = false // Focus flag for room-name input.
    @State private var isAreaFirstResponder: Bool = false // Focus flag for city input.
    @State private var isDescriptionFirstResponder: Bool = false // Focus flag for description editor.
    init(vm: HostViewModel, onCloseRoom: (() -> Void)? = nil) { // Initializes this type.
        _vm = StateObject(wrappedValue: vm)
        self.onCloseRoom = onCloseRoom
    }

    var body: some View {
        NavigationStack {
            Form {
                // Host name
                Section {
                    SmartTextField(
                        placeholderKey: "host_room_name_placeholder",
                        text: $vm.hostName,
                        isFirstResponder: $isNameFirstResponder,
                        keyboardType: .default,
                        textContentType: .name,
                        autocapitalization: .words,
                        autocorrection: .yes,
                        onChange: { _ in
                            vm.enforceLimits()
                            if vm.showNameError {
                                vm.showNameError = vm.hostName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            }
                        }
                    )
                    .frame(minHeight: 22)
                    .accessibilityIdentifier("host_name_field")
                    .onTapGesture {
                        isNameFirstResponder = true
                    }

                    if vm.showNameError {
                        Text(LocalizedStringKey("host_field_required"))
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text(LocalizedStringKey("host_room_name_header"))
                }

                // Location
                Section {
                    Picker(LocalizedStringKey("host_country_label"), selection: $vm.countryCode) {
                        ForEach(HostViewModel.availableCountries, id: \.code) { item in
                            Text(item.name).tag(item.code)
                        }
                    }

                    HStack(spacing: 12) {
                        Text(LocalizedStringKey("host_area_label"))

                        Spacer()

                        SmartTextField(
                            placeholderKey: "host_city_placeholder",
                            text: $vm.city,
                            isFirstResponder: $isAreaFirstResponder,
                            keyboardType: .default,
                            textContentType: .location,
                            autocapitalization: .words,
                            autocorrection: .yes,
                            textAlignment: .right,
                            onChange: { _ in
                                if vm.showAreaError {
                                    vm.showAreaError = vm.city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                }
                            }
                        )
                        .frame(minHeight: 22)
                        .accessibilityIdentifier("host_city_field")
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .onTapGesture {
                            isAreaFirstResponder = true
                        }
                    }

                    if vm.showAreaError {
                        Text(LocalizedStringKey("host_field_required"))
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text(LocalizedStringKey("host_location_header"))
                }

                // Other message (100 chars max)
                Section {
                    SmartTextEditor(
                        text: $vm.otherMessage,
                        isFirstResponder: $isDescriptionFirstResponder,
                        autocapitalization: .sentences,
                        autocorrection: .yes
                    )
                        .padding(.horizontal, 2)
                        .frame(minHeight: 140)
                        .onChange(of: vm.otherMessage) { _, _ in vm.enforceLimits() }
                        .accessibilityIdentifier("host_message_editor")

                    HStack {
                        Text(LocalizedStringKey("host_words_label"))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(vm.otherCharCount)/\(HostViewModel.otherMaxChars)")
                            .foregroundColor(vm.otherCharCount <= HostViewModel.otherMaxChars ? .secondary : .red)
                            .monospacedDigit()
                    }
                } header: {
                    Text(LocalizedStringKey("host_description_header"))
                }

                if AppConfig.Mushroom.isRaidPaymentAdjustmentEnabled {
                    Section {
                        Stepper(
                            value: $vm.fixedRaidCost,
                            in: AppConfig.Mushroom.minFixedRaidCost...AppConfig.Mushroom.enabledRaidPaymentMaxHoney,
                            step: 1
                        ) {
                            HStack {
                                tokenizedHostFixedRaidCostLabel
                                Spacer()
                                Text("\(vm.fixedRaidCost)")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text(LocalizedStringKey("host_fixed_raid_cost_header"))
                    } footer: {
                        Text(LocalizedStringKey("host_fixed_raid_cost_footer"))
                    }
                }

                // Error
                if let err = vm.errorMessage {
                    Section {
                        Text(err)
                            .foregroundStyle(.red)
                    }
                }

                // Create button
                Section {
                    Button {
                        dismissKeyboard()
                        Task { await vm.submit() }
                    } label: {
                        HStack {
                            Spacer()
                            if vm.isSubmitting {
                                ProgressView()
                            } else {
                                Text(vm.primaryActionTitle).font(.headline)
                            }
                            Spacer()
                        }
                    }
                    .disabled(vm.isSubmitting)
                    .accessibilityIdentifier("host_submit_button")
                }

                if vm.isEditMode {
                    Section {
                        Button(role: .destructive) {
                            dismiss()
                            onCloseRoom?()
                        } label: {
                            HStack {
                                Spacer()
                                Text(LocalizedStringKey("host_close_room_button"))
                                    .font(.headline)
                                Spacer()
                            }
                        }
                    } footer: {
                        Text(LocalizedStringKey("host_close_room_footer"))
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .background(
                KeyboardDismissBridge {
                    dismissKeyboard()
                }
            )
            .navigationTitle(vm.navigationTitle)
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundGradient(for: scheme))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                    }
                    .accessibilityLabel(LocalizedStringKey("common_close"))
                    .accessibilityIdentifier("host_close_button")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(LocalizedStringKey("common_done")) {
                        dismissKeyboard()
                    }
                }
            }
            .overlay {
                if vm.showSuccessAlert {
                    MessageBox(
                        title: vm.successAlertTitle,
                        message: vm.successAlertMessage,
                        buttons: [
                            MessageBoxButton(
                                id: "room_form_success_ok",
                                title: NSLocalizedString("common_ok", comment: "")
                            ) {
                                vm.showSuccessAlert = false
                                dismiss()
                            }
                        ]
                    )
                } else if vm.showLimitAlert {
                    MessageBox(
                        title: NSLocalizedString("host_limit_title", comment: ""),
                        message: vm.limitAlertMessage,
                        buttons: [
                            MessageBoxButton(
                                id: "room_form_limit_ok",
                                title: NSLocalizedString("common_ok", comment: "")
                            ) {
                                vm.showLimitAlert = false
                            }
                        ]
                    )
                } else if vm.showRequiredAlert {
                    MessageBox(
                        title: NSLocalizedString("host_required_title", comment: ""),
                        message: NSLocalizedString("host_required_message", comment: ""),
                        buttons: [
                            MessageBoxButton(
                                id: "room_form_required_ok",
                                title: NSLocalizedString("common_ok", comment: "")
                            ) {
                                vm.showRequiredAlert = false
                            }
                        ]
                    )
                }
            }
        }
    }

    /// Clears all field focus flags and asks UIKit to end editing in the active window.
    private func dismissKeyboard() {
        isNameFirstResponder = false
        isAreaFirstResponder = false
        isDescriptionFirstResponder = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// Localized host fixed-raid-cost label where `{honey_icon}` tokens render as inline icon.
    private var tokenizedHostFixedRaidCostLabel: Text {
        let rawLabel = NSLocalizedString("host_fixed_raid_cost_label", comment: "")
        return tokenizedHoneyLabel(rawLabel)
    }

    /// Builds one inline text run that replaces `{honey_icon}` with `HoneyIcon`.
    /// - Parameter rawText: Source localized text that may contain icon tokens.
    /// - Returns: Tokenized SwiftUI `Text` ready for inline rendering.
    private func tokenizedHoneyLabel(_ rawText: String) -> Text {
        let segments = rawText.components(separatedBy: honeyIconToken)
        var combinedText = Text("")

        for (index, segment) in segments.enumerated() {
            combinedText = combinedText + Text(segment)
            if index < segments.count - 1 {
                combinedText = combinedText + Text(honeyInlineImage())
            }
        }

        return combinedText
    }

    /// Generates a pre-scaled honey icon image for inline tokenized text rendering.
    /// - Returns: Resized `HoneyIcon` image with fallback symbol when asset is missing.
    private func honeyInlineImage() -> Image {
        guard let sourceImage = UIImage(named: "HoneyIcon") else {
            return Image(systemName: "drop.fill")
        }

        let iconRenderSize = CGSize(width: honeyInlineIconSize, height: honeyInlineIconSize)
        let renderer = UIGraphicsImageRenderer(size: iconRenderSize)
        let resizedImage = renderer.image { _ in
            sourceImage.draw(in: CGRect(origin: .zero, size: iconRenderSize))
        }
        return Image(uiImage: resizedImage)
    }
}
