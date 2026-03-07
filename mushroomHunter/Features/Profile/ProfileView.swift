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

        /// Edit-profile form sheet.
        case editProfile

        /// Stable identity used by `.sheet(item:)`.
        var id: String {
            rawValue
        }
    }

    /// Shared authenticated session state used across tabs.
    @EnvironmentObject private var session: UserSessionStore
    /// Shared notification inbox state used by the top-right bell button.
    @EnvironmentObject private var notificationInbox: EventInboxStore

    /// Current color scheme used to keep background styling consistent with app theme.
    @Environment(\.colorScheme) private var colorScheme

    /// Currently presented profile sheet route.
    @State private var activeSheet: ActiveSheet? = nil

    /// Deferred sheet route opened after current sheet dismisses.
    @State private var pendingSheetAfterDismiss: ActiveSheet? = nil
    /// Controls navigation push of tutorial catalog from profile root stack.
    @State private var isTutorialCatalogPresented: Bool = false
    /// Defers tutorial catalog push until settings sheet dismissal completes.
    @State private var isPendingTutorialCatalogAfterDismiss: Bool = false

    /// Shows success alert after feedback submission.
    @State private var isFeedbackSubmittedAlertPresented: Bool = false
    /// Controls presentation of the event inbox sheet.
    @State private var isNotificationInboxPresented: Bool = false

    /// Controls whether the sign-out confirmation message box is visible.
    @State private var isSignOutConfirmationPresented: Bool = false

    /// Repository that submits feedback payloads.
    private let feedbackRepo = FbFeedbackRepo()

    /// Main profile screen composition and modal routing.
    var body: some View {
        NavigationStack {
            Form {
                TopActionBar(
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
                settingsSection
                signOutSection
            }
            .navigationTitle(LocalizedStringKey("profile_title"))
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundGradient(for: colorScheme))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { @MainActor in
                            await notificationInbox.refreshFromServer()
                            isNotificationInboxPresented = true
                        }
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "bell")
                            if notificationInbox.unreadCount > 0 {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 8, height: 8)
                                    .offset(x: 4, y: -3)
                            }
                        }
                    }
                    .accessibilityLabel(LocalizedStringKey("browse_notification_accessibility"))
                    .accessibilityIdentifier("profile_notification_button")
                }
            }
            .navigationDestination(isPresented: $isTutorialCatalogPresented) {
                TutorialCatalogView()
            }
        }
        .sheet(isPresented: $isNotificationInboxPresented) {
            EventInboxView { route in
                routeEventInboxItem(route)
            }
            .environmentObject(notificationInbox)
        }
        .sheet(item: $activeSheet, onDismiss: {
            if let pendingSheetAfterDismiss, activeSheet == nil {
                activeSheet = pendingSheetAfterDismiss
                self.pendingSheetAfterDismiss = nil
                return
            }
            if isPendingTutorialCatalogAfterDismiss, activeSheet == nil {
                isPendingTutorialCatalogAfterDismiss = false
                isTutorialCatalogPresented = true
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
            case .editProfile:
                ProfileCreateEditView(mode: .edit)
            }
        }
        .overlay {
            if isFeedbackSubmittedAlertPresented {
                MessageBox(
                    title: NSLocalizedString("feedback_submit_success_title", comment: ""),
                    message: NSLocalizedString("feedback_submit_success_message", comment: ""),
                    buttons: [
                        MessageBoxButton(
                            id: "profile_feedback_success_done",
                            title: NSLocalizedString("common_done", comment: "")
                        ) {
                            isFeedbackSubmittedAlertPresented = false
                        }
                    ]
                )
            }

            if isSignOutConfirmationPresented {
                MessageBox(
                    title: NSLocalizedString("profile_sign_out_confirm_title", comment: ""),
                    message: NSLocalizedString("profile_sign_out_confirm_message", comment: ""),
                    buttons: [
                        MessageBoxButton(
                            id: "profile_sign_out_confirm_action",
                            title: NSLocalizedString("profile_sign_out", comment: ""),
                            role: .destructive
                        ) {
                            isSignOutConfirmationPresented = false
                            session.signOut()
                        },
                        MessageBoxButton(
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

    /// Section that exposes settings entry above sign-out.
    private var settingsSection: some View {
        Section {
            Button {
                activeSheet = .settings
            } label: {
                Text(LocalizedStringKey("settings_title"))
            }
            .accessibilityIdentifier("profile_settings_row_button")
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
                        isPendingTutorialCatalogAfterDismiss = true
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

    /// Routes a tapped event inbox row into existing app-level deep-link channels.
    /// - Parameter route: Inbox route metadata attached to the tapped row.
    private func routeEventInboxItem(_ route: EventInboxRoute) {
        switch route.kind {
        case .room:
            guard let roomId = route.roomId, roomId.isEmpty == false else { return }
            if route.isOpeningConfirmationQueue {
                NotificationCenter.default.post(name: .didOpenRoomConfirmationFromPush, object: roomId)
            } else {
                NotificationCenter.default.post(name: .didOpenRoomFromPush, object: roomId)
            }
        case .postcard:
            guard let postcardId = route.postcardId, postcardId.isEmpty == false else { return }
            if route.isOpeningOrderPage {
                NotificationCenter.default.post(
                    name: .didOpenPostcardOrderFromPush,
                    object: [
                        "postcardId": postcardId,
                        "orderId": route.orderId ?? ""
                    ]
                )
            } else {
                NotificationCenter.default.post(name: .didOpenPostcardFromLink, object: postcardId)
            }
        case .none:
            break
        }
    }

}
