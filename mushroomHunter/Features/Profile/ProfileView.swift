//
//  ProfileView.swift
//  mushroomHunter
//
//  Created by Ken on 4/2/2026.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ProfileView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.colorScheme) private var scheme

    // Name editing
    @State private var isEditingName: Bool = false
    @State private var draftName: String = ""
    @State private var nameFieldFocused: Bool = false

    // Friend code editing
    @State private var isEditingFriendCode: Bool = false
    @State private var draftFriendCode: String = ""
    @State private var friendCodeError: String? = nil
    @State private var friendCodeFieldFocused: Bool = false

    // host room
    @State private var isHostLoading: Bool = false
    @State private var hostErrorMessage: String? = nil
    @State private var hostedRooms: [HostedRoomSummary] = []
    @State private var isJoinedLoading: Bool = false
    @State private var joinedErrorMessage: String? = nil
    @State private var joinedRooms: [JoinedRoomSummary] = []
    @State private var isOnShelfLoading: Bool = false
    @State private var onShelfErrorMessage: String? = nil
    @State private var onShelfPostcards: [PostcardListing] = []
    @State private var isOrderedLoading: Bool = false
    @State private var orderedErrorMessage: String? = nil
    @State private var orderedPostcards: [PostcardListing] = []
    @State private var selectedPostcard: PostcardListing? = nil
    @State private var showSettingsSheet: Bool = false
    @State private var showFeedbackSheet: Bool = false
    @State private var showFeedbackSubmittedAlert: Bool = false
    @State private var pendingOpenFeedbackFromSettings: Bool = false

    private let hostRepo = FirebaseProfileHostRepository()
    private let postcardRepo = FirebasePostcardRepository()
    private let feedbackRepo = FirebaseFeedbackRepository()

    // Host rooms (MVP: mock; later: load from Firestore)
    //@State private var hostedRooms: [HostedRoomStub] = []

    var body: some View {
        NavigationStack {
            Form {

                // MARK: Account
                Section {
                    // Name row
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(LocalizedStringKey("profile_name"))
                            Spacer()
                            if isEditingName {
                                SelectAllTextField(
                                    placeholderKey: "profile_name_placeholder",
                                    text: $draftName,
                                    isFirstResponder: $nameFieldFocused
                                )
                                .frame(height: 22)
                                .multilineTextAlignment(.trailing)
                            } else {
                                Text(session.displayName)
                                    .foregroundStyle(.secondary)
                            }

                            Button {
                                if !isEditingName {
                                    isEditingName = true
                                    draftName = session.displayName
                                    nameFieldFocused = true
                                }
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(LocalizedStringKey("profile_edit_name_accessibility"))
                        }

                        if isEditingName {
                            Text(LocalizedStringKey("profile_name_hint"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            HStack {
                                Button(LocalizedStringKey("common_cancel")) {
                                    draftName = session.displayName
                                    isEditingName = false
                                    nameFieldFocused = false
                                }

                                Spacer()

                                Button(LocalizedStringKey("common_save")) {
                                    let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !trimmed.isEmpty else { return }
                                    session.updateDisplayName(trimmed)
                                    isEditingName = false
                                    nameFieldFocused = false
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                    }
                    .padding(.vertical, 4)

                    // Friend code row
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(LocalizedStringKey("profile_friend_code"))
                            Spacer()

                            if isEditingFriendCode {
                                SelectAllTextField(
                                    placeholderKey: "profile_friend_code_placeholder",
                                    text: $draftFriendCode,
                                    isFirstResponder: $friendCodeFieldFocused,
                                    keyboardType: .numberPad,
                                    textContentType: .oneTimeCode,
                                    autocapitalization: .none,
                                    autocorrection: .no
                                ) { newValue in
                                    let digitsOnly = newValue.filter { $0.isNumber }
                                    if digitsOnly != newValue {
                                        draftFriendCode = digitsOnly
                                    }
                                    if draftFriendCode.count > 12 {
                                        draftFriendCode = String(draftFriendCode.prefix(12))
                                    }
                                    friendCodeError = validateFriendCode(draftFriendCode)
                                }
                                .frame(height: 22)
                                .multilineTextAlignment(.trailing)
                            } else {
                                let raw = session.friendCode
                                Text(raw.isEmpty ? "XXXX XXXX XXXX" : formatFriendCode(raw))
                                    .foregroundStyle(.secondary)
                            }

                            Button {
                                if !isEditingFriendCode {
                                    isEditingFriendCode = true
                                    draftFriendCode = session.friendCode.filter { $0.isNumber }
                                    friendCodeError = validateFriendCode(draftFriendCode)
                                    friendCodeFieldFocused = true
                                }
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(LocalizedStringKey("profile_edit_friend_code_accessibility"))
                        }

                        if isEditingFriendCode {
                            Text(LocalizedStringKey("profile_friend_code_hint"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            if let err = friendCodeError {
                                Text(err)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }

                            HStack {
                                Button(LocalizedStringKey("common_cancel")) {
                                    draftFriendCode = session.friendCode.filter { $0.isNumber }
                                    friendCodeError = nil
                                    isEditingFriendCode = false
                                    friendCodeFieldFocused = false
                                }

                                Spacer()

                                Button(LocalizedStringKey("common_save")) {
                                    if validateFriendCode(draftFriendCode) == nil {
                                        session.updateFriendCode(draftFriendCode)
                                        isEditingFriendCode = false
                                        friendCodeError = nil
                                        friendCodeFieldFocused = false
                                    } else {
                                        friendCodeError = validateFriendCode(draftFriendCode)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(validateFriendCode(draftFriendCode) != nil)
                            }
                        }
                    }
                    .padding(.vertical, 4)

                } header: {
                    Text(LocalizedStringKey("profile_id_section"))
                }

                // MARK: - Community
                Section {
                    HStack {
                        Label(LocalizedStringKey("profile_stars"), systemImage: "star.fill")
                            .foregroundStyle(.yellow)

                        Spacer()

                        Text("\(session.stars)")
                            .font(.headline)
                            .monospacedDigit()
                    }

                    HStack {
                        HStack(spacing: 6) {
                            Image("HoneyIcon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                            Text(LocalizedStringKey("profile_honey"))
                        }

                        Spacer()

                        Text("\(session.honey)")
                            .font(.headline)
                            .monospacedDigit()
                    }

                } header: {
                    Text(LocalizedStringKey("profile_community_section"))
                } footer: {
                    Text(LocalizedStringKey("profile_community_footer"))
                }

                Section {
                    JoinedRoomsSection(
                        rooms: joinedRooms,
                        isLoading: isJoinedLoading,
                        errorMessage: joinedErrorMessage
                    )
                    .equatable()

                    HostedRoomsSection(
                        rooms: hostedRooms,
                        isLoading: isHostLoading,
                        errorMessage: hostErrorMessage,
                        onRoomClosed: { Task { await loadHostedRooms() } }
                    )
                    .equatable()
                } header: {
                    Text(LocalizedStringKey("profile_mushroom_section"))
                }

                Section {
                    OnShelfPostcardsSection(
                        postcards: onShelfPostcards,
                        isLoading: isOnShelfLoading,
                        errorMessage: onShelfErrorMessage,
                        onSelectPostcard: { selectedPostcard = $0 }
                    )
                    .equatable()

                    OrderedPostcardsSection(
                        postcards: orderedPostcards,
                        isLoading: isOrderedLoading,
                        errorMessage: orderedErrorMessage,
                        onSelectPostcard: { selectedPostcard = $0 }
                    )
                    .equatable()
                } header: {
                    Text(LocalizedStringKey("profile_postcard_section"))
                }
                // MARK: Sign out
                Section {
                    Button(role: .destructive) {
                        session.signOut()
                    } label: {
                        Text(LocalizedStringKey("profile_sign_out"))
                    }
                }
            }
            .navigationTitle(LocalizedStringKey("profile_title"))
            .navigationDestination(item: $selectedPostcard) { postcard in
                PostcardDetailView(listing: postcard)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundGradient(for: scheme))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettingsSheet = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(LocalizedStringKey("settings_title"))
                }
            }
            .task {
                await session.refreshProfileFromBackend()
                await loadJoinedRooms()
                await loadHostedRooms()
                await loadOnShelfPostcards()
                await loadOrderedPostcards()
            }
            .refreshable {
                await session.refreshProfileFromBackend()
                await loadJoinedRooms()
                await loadHostedRooms()
                await loadOnShelfPostcards()
                await loadOrderedPostcards()
            }
        }
        .sheet(isPresented: $showSettingsSheet, onDismiss: {
            if pendingOpenFeedbackFromSettings {
                pendingOpenFeedbackFromSettings = false
                showFeedbackSheet = true
            }
        }) {
            NavigationStack {
                List {
                    Section {
                        Button {
                            pendingOpenFeedbackFromSettings = true
                            showSettingsSheet = false
                        } label: {
                            Label(LocalizedStringKey("settings_feedback_button"), systemImage: "envelope")
                        }

                        NavigationLink {
                            AboutView()
                        } label: {
                            Label(LocalizedStringKey("settings_about_button"), systemImage: "info.circle")
                        }
                    }

                    Section {
                        Text(LocalizedStringKey("settings_language_managed"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle(LocalizedStringKey("settings_title"))
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            showSettingsSheet = false
                        } label: {
                            Image(systemName: "xmark")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showFeedbackSheet) {
            FeedbackComposeSheet { draft in
                let uid = session.authUid
                let displayName = session.displayName
                let friendCode = session.friendCode
                try await feedbackRepo.submitFeedback(
                    userId: uid,
                    displayName: displayName,
                    friendCode: friendCode,
                    subject: draft.subject,
                    message: draft.body
                )
                await MainActor.run {
                    showFeedbackSubmittedAlert = true
                }
            }
        }
        .alert(LocalizedStringKey("feedback_submit_success_title"), isPresented: $showFeedbackSubmittedAlert) {
            Button(LocalizedStringKey("common_done")) { }
        } message: {
            Text(LocalizedStringKey("feedback_submit_success_message"))
        }
        .onAppear {
            draftName = session.displayName
            draftFriendCode = session.friendCode
            friendCodeError = nil
            Task { await session.refreshProfileFromBackend() }
        }
    }

    // MARK: - Validation / Formatting

    private func validateFriendCode(_ code: String) -> String? {
        if code.isEmpty { return NSLocalizedString("profile_friend_code_error_required", comment: "") }
        if code.count != 12 { return NSLocalizedString("profile_friend_code_error_length", comment: "") }
        if code.allSatisfy({ $0.isNumber }) == false { return NSLocalizedString("profile_friend_code_error_digits", comment: "") }
        return nil
    }

    private func loadHostedRooms() async {
        guard session.isLoggedIn else { return }

        isHostLoading = true
        hostErrorMessage = nil
        defer { isHostLoading = false }

        do {
            let rooms = try await hostRepo.fetchMyHostedRooms(limit: 50)
            hostedRooms = rooms
        } catch is CancellationError {
            return
        } catch {
            print("❌ loadHostedRooms error:", error)
            hostErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func loadJoinedRooms() async {
        guard session.isLoggedIn else { return }

        isJoinedLoading = true
        joinedErrorMessage = nil
        defer { isJoinedLoading = false }

        do {
            let rooms = try await hostRepo.fetchMyJoinedRooms(limit: 50)
            joinedRooms = rooms
        } catch is CancellationError {
            return
        } catch {
            print("❌ loadJoinedRooms error:", error)
            joinedErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func loadOnShelfPostcards() async {
        guard let uid = session.authUid, !uid.isEmpty else { return }

        isOnShelfLoading = true
        onShelfErrorMessage = nil
        defer { isOnShelfLoading = false }

        do {
            onShelfPostcards = try await postcardRepo.fetchMyListings(userId: uid, limit: 50)
        } catch is CancellationError {
            return
        } catch {
            print("❌ loadOnShelfPostcards error:", error)
            onShelfErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func loadOrderedPostcards() async {
        guard let uid = session.authUid, !uid.isEmpty else { return }

        isOrderedLoading = true
        orderedErrorMessage = nil
        defer { isOrderedLoading = false }

        do {
            orderedPostcards = try await postcardRepo.fetchMyOrderedPostcards(userId: uid, limit: 50)
        } catch is CancellationError {
            return
        } catch {
            print("❌ loadOrderedPostcards error:", error)
            orderedErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func formatFriendCode(_ raw: String) -> String {
        let digits = raw.filter { $0.isNumber }
        var parts: [String] = []
        var i = digits.startIndex
        while i < digits.endIndex {
            let end = digits.index(i, offsetBy: 4, limitedBy: digits.endIndex) ?? digits.endIndex
            parts.append(String(digits[i..<end]))
            i = end
        }
        return parts.joined(separator: " ")
    }

}

private func localizedRoomStatus(_ status: String) -> LocalizedStringKey {
    let lower = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return lower == "open" ? "common_open" : "common_closed"
}

// MARK: - Host room stub (MVP)

private struct HostedRoomStub: Identifiable {
    let id: String
    let roomId: String
    let title: String
}

// MARK: - Joined/Hosted Sections (Equatable for smoother typing)

private struct SelectAllTextField: UIViewRepresentable {
    let placeholderKey: String
    @Binding var text: String
    @Binding var isFirstResponder: Bool
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = .name
    var autocapitalization: UITextAutocapitalizationType = .words
    var autocorrection: UITextAutocorrectionType = .no
    var onChange: ((String) -> Void)? = nil

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.borderStyle = .none
        tf.textAlignment = .right
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

private struct FeedbackMailDraft {
    let subject: String
    let body: String
}

private struct FeedbackComposeSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var subject: String = ""
    @State private var messageText: String = ""
    @State private var isSubmitting: Bool = false
    @State private var submissionError: String? = nil
    @State private var showSubmissionErrorAlert: Bool = false

    let onSend: (FeedbackMailDraft) async throws -> Void

    private var trimmedBody: String {
        messageText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var bodyView: some View {
        Form {
            Section {
                TextField(LocalizedStringKey("feedback_subject_placeholder"), text: $subject)
                TextEditor(text: $messageText)
                    .frame(minHeight: 180)
            } header: {
                Text(LocalizedStringKey("feedback_message_label"))
            }
        }
    }

    var body: some View {
        NavigationStack {
            bodyView
                .navigationTitle(LocalizedStringKey("feedback_title"))
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(LocalizedStringKey("common_cancel")) {
                            dismiss()
                        }
                        .disabled(isSubmitting)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(LocalizedStringKey("feedback_send_button")) {
                            let fallback = NSLocalizedString("feedback_subject_default", comment: "")
                            let finalSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? fallback
                                : subject.trimmingCharacters(in: .whitespacesAndNewlines)
                            let draft = FeedbackMailDraft(subject: finalSubject, body: trimmedBody)
                            Task {
                                isSubmitting = true
                                do {
                                    try await onSend(draft)
                                    dismiss()
                                } catch {
                                    submissionError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                                    showSubmissionErrorAlert = true
                                }
                                isSubmitting = false
                            }
                        }
                        .disabled(trimmedBody.isEmpty || isSubmitting)
                    }
                }
                .overlay {
                    if isSubmitting {
                        ZStack {
                            Color.black.opacity(0.12)
                            ProgressView()
                        }
                        .ignoresSafeArea()
                    }
                }
                .alert(LocalizedStringKey("feedback_submit_failed_title"), isPresented: $showSubmissionErrorAlert) {
                    Button(LocalizedStringKey("common_done")) { }
                } message: {
                    Text(submissionError ?? NSLocalizedString("feedback_submit_failed_message", comment: ""))
                }
        }
    }
}

enum FeedbackRepoError: LocalizedError {
    case emptyMessage

    var errorDescription: String? {
        switch self {
        case .emptyMessage:
            return NSLocalizedString("feedback_submit_failed_message", comment: "")
        }
    }
}

private final class FirebaseFeedbackRepository {
    private let db = Firestore.firestore()

    func submitFeedback(
        userId: String?,
        displayName: String,
        friendCode: String,
        subject: String,
        message: String
    ) async throws {
        let explicitUserId = userId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let authUserId = Auth.auth().currentUser?.uid ?? ""
        let resolvedUserId = explicitUserId.isEmpty ? authUserId : explicitUserId

        let cleanSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanMessage.isEmpty == false else { throw FeedbackRepoError.emptyMessage }

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        let bundleId = Bundle.main.bundleIdentifier ?? ""

        try await db.collection("feedbackSubmissions").addDocument(data: [
            "userId": resolvedUserId,
            "displayName": displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            "friendCode": friendCode.trimmingCharacters(in: .whitespacesAndNewlines),
            "subject": cleanSubject,
            "message": cleanMessage,
            "appVersion": version,
            "buildNumber": build,
            "bundleId": bundleId,
            "localeIdentifier": Locale.current.identifier,
            "platform": "iOS",
            "createdAt": Timestamp(date: Date())
        ])
    }
}

private struct AboutView: View {
    var body: some View {
        List {
            Section {
                Text(LocalizedStringKey("about_intro"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent(LocalizedStringKey("about_phone_label")) {
                    Link("+886 930200769", destination: URL(string: "tel://886930200769")!)
                }

                LabeledContent(LocalizedStringKey("about_email_label")) {
                    Link("kenyu910645@gmail.com", destination: URL(string: "mailto:kenyu910645@gmail.com")!)
                }

                LabeledContent(LocalizedStringKey("about_website_label")) {
                    Link("kenyu910645.github.io", destination: URL(string: "https://kenyu910645.github.io/")!)
                }
            }
        }
        .navigationTitle(LocalizedStringKey("about_title"))
    }
}

private struct JoinedRoomsSection: View, Equatable {
    @EnvironmentObject private var session: SessionStore

    let rooms: [JoinedRoomSummary]
    let isLoading: Bool
    let errorMessage: String?

    static func == (lhs: JoinedRoomsSection, rhs: JoinedRoomsSection) -> Bool {
        lhs.rooms == rhs.rooms
            && lhs.isLoading == rhs.isLoading
            && lhs.errorMessage == rhs.errorMessage
    }

    var body: some View {
        Group {
            if let err = errorMessage {
                Text(err)
                    .foregroundStyle(.red)
            }

            if isLoading && rooms.isEmpty {
                HStack {
                    ProgressView()
                    Text(LocalizedStringKey("profile_loading_joined"))
                        .foregroundStyle(.secondary)
                }
            } else if rooms.isEmpty {
                ContentUnavailableView(
                    LocalizedStringKey("profile_joined_empty_title"),
                    systemImage: "person.2"
//                    description: Text(LocalizedStringKey("profile_joined_empty_description"))
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(rooms) { r in
                    NavigationLink {
                        RoomDetailsView(
                            vm: RoomDetailsViewModel(roomId: r.id, session: session)
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(r.title)
                                    .font(.headline)
                                    .lineLimit(1)
                            }

                            HStack(spacing: 8) {
                                Text(String(format: NSLocalizedString("profile_players_format", comment: ""), r.joinedCount, r.maxPlayers))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Text(String(format: NSLocalizedString("profile_bid_format", comment: ""), r.depositHoney))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct HostedRoomsSection: View, Equatable {
    @EnvironmentObject private var session: SessionStore

    let rooms: [HostedRoomSummary]
    let isLoading: Bool
    let errorMessage: String?
    let onRoomClosed: () -> Void

    static func == (lhs: HostedRoomsSection, rhs: HostedRoomsSection) -> Bool {
        lhs.rooms == rhs.rooms
            && lhs.isLoading == rhs.isLoading
            && lhs.errorMessage == rhs.errorMessage
    }

    var body: some View {
        Group {
            if let err = errorMessage {
                Text(err)
                    .foregroundStyle(.red)
            }

            if isLoading && rooms.isEmpty {
                HStack {
                    ProgressView()
                    Text(LocalizedStringKey("profile_loading_hosted"))
                        .foregroundStyle(.secondary)
                }
            } else if rooms.isEmpty {
                ContentUnavailableView(
                    LocalizedStringKey("profile_hosted_empty_title"),
                    systemImage: "house"
//                    description: Text(LocalizedStringKey("profile_hosted_empty_description"))
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(rooms) { r in
                    NavigationLink {
                        RoomDetailsView(
                            vm: RoomDetailsViewModel(roomId: r.id, session: session),
                            onRoomClosed: onRoomClosed
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(r.title)
                                    .font(.headline)
                                    .lineLimit(1)
                            }

                            Text(String(format: NSLocalizedString("profile_players_format", comment: ""), r.joinedCount, r.maxPlayers))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

private struct OnShelfPostcardsSection: View, Equatable {
    let postcards: [PostcardListing]
    let isLoading: Bool
    let errorMessage: String?
    let onSelectPostcard: (PostcardListing) -> Void

    static func == (lhs: OnShelfPostcardsSection, rhs: OnShelfPostcardsSection) -> Bool {
        lhs.postcards == rhs.postcards
            && lhs.isLoading == rhs.isLoading
            && lhs.errorMessage == rhs.errorMessage
    }

    var body: some View {
        Group {
            Text(LocalizedStringKey("profile_postcard_onshelf_section"))
                .font(.subheadline.weight(.semibold))

            if let err = errorMessage {
                Text(err)
                    .foregroundStyle(.red)
            }

            if isLoading && postcards.isEmpty {
                HStack {
                    ProgressView()
                    Text(LocalizedStringKey("profile_loading_onshelf_postcards"))
                        .foregroundStyle(.secondary)
                }
            } else if postcards.isEmpty {
                ContentUnavailableView(
                    LocalizedStringKey("profile_onshelf_empty_title"),
                    systemImage: "shippingbox"
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(postcards) { postcard in
                    Button {
                        onSelectPostcard(postcard)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(postcard.title)
                                .font(.headline)
                                .lineLimit(1)

                            HStack {
                                Text(postcard.location.shortLabel)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer()
                                Text(String(format: NSLocalizedString("postcard_stock_format", comment: ""), postcard.stock))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct OrderedPostcardsSection: View, Equatable {
    let postcards: [PostcardListing]
    let isLoading: Bool
    let errorMessage: String?
    let onSelectPostcard: (PostcardListing) -> Void

    static func == (lhs: OrderedPostcardsSection, rhs: OrderedPostcardsSection) -> Bool {
        lhs.postcards == rhs.postcards
            && lhs.isLoading == rhs.isLoading
            && lhs.errorMessage == rhs.errorMessage
    }

    var body: some View {
        Group {
            Text(LocalizedStringKey("profile_postcard_ordered_section"))
                .font(.subheadline.weight(.semibold))

            if let err = errorMessage {
                Text(err)
                    .foregroundStyle(.red)
            }

            if isLoading && postcards.isEmpty {
                HStack {
                    ProgressView()
                    Text(LocalizedStringKey("profile_loading_ordered_postcards"))
                        .foregroundStyle(.secondary)
                }
            } else if postcards.isEmpty {
                ContentUnavailableView(
                    LocalizedStringKey("profile_ordered_empty_title"),
                    systemImage: "cart"
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(postcards) { postcard in
                    Button {
                        onSelectPostcard(postcard)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(postcard.title)
                                .font(.headline)
                                .lineLimit(1)

                            HStack(spacing: 4) {
                                Text("\(postcard.priceHoney)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                Image("HoneyIcon")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 12, height: 12)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private extension ProfileView {
    static func mockHostedRooms(for name: String) -> [HostedRoomStub] {
        // Just 2 sample rooms. Replace with Firestore later.
        [
            .init(id: "h1", roomId: "room_ken_001", title: "\(name)’s Fire Hunt"),
            .init(id: "h2", roomId: "room_ken_002", title: "\(name)’s Water Squad")
        ]
    }
}
