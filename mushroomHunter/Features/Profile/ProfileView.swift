//
//  ProfileView.swift
//  mushroomHunter
//
//  Purpose:
//  - Renders the profile tab and related sheets (profile edit, settings, feedback, help, about).
//  - Shows account identity and sign-out actions only; room/postcard activity lives in browse tabs.
//
import SwiftUI

/// Profile landing screen that surfaces user identity and settings actions.
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

    /// View model retained for profile badge aggregation and background profile data refresh.
    @StateObject private var viewModel = ProfileViewModel()

    /// Currently presented profile sheet route.
    @State private var activeSheet: ActiveSheet? = nil

    /// Deferred sheet route opened after current sheet dismisses.
    @State private var pendingSheetAfterDismiss: ActiveSheet? = nil

    /// Shows success alert after feedback submission.
    @State private var isFeedbackSubmittedAlertPresented: Bool = false

    /// Controls whether the sign-out confirmation message box is visible.
    @State private var isSignOutConfirmationPresented: Bool = false

    /// Repository that submits feedback payloads.
    private let feedbackRepo = FbFeedbackRepo()

    /// Main profile screen composition and modal routing.
    var body: some View {
        NavigationStack {
            Form {
                BrowseViewTopActionBar(
                    honey: session.honey,
                    stars: session.stars,
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
                signOutSection
            }
            .navigationTitle(LocalizedStringKey("profile_title"))
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundGradient(for: colorScheme))
            .toolbar {
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

            if isSignOutConfirmationPresented {
                HoneyMessageBox(
                    title: NSLocalizedString("profile_sign_out_confirm_title", comment: ""),
                    message: NSLocalizedString("profile_sign_out_confirm_message", comment: ""),
                    buttons: [
                        HoneyMessageBoxButton(
                            id: "profile_sign_out_confirm_action",
                            title: NSLocalizedString("profile_sign_out", comment: ""),
                            role: .destructive
                        ) {
                            isSignOutConfirmationPresented = false
                            session.signOut()
                        },
                        HoneyMessageBoxButton(
                            id: "profile_sign_out_cancel_action",
                            title: NSLocalizedString("common_cancel", comment: ""),
                            role: .cancel
                        ) {
                            isSignOutConfirmationPresented = false
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

    /// Section that exposes sign-out action.
    private var signOutSection: some View {
        Section {
            Button(role: .destructive) {
                isSignOutConfirmationPresented = true
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
                        pendingSheetAfterDismiss = .editProfile
                        activeSheet = nil
                    } label: {
                        Label(LocalizedStringKey("edit_profile_title"), systemImage: "pencil")
                    }
                    .accessibilityIdentifier("settings_edit_profile_button")

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
