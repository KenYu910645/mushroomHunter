//
//  ProfileView.swift
//  mushroomHunter
//
//  Purpose:
//  - Implements profile tab UI, editing, settings actions, and related lists.
//
//  Defined in this file:
//  - ProfileView sections, form state, and profile-linked data views.
//
import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var session: UserSessionStore // State or dependency property.
    @Environment(\.colorScheme) private var scheme // State or dependency property.
    // Name editing
    @State private var isEditingName: Bool = false // State or dependency property.
    @State private var draftName: String = "" // State or dependency property.
    @State private var nameFieldFocused: Bool = false // State or dependency property.
    // Friend code editing
    @State private var isEditingFriendCode: Bool = false // State or dependency property.
    @State private var draftFriendCode: String = "" // State or dependency property.
    @State private var friendCodeError: String? = nil // State or dependency property.
    @State private var friendCodeFieldFocused: Bool = false // State or dependency property.
    // host room
    @State private var isHostLoading: Bool = false // State or dependency property.
    @State private var hostErrorMessage: String? = nil // State or dependency property.
    @State private var hostedRooms: [HostedRoomSummary] = [] // State or dependency property.
    @State private var isJoinedLoading: Bool = false // State or dependency property.
    @State private var joinedErrorMessage: String? = nil // State or dependency property.
    @State private var joinedRooms: [JoinedRoomSummary] = [] // State or dependency property.
    @State private var isOnShelfLoading: Bool = false // State or dependency property.
    @State private var onShelfErrorMessage: String? = nil // State or dependency property.
    @State private var onShelfPostcards: [PostcardListing] = [] // State or dependency property.
    @State private var isOrderedLoading: Bool = false // State or dependency property.
    @State private var orderedErrorMessage: String? = nil // State or dependency property.
    @State private var orderedPostcards: [PostcardListing] = [] // State or dependency property.
    @State private var selectedPostcard: PostcardListing? = nil // State or dependency property.
    @State private var showSettingsSheet: Bool = false // State or dependency property.
    @State private var showFeedbackSheet: Bool = false // State or dependency property.
    @State private var showFeedbackSubmittedAlert: Bool = false // State or dependency property.
    @State private var pendingOpenFeedbackFromSettings: Bool = false // State or dependency property.
    private let hostRepo = FirebaseProfileHostRepository()
    private let postcardRepo = FirebasePostcardRepository()
    private let feedbackRepo = FirebaseFeedbackRepository()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                BrowseViewTopActionBar(
                    honey: session.honey,
                    onSearch: nil,
                    onCreate: nil,
                    searchAccessibilityLabel: nil,
                    createAccessibilityLabel: nil,
                    searchButtonIdentifier: nil,
                    createButtonIdentifier: nil,
                    showActions: false
                )
                .padding(.horizontal)
                .padding(.top, 8)

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
                                    isFirstResponder: $nameFieldFocused,
                                    textAlignment: .right
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
                                    autocorrection: .no,
                                    textAlignment: .right
                                ) { newValue in
                                    let digitsOnly = newValue.filter { $0.isNumber }
                                    if digitsOnly != newValue {
                                        draftFriendCode = digitsOnly
                                    }
                                    if draftFriendCode.count > AppConfig.Profile.friendCodeDigits {
                                        draftFriendCode = String(draftFriendCode.prefix(AppConfig.Profile.friendCodeDigits))
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
                await refreshAllProfileData()
            }
            .refreshable {
                await refreshAllProfileData()
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
        }
    }

    // MARK: - Validation / Formatting

    private func validateFriendCode(_ code: String) -> String? {
        if code.isEmpty { return NSLocalizedString("profile_friend_code_error_required", comment: "") }
        if code.count != AppConfig.Profile.friendCodeDigits { return NSLocalizedString("profile_friend_code_error_length", comment: "") }
        if code.allSatisfy({ $0.isNumber }) == false { return NSLocalizedString("profile_friend_code_error_digits", comment: "") }
        return nil
    }

    private func refreshAllProfileData() async {
        await session.refreshProfileFromBackend()
        async let joinedRoomsLoad = loadJoinedRooms()
        async let hostedRoomsLoad = loadHostedRooms()
        async let onShelfLoad = loadOnShelfPostcards()
        async let orderedLoad = loadOrderedPostcards()
        _ = await (joinedRoomsLoad, hostedRoomsLoad, onShelfLoad, orderedLoad)
    }

    private func loadHostedRooms() async {
        guard session.isLoggedIn else { return }

        isHostLoading = true
        hostErrorMessage = nil
        defer { isHostLoading = false }

        do {
            let rooms = try await hostRepo.fetchMyHostedRooms(limit: AppConfig.Mushroom.profileListFetchLimit)
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
            let rooms = try await hostRepo.fetchMyJoinedRooms(limit: AppConfig.Mushroom.profileListFetchLimit)
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
            onShelfPostcards = try await postcardRepo.fetchMyListings(userId: uid, limit: AppConfig.Postcard.profileListFetchLimit)
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
            orderedPostcards = try await postcardRepo.fetchMyOrderedPostcards(userId: uid, limit: AppConfig.Postcard.profileListFetchLimit)
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

private struct FeedbackMailDraft {
    let subject: String
    let body: String
}

private struct FeedbackComposeSheet: View {
    @Environment(\.dismiss) private var dismiss // State or dependency property.
    @State private var subject: String = "" // State or dependency property.
    @State private var subjectFieldFocused: Bool = false // State or dependency property.
    @State private var messageText: String = "" // State or dependency property.
    @State private var messageFieldFocused: Bool = false // State or dependency property.
    @State private var isSubmitting: Bool = false // State or dependency property.
    @State private var submissionError: String? = nil // State or dependency property.
    @State private var showSubmissionErrorAlert: Bool = false // State or dependency property.
    let onSend: (FeedbackMailDraft) async throws -> Void

    private var trimmedBody: String {
        messageText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var bodyView: some View {
        Form {
            Section {
                SelectAllTextField(
                    placeholderKey: "feedback_subject_placeholder",
                    text: $subject,
                    isFirstResponder: $subjectFieldFocused,
                    textAlignment: .left
                )
                .frame(height: 22)
                SelectAllTextEditor(
                    text: $messageText,
                    isFirstResponder: $messageFieldFocused,
                    autocapitalization: .sentences,
                    autocorrection: .yes
                )
                .padding(.horizontal, 2)
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
    @EnvironmentObject private var session: UserSessionStore // State or dependency property.
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
    @EnvironmentObject private var session: UserSessionStore // State or dependency property.
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
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(postcard.title)
                                    .font(.headline)
                                    .lineLimit(1)

                                Text(postcard.location.shortLabel)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            VStack(alignment: .leading, spacing: 4) {
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
                                Text("x\(postcard.stock)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
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
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(postcard.title)
                                    .font(.headline)
                                    .lineLimit(1)

                                Text(postcard.location.shortLabel)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            VStack(alignment: .leading, spacing: 4) {
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
                                Text("x\(postcard.stock)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
