//
//  ProfileView.swift
//  mushroomHunter
//
//  Purpose:
//  - Renders the profile tab and related sheets (profile edit, settings, feedback, about).
//  - Loads profile-owned mushroom/postcard lists and profile summary information.
//
import SwiftUI

/// Profile landing screen that surfaces user identity, reputation, owned rooms, and postcard activity.
struct ProfileView: View {
    /// Shared authenticated session state used across tabs.
    @EnvironmentObject private var session: UserSessionStore

    /// Current color scheme used to keep background styling consistent with app theme.
    @Environment(\.colorScheme) private var colorScheme

    /// Shows loading indicator for hosted room fetches.
    @State private var isHostedRoomsLoading: Bool = false

    /// Presents a hosted room fetch failure message.
    @State private var hostedRoomsErrorMessage: String? = nil

    /// Profile-hosted room list.
    @State private var hostedRooms: [HostedRoomSummary] = []

    /// Shows loading indicator for joined room fetches.
    @State private var isJoinedRoomsLoading: Bool = false

    /// Presents a joined room fetch failure message.
    @State private var joinedRoomsErrorMessage: String? = nil

    /// Profile-joined room list.
    @State private var joinedRooms: [JoinedRoomSummary] = []

    /// Shows loading indicator for on-shelf postcard fetches.
    @State private var isOnShelfPostcardsLoading: Bool = false

    /// Presents an on-shelf postcard fetch failure message.
    @State private var onShelfPostcardsErrorMessage: String? = nil

    /// Postcards currently listed by the user.
    @State private var onShelfPostcards: [PostcardListing] = []

    /// Shows loading indicator for ordered postcard fetches.
    @State private var isOrderedPostcardsLoading: Bool = false

    /// Presents an ordered postcard fetch failure message.
    @State private var orderedPostcardsErrorMessage: String? = nil

    /// Postcards purchased by the user.
    @State private var orderedPostcards: [PostcardListing] = []

    /// Selected postcard used to push into postcard detail.
    @State private var selectedPostcard: PostcardListing? = nil

    /// Controls settings sheet presentation.
    @State private var isSettingsSheetPresented: Bool = false

    /// Controls feedback compose sheet presentation.
    @State private var isFeedbackSheetPresented: Bool = false

    /// Controls edit-profile sheet presentation.
    @State private var isEditProfileSheetPresented: Bool = false

    /// Shows success alert after feedback submission.
    @State private var isFeedbackSubmittedAlertPresented: Bool = false

    /// Defers feedback sheet presentation until settings sheet finishes dismissing.
    @State private var shouldOpenFeedbackAfterSettingsDismiss: Bool = false

    /// Repository that loads hosted and joined room summaries.
    private let hostRepo = FirebaseProfileHostRepository()

    /// Repository that loads profile postcard lists.
    private let postcardRepo = FirebasePostcardRepository()

    /// Repository that submits feedback payloads.
    private let feedbackRepo = FirebaseFeedbackRepository()

    /// Main profile screen composition and modal routing.
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
                    accountSection
                    communitySection
                    mushroomSection
                    postcardSection
                    signOutSection
                }
            }
            .navigationTitle(LocalizedStringKey("profile_title"))
            .navigationDestination(item: $selectedPostcard) { postcard in
                PostcardView(listing: postcard)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundGradient(for: colorScheme))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isEditProfileSheetPresented = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel(LocalizedStringKey("edit_profile_title"))
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isSettingsSheetPresented = true
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
        .sheet(isPresented: $isSettingsSheetPresented, onDismiss: {
            if shouldOpenFeedbackAfterSettingsDismiss {
                shouldOpenFeedbackAfterSettingsDismiss = false
                isFeedbackSheetPresented = true
            }
        }) {
            settingsSheet
        }
        .sheet(isPresented: $isFeedbackSheetPresented) {
            FeedbackView { draft in
                let userId = session.authUid
                let displayName = session.displayName
                let friendCode = session.friendCode
                try await feedbackRepo.submitFeedback(
                    userId: userId,
                    displayName: displayName,
                    friendCode: friendCode,
                    subject: draft.subject,
                    message: draft.body
                )
                await MainActor.run {
                    isFeedbackSubmittedAlertPresented = true
                }
            }
        }
        .sheet(isPresented: $isEditProfileSheetPresented) {
            ProfileFormView(mode: .edit)
        }
        .alert(
            LocalizedStringKey("feedback_submit_success_title"),
            isPresented: $isFeedbackSubmittedAlertPresented
        ) {
            Button(LocalizedStringKey("common_done")) { }
        } message: {
            Text(LocalizedStringKey("feedback_submit_success_message"))
        }
    }

    /// Section that displays profile identity values.
    private var accountSection: some View {
        Section {
            HStack {
                Text(LocalizedStringKey("profile_name"))
                Spacer()
                Text(session.displayName)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

            HStack {
                Text(LocalizedStringKey("profile_friend_code"))
                Spacer()
                let rawFriendCode = session.friendCode
                Text(rawFriendCode.isEmpty ? "XXXX XXXX XXXX" : formatFriendCode(rawFriendCode))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } header: {
            Text(LocalizedStringKey("profile_id_section"))
        }
    }

    /// Section that shows the stars value accumulated by community activity.
    private var communitySection: some View {
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
    }

    /// Section that displays mushroom rooms the user has joined or hosted.
    private var mushroomSection: some View {
        Section {
            JoinedRoomsSection(
                rooms: joinedRooms,
                isLoading: isJoinedRoomsLoading,
                errorMessage: joinedRoomsErrorMessage
            )
            .equatable()

            HostedRoomsSection(
                rooms: hostedRooms,
                isLoading: isHostedRoomsLoading,
                errorMessage: hostedRoomsErrorMessage,
                onRoomClosed: { Task { await loadHostedRooms() } }
            )
            .equatable()
        } header: {
            Text(LocalizedStringKey("profile_mushroom_section"))
        }
    }

    /// Section that displays postcards listed by the user and ordered by the user.
    private var postcardSection: some View {
        Section {
            OnShelfPostcardsSection(
                postcards: onShelfPostcards,
                isLoading: isOnShelfPostcardsLoading,
                errorMessage: onShelfPostcardsErrorMessage,
                onSelectPostcard: { selectedPostcard = $0 }
            )
            .equatable()

            OrderedPostcardsSection(
                postcards: orderedPostcards,
                isLoading: isOrderedPostcardsLoading,
                errorMessage: orderedPostcardsErrorMessage,
                onSelectPostcard: { selectedPostcard = $0 }
            )
            .equatable()
        } header: {
            Text(LocalizedStringKey("profile_postcard_section"))
        }
    }

    /// Section that exposes sign-out action.
    private var signOutSection: some View {
        Section {
            Button(role: .destructive) {
                session.signOut()
            } label: {
                Text(LocalizedStringKey("profile_sign_out"))
            }
        }
    }

    /// Settings sheet that routes to feedback and about pages.
    private var settingsSheet: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        shouldOpenFeedbackAfterSettingsDismiss = true
                        isSettingsSheetPresented = false
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
                        isSettingsSheetPresented = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
    }

    /// Refreshes profile data from backend and loads all profile tab collections in parallel.
    private func refreshAllProfileData() async {
        await session.refreshProfileFromBackend()
        async let joinedRoomsLoad: Void = loadJoinedRooms()
        async let hostedRoomsLoad: Void = loadHostedRooms()
        async let onShelfPostcardsLoad: Void = loadOnShelfPostcards()
        async let orderedPostcardsLoad: Void = loadOrderedPostcards()
        _ = await (joinedRoomsLoad, hostedRoomsLoad, onShelfPostcardsLoad, orderedPostcardsLoad)
    }

    /// Loads rooms hosted by the current user and updates local hosted-room state.
    private func loadHostedRooms() async {
        guard session.isLoggedIn else { return }

        isHostedRoomsLoading = true
        hostedRoomsErrorMessage = nil
        defer { isHostedRoomsLoading = false }

        do {
            hostedRooms = try await hostRepo.fetchMyHostedRooms(limit: AppConfig.Mushroom.profileListFetchLimit)
        } catch is CancellationError {
            return
        } catch {
            print("❌ loadHostedRooms error:", error)
            hostedRoomsErrorMessage = resolvedErrorMessage(from: error)
        }
    }

    /// Loads rooms joined by the current user and updates local joined-room state.
    private func loadJoinedRooms() async {
        guard session.isLoggedIn else { return }

        isJoinedRoomsLoading = true
        joinedRoomsErrorMessage = nil
        defer { isJoinedRoomsLoading = false }

        do {
            joinedRooms = try await hostRepo.fetchMyJoinedRooms(limit: AppConfig.Mushroom.profileListFetchLimit)
        } catch is CancellationError {
            return
        } catch {
            print("❌ loadJoinedRooms error:", error)
            joinedRoomsErrorMessage = resolvedErrorMessage(from: error)
        }
    }

    /// Loads active listings owned by the current user and updates on-shelf postcard state.
    private func loadOnShelfPostcards() async {
        guard let userId = session.authUid, userId.isEmpty == false else { return }

        isOnShelfPostcardsLoading = true
        onShelfPostcardsErrorMessage = nil
        defer { isOnShelfPostcardsLoading = false }

        do {
            onShelfPostcards = try await postcardRepo.fetchMyListings(
                userId: userId,
                limit: AppConfig.Postcard.profileListFetchLimit
            )
        } catch is CancellationError {
            return
        } catch {
            print("❌ loadOnShelfPostcards error:", error)
            onShelfPostcardsErrorMessage = resolvedErrorMessage(from: error)
        }
    }

    /// Loads ordered postcards for the current user and updates ordered postcard state.
    private func loadOrderedPostcards() async {
        guard let userId = session.authUid, userId.isEmpty == false else { return }

        isOrderedPostcardsLoading = true
        orderedPostcardsErrorMessage = nil
        defer { isOrderedPostcardsLoading = false }

        do {
            orderedPostcards = try await postcardRepo.fetchMyOrderedPostcards(
                userId: userId,
                limit: AppConfig.Postcard.profileListFetchLimit
            )
        } catch is CancellationError {
            return
        } catch {
            print("❌ loadOrderedPostcards error:", error)
            orderedPostcardsErrorMessage = resolvedErrorMessage(from: error)
        }
    }

    /// Formats raw friend code into grouped chunks for read-only presentation.
    private func formatFriendCode(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        var chunks: [String] = []
        var chunkStart = digits.startIndex

        while chunkStart < digits.endIndex {
            let chunkEnd = digits.index(chunkStart, offsetBy: 4, limitedBy: digits.endIndex) ?? digits.endIndex
            chunks.append(String(digits[chunkStart..<chunkEnd]))
            chunkStart = chunkEnd
        }

        return chunks.joined(separator: " ")
    }

    /// Converts an error into the best available user-facing message.
    private func resolvedErrorMessage(from error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
