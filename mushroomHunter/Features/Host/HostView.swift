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

    // Dependencies
    private unowned let session: SessionStore
    private let repo: FirebaseHostRepository

    let mode: Mode

    // Inputs
    @Published var hostName: String = ""
    @Published var color: MushroomColor = .Red
    @Published var attribute: MushroomAttribute = .Normal
    @Published var size: MushroomSize = .Normal
    @Published var location: String = ""
    @Published var otherMessage: String = ""
    @Published var fixedRaidCost: Int = 10

    // UI State
    @Published var showSuccessAlert: Bool = false
    @Published var successRoomId: String? = nil
    @Published var errorMessage: String? = nil
    @Published var isSubmitting: Bool = false
    @Published var showLimitAlert: Bool = false
    @Published var limitAlertMessage: String = ""

    // Limits
    static let hostNameMaxChars = 30
    static let otherMaxChars = 100

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

    var hostNameRemaining: Int { Self.hostNameMaxChars - hostName.count }
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
        let locOK = !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        guard canSubmit else { return }

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
                location: location,
                note: otherMessage,
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
        hostName = ""
        color = .Red
        attribute = .Normal
        size = .Normal
        location = ""
        otherMessage = ""
        fixedRaidCost = 10
        errorMessage = nil
        successRoomId = nil
        showSuccessAlert = false
    }

    private func seed(from room: RoomDetail) {
        hostName = room.title
        color = room.targetMushroom.color
        attribute = room.targetMushroom.attribute
        size = room.targetMushroom.size
        location = room.location
        otherMessage = room.note
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
}

// MARK: - View

struct HostView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore
    @Environment(\.colorScheme) private var scheme
    @StateObject private var vm: HostViewModel
    private let onCloseRoom: (() -> Void)?

    init(vm: HostViewModel, onCloseRoom: (() -> Void)? = nil) {
        _vm = StateObject(wrappedValue: vm)
        self.onCloseRoom = onCloseRoom
    }

    var body: some View {
        NavigationStack {
            Form {
                // Host name
                Section {
                    TextField(LocalizedStringKey("host_room_name_placeholder"), text: $vm.hostName)
                        .onChange(of: vm.hostName) { _, _ in vm.enforceLimits() }
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)

//                    HStack {
//                        Text("Remaining")
//                            .foregroundStyle(.secondary)
//                        Spacer()
//                        Text("\(max(vm.hostNameRemaining, 0))")
//                            .foregroundColor(vm.hostNameRemaining >= 0 ? .secondary : .red)
//                            .monospacedDigit()
//                    }
                } header: {
                    Text(LocalizedStringKey("host_room_name_header"))
                }
//                } footer: {
//                    Text(LocalizedStringKey("host_room_name_footer"))
//                }

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
                    TextField(LocalizedStringKey("host_location_placeholder"), text: $vm.location)
                        .onChange(of: vm.location) { _, _ in
                            // Optional: you can add a char limit here too if you want.
                        }
                        .textInputAutocapitalization(.words)
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
//                footer: {
//                    Text(LocalizedStringKey("host_description_footer"))
//                }

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
                    .disabled(!vm.canSubmit)
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
        }
    }

    private func localizedColor(_ color: MushroomColor) -> LocalizedStringKey {
        switch color {
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
        case .Small: return "mushroom_size_small"
        case .Normal: return "mushroom_size_normal"
        case .Magnificent: return "mushroom_size_magnificent"
        }
    }
}
