import SwiftUI
import Combine

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
    private unowned let session: SessionStore
    private let repo: FirebaseHostRepository

    let mode: Mode

    // Inputs
    @Published var hostName: String = NSLocalizedString("host_room_default_name", comment: "")
    @Published var color: MushroomColor = .All
    @Published var attribute: MushroomAttribute = .All
    @Published var size: MushroomSize = .All
    @Published var countryCode: String = Locale.current.region?.identifier ?? "US"
    @Published var city: String = NSLocalizedString("host_city_default", comment: "")
    @Published var otherMessage: String = ""
    @Published var fixedRaidCost: Int = 10

    // UI State
    @Published var showSuccessAlert: Bool = false
    @Published var successRoomId: String? = nil
    @Published var errorMessage: String? = nil
    @Published var isSubmitting: Bool = false
    @Published var showLimitAlert: Bool = false
    @Published var limitAlertMessage: String = ""
    @Published var showNameError: Bool = false
    @Published var showAreaError: Bool = false
    @Published var showRequiredAlert: Bool = false

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

    init(session: SessionStore, repo: FirebaseHostRepository = FirebaseHostRepository()) {
        self.session = session
        self.repo = repo
        self.mode = .create
    }

    init(session: SessionStore, room: RoomDetail, repo: FirebaseHostRepository = FirebaseHostRepository()) {
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

    func enforceLimits() {
        if hostName.count > Self.hostNameMaxChars {
            hostName = String(hostName.prefix(Self.hostNameMaxChars))
        }
        if otherCharCount > Self.otherMaxChars {
            otherMessage = Self.trimToChars(otherMessage, maxChars: Self.otherMaxChars)
        }
    }

    func submit() async {
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

        do {
        let req = FirestoreRoomCreateRequest(
            title: hostName,
            targetColor: color.rawValue,
            targetAttribute: attribute.rawValue,
            targetSize: size.rawValue,
            location: locationString,
            description: otherMessage,
            hostFriendCode: session.friendCode,
            fixedRaidCost: fixedRaidCost
        )

            switch mode {
            case .create:
                let roomId = try await repo.createRoom(
                    req: req,
                    hostName: session.displayName,
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
            if let limitError = error as? HostRoomError {
                limitAlertMessage = limitError.errorDescription ?? ""
                showLimitAlert = true
            } else {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func reset() {
        hostName = NSLocalizedString("host_room_default_name", comment: "")
        color = .All
        attribute = .All
        size = .All
        countryCode = Locale.current.region?.identifier ?? "US"
        city = NSLocalizedString("host_city_default", comment: "")
        otherMessage = ""
        fixedRaidCost = 10
        errorMessage = nil
        successRoomId = nil
        showSuccessAlert = false
        showNameError = false
        showAreaError = false
    }

    private func seed(from room: RoomDetail) {
        hostName = room.title
        color = room.targetMushroom.color
        attribute = room.targetMushroom.attribute
        size = room.targetMushroom.size
        if let parsed = parseLocation(room.location) {
            countryCode = parsed.countryCode
            city = parsed.city
        } else {
            countryCode = Locale.current.region?.identifier ?? "US"
            city = room.location
        }
        otherMessage = room.description
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
        let target = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if target.isEmpty { return nil }
        for code in Locale.isoRegionCodes {
            let display = Locale.current.localizedString(forRegionCode: code) ?? ""
            if display.lowercased() == target {
                return code
            }
        }
        return nil
    }

    // MARK: Validation
    @discardableResult
    func validateRequired() -> Bool {
        let nameOK = !hostName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let areaOK = !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        showNameError = !nameOK
        showAreaError = !areaOK
        return nameOK && areaOK
    }
}

// MARK: - View

struct HostView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore
    @Environment(\.colorScheme) private var scheme
    @StateObject private var vm: HostViewModel
    private let onCloseRoom: (() -> Void)?
    @State private var isNameFirstResponder: Bool = false
    @State private var isAreaFirstResponder: Bool = false

    init(vm: HostViewModel, onCloseRoom: (() -> Void)? = nil) {
        _vm = StateObject(wrappedValue: vm)
        self.onCloseRoom = onCloseRoom
    }

    var body: some View {
        NavigationStack {
            Form {
                // Host name
                Section {
                    SelectAllTextField(
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

                // Mushroom properties
                Section(LocalizedStringKey("host_target_section")) {
                    Picker(LocalizedStringKey("host_color_label"), selection: $vm.color) {
                        ForEach(MushroomColor.allCases, id: \.self) { c in
                            Text(localizedColor(c)).tag(c)
                        }
                    }

                    Picker(LocalizedStringKey("host_attribute_label"), selection: $vm.attribute) {
                        ForEach(MushroomAttribute.allCases, id: \.self) { a in
                            Text(localizedAttribute(a)).tag(a)
                        }
                    }

                    Picker(LocalizedStringKey("host_size_label"), selection: $vm.size) {
                        ForEach(MushroomSize.allCases, id: \.self) { s in
                            Text(localizedSize(s)).tag(s)
                        }
                    }
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

                        SelectAllTextField(
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
                } footer: {
                    Text(LocalizedStringKey("host_location_footer"))
                }

                // Other message (100 chars max)
                Section {
                    TextEditor(text: $vm.otherMessage)
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

                Section {
                    Stepper(value: $vm.fixedRaidCost, in: 1...10_000, step: 1) {
                        HStack {
                            Text(LocalizedStringKey("host_min_bid_label"))
                            Spacer()
                            Text("\(vm.fixedRaidCost)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text(LocalizedStringKey("host_min_bid_header"))
                } footer: {
                    Text(LocalizedStringKey("host_min_bid_footer"))
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
            }
            .alert(vm.successAlertTitle, isPresented: $vm.showSuccessAlert) {
                Button(LocalizedStringKey("common_ok")) {
                    dismiss()
                }
            } message: {
                Text(vm.successAlertMessage)
            }
            .alert(LocalizedStringKey("host_limit_title"), isPresented: $vm.showLimitAlert) {
                Button(LocalizedStringKey("common_ok")) {}
            } message: {
                Text(vm.limitAlertMessage)
            }
            .alert(LocalizedStringKey("host_required_title"), isPresented: $vm.showRequiredAlert) {
                Button(LocalizedStringKey("common_ok")) {}
            } message: {
                Text(LocalizedStringKey("host_required_message"))
            }
        }
    }

    private func localizedColor(_ color: MushroomColor) -> LocalizedStringKey {
        switch color {
        case .All: return "mushroom_color_all"
        case .Red: return "mushroom_color_red"
        case .Yellow: return "mushroom_color_yellow"
        case .Blue: return "mushroom_color_blue"
        case .Purple: return "mushroom_color_purple"
        case .White: return "mushroom_color_white"
        case .Gray: return "mushroom_color_gray"
        case .Pink: return "mushroom_color_pink"
        }
    }

    private func localizedAttribute(_ attribute: MushroomAttribute) -> LocalizedStringKey {
        switch attribute {
        case .All: return "mushroom_attr_all"
        case .Normal: return "mushroom_attr_normal"
        case .Fire: return "mushroom_attr_fire"
        case .Water: return "mushroom_attr_water"
        case .Crystal: return "mushroom_attr_crystal"
        case .Electric: return "mushroom_attr_electric"
        case .Poisonous: return "mushroom_attr_poisonous"
        }
    }

    private func localizedSize(_ size: MushroomSize) -> LocalizedStringKey {
        switch size {
        case .All: return "mushroom_size_all"
        case .Small: return "mushroom_size_small"
        case .Normal: return "mushroom_size_normal"
        case .Magnificent: return "mushroom_size_magnificent"
        }
    }
}

private struct SelectAllTextField: UIViewRepresentable {
    let placeholderKey: String
    @Binding var text: String
    @Binding var isFirstResponder: Bool
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = .name
    var autocapitalization: UITextAutocapitalizationType = .words
    var autocorrection: UITextAutocorrectionType = .no
    var textAlignment: NSTextAlignment = .left
    var onChange: ((String) -> Void)? = nil

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.borderStyle = .none
        tf.textAlignment = textAlignment
        tf.autocorrectionType = autocorrection
        tf.autocapitalizationType = autocapitalization
        tf.textContentType = textContentType
        tf.keyboardType = keyboardType
        tf.placeholder = NSLocalizedString(placeholderKey, comment: "")
        tf.addTarget(context.coordinator, action: #selector(Coordinator.textChanged), for: .editingChanged)
        tf.delegate = context.coordinator
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        if isFirstResponder, !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
            DispatchQueue.main.async {
                uiView.selectAll(nil)
            }
        } else if !isFirstResponder, uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFirstResponder: $isFirstResponder, onChange: onChange)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        @Binding var isFirstResponder: Bool
        let onChange: ((String) -> Void)?

        init(text: Binding<String>, isFirstResponder: Binding<Bool>, onChange: ((String) -> Void)?) {
            _text = text
            _isFirstResponder = isFirstResponder
            self.onChange = onChange
        }

        @objc func textChanged(_ sender: UITextField) {
            let value = sender.text ?? ""
            text = value
            onChange?(value)
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            isFirstResponder = true
            DispatchQueue.main.async {
                textField.selectAll(nil)
            }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            isFirstResponder = false
        }
    }
}
