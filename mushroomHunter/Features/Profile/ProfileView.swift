//
//  ProfileView.swift
//  mushroomHunter
//
//  Purpose:
//  - Renders the profile tab and related sheets (profile edit, settings, feedback, help, about).
//  - Loads profile-owned mushroom/postcard lists and profile summary information.
//
import SwiftUI

/// Profile landing screen that surfaces user identity, reputation, owned rooms, and postcard activity.
struct ProfileView: View {
    /// Sheet routes presented from profile toolbar and settings actions.
    private enum ActiveSheet: String, Identifiable {
        /// Settings menu sheet.
        case settings

        /// Feedback compose sheet.
        case feedback

        /// Tutorial walkthrough sheet opened from settings help.
        case help

        /// Edit-profile form sheet.
        case editProfile

        /// Stable identity used by `.sheet(item:)`.
        var id: String {
            rawValue
        }
    }

    /// Shared authenticated session state used across tabs.
    @EnvironmentObject private var session: UserSessionStore

    /// Current color scheme used to keep background styling consistent with app theme.
    @Environment(\.colorScheme) private var colorScheme

    /// View model that manages room/postcard profile lists and loading state.
    @StateObject private var viewModel = ProfileViewModel()

    /// Selected postcard used to push into postcard detail.
    @State private var selectedPostcard: PostcardListing? = nil

    /// Currently presented profile sheet route.
    @State private var activeSheet: ActiveSheet? = nil

    /// Deferred sheet route opened after current sheet dismisses.
    @State private var pendingSheetAfterDismiss: ActiveSheet? = nil

    /// Shows success alert after feedback submission.
    @State private var isFeedbackSubmittedAlertPresented: Bool = false

    /// Repository that submits feedback payloads.
    private let feedbackRepo = FbFeedbackRepo()

    /// Main profile screen composition and modal routing.
    var body: some View {
        NavigationStack {
            Form {
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
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                accountSection
                communitySection
                mushroomSection
                postcardSection
                signOutSection
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
                        activeSheet = .editProfile
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel(LocalizedStringKey("edit_profile_title"))
                    .accessibilityIdentifier("profile_edit_button")
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        activeSheet = .settings
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(LocalizedStringKey("settings_title"))
                    .accessibilityIdentifier("profile_settings_button")
                }
            }
            .task {
                await viewModel.loadOnAppear(session: session)
            }
            .refreshable {
                await viewModel.refreshAllProfileData(session: session, forceRefresh: true)
            }
        }
        .sheet(item: $activeSheet, onDismiss: {
            if let pendingSheetAfterDismiss, activeSheet == nil {
                activeSheet = pendingSheetAfterDismiss
                self.pendingSheetAfterDismiss = nil
            }
        }) {
            switch $0 {
            case .settings:
                settingsSheet
            case .feedback:
                FeedbackView { draft in
                    if AppTesting.isUITesting {
                        await MainActor.run {
                            isFeedbackSubmittedAlertPresented = true
                        }
                        return
                    }
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
            case .help:
                TutorialView()
            case .editProfile:
                ProfileFormView(mode: .edit)
            }
        }
        .overlay {
            if isFeedbackSubmittedAlertPresented {
                HoneyMessageBox(
                    title: NSLocalizedString("feedback_submit_success_title", comment: ""),
                    message: NSLocalizedString("feedback_submit_success_message", comment: ""),
                    buttons: [
                        HoneyMessageBoxButton(
                            id: "profile_feedback_success_done",
                            title: NSLocalizedString("common_done", comment: "")
                        ) {
                            isFeedbackSubmittedAlertPresented = false
                        }
                    ]
                )
            }
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
                    .accessibilityIdentifier("profile_display_name_value")
            }
            .padding(.vertical, 4)

            HStack {
                Text(LocalizedStringKey("profile_friend_code"))
                Spacer()
                let rawFriendCode = session.friendCode
                Text(rawFriendCode.isEmpty ? "XXXX XXXX XXXX" : FriendCode.formatted(rawFriendCode))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("profile_friend_code_value")
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
                rooms: viewModel.joinedRooms,
                isLoading: viewModel.isJoinedRoomsLoading,
                errorMessage: viewModel.joinedRoomsErrorMessage
            )
            .equatable()

            HostedRoomsSection(
                rooms: viewModel.hostedRooms,
                isLoading: viewModel.isHostedRoomsLoading,
                errorMessage: viewModel.hostedRoomsErrorMessage,
                onRoomClosed: { Task { await viewModel.loadHostedRooms(session: session, forceRefresh: true) } }
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
                postcards: viewModel.onShelfPostcards,
                pendingOrderPostcardIds: viewModel.onShelfPendingOrderPostcardIds,
                isLoading: viewModel.isOnShelfPostcardsLoading,
                errorMessage: viewModel.onShelfPostcardsErrorMessage,
                onSelectPostcard: { selectedPostcard = $0 }
            )
            .equatable()

            OrderedPostcardsSection(
                postcards: viewModel.orderedPostcards,
                isLoading: viewModel.isOrderedPostcardsLoading,
                errorMessage: viewModel.orderedPostcardsErrorMessage,
                onSelectPostcard: { selectedPostcard = $0.listing }
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

    /// Settings sheet that routes to feedback, help, and about pages.
    private var settingsSheet: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        pendingSheetAfterDismiss = .feedback
                        activeSheet = nil
                    } label: {
                        Label(LocalizedStringKey("settings_feedback_button"), systemImage: "envelope")
                    }
                    .accessibilityIdentifier("settings_feedback_button")

                    Button {
                        pendingSheetAfterDismiss = .help
                        activeSheet = nil
                    } label: {
                        Label(LocalizedStringKey("settings_help_button"), systemImage: "questionmark.circle")
                    }
                    .accessibilityIdentifier("settings_help_button")

                    NavigationLink {
                        AboutView()
                    } label: {
                        Label(LocalizedStringKey("settings_about_button"), systemImage: "info.circle")
                    }
                    .accessibilityIdentifier("settings_about_button")
                }
            }
            .navigationTitle(LocalizedStringKey("settings_title"))
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            activeSheet = nil
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityIdentifier("settings_close_button")
                }
            }
        }
    }

}
