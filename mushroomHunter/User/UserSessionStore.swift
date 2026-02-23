//
//  UserSessionStore.swift
//  mushroomHunter
//
//  Purpose:
//  - Defines the shared user session state container used across the app.
//
//  Defined in this file:
//  - UserSessionStore state, lifecycle bootstrap, and shared local persistence helpers.
//
import Foundation
import FirebaseAuth
import Combine

@MainActor
final class UserSessionStore: ObservableObject {
    @Published var isLoggedIn: Bool = false // State or dependency property.
    @Published var displayName: String = "" // State or dependency property.
    @Published var friendCode: String = "" // State or dependency property.
    @Published var stars: Int = 0 // State or dependency property.
    @Published var honey: Int = 0 // State or dependency property.
    @Published var maxHostRoom: Int = AppConfig.Mushroom.defaultHostRoomLimit // State or dependency property.
    @Published var maxJoinRoom: Int = AppConfig.Mushroom.defaultJoinRoomLimit // State or dependency property.
    @Published var authUid: String? = nil // State or dependency property.
    @Published var fcmToken: String? = nil // State or dependency property.
    @Published var isProfileComplete: Bool = false // State or dependency property.
    @Published var isShowingOnboardingTutorial: Bool = false // Tracks whether the first-time tutorial sheet is currently presented.
    @Published var profileActionBadgeCount: Int = 0 // Actionable item count used by profile tab/app icon badges.
    @Published var isLoading: Bool = false // State or dependency property.
    @Published var errorMessage: String? = nil // State or dependency property.

    let kDisplayName: String = "mh.displayName" // Local persistence key.
    let kFriendCode: String = "mh.friendCode" // Local persistence key.
    let kStars: String = "mh.stars" // Local persistence key.
    let kHoney: String = "mh.honey" // Local persistence key.
    let kFcmToken: String = "mh.fcmToken" // Local persistence key.
    let kMaxHostRoom: String = "mh.maxHostRoom" // Local persistence key.
    let kMaxJoinRoom: String = "mh.maxJoinRoom" // Local persistence key.
    let kHasShownOnboardingTutorial: String = "mh.hasShownOnboardingTutorial" // Local persistence key for one-time tutorial visibility.

    var authHandle: AuthStateDidChangeListenerHandle? // Firebase auth state listener handle.
    var currentAppleNonce: String? // Temporary nonce used during Apple sign-in.
    var lastSyncedFcmTokenByUid: [String: String] = [:] // Tracks the most recently synced FCM token per uid to avoid duplicate writes.
    var isUserProfileEnsuredInCurrentSession: Bool = false // Tracks whether ensureUserProfile already wrote for the current signed-in uid.
    var lastObservedAuthUid: String? = nil // Keeps the previous auth uid so session-scoped sync guards reset when user changes.

    init() { // Initializes this type.
        resetToDefaults()
        fcmToken = UserDefaults.standard.string(forKey: kFcmToken)

        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }

            let newAuthUid = user?.uid
            let isAuthUserChanged = self.lastObservedAuthUid != newAuthUid
            if isAuthUserChanged {
                self.isUserProfileEnsuredInCurrentSession = false
                self.lastObservedAuthUid = newAuthUid
            }

            self.authUid = user?.uid
            self.isLoggedIn = (user != nil)

            if let user {
                self.loadLocalProfile(for: user.uid)
                Task { await self.refreshProfileFromBackend() }
            } else {
                self.resetToDefaults()
            }

            if let token = self.fcmToken, self.isLoggedIn {
                Task {
                    await self.syncFcmToken(token)
                    await self.ensureUserProfile()
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: .didReceiveFcmToken,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let token = notification.object as? String else { return }
            self?.updateFcmToken(token)
        }
    }

    deinit { // Cleans up retained listener resources.
        if let handle = authHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    func scopedKey(_ key: String, uid: String) -> String { // Builds a user-scoped persistence key.
        "\(key).\(uid)"
    }

    func persistScopedString(_ key: String, value: String) { // Saves a user-scoped string value locally.
        guard let uid = authUid else { return }
        UserDefaults.standard.set(value, forKey: scopedKey(key, uid: uid))
    }

    func persistScopedInt(_ key: String, value: Int) { // Saves a user-scoped integer value locally.
        guard let uid = authUid else { return }
        UserDefaults.standard.set(value, forKey: scopedKey(key, uid: uid))
    }

    func updateProfileCompletionFromFields() { // Recomputes profile-complete state from current local fields.
        let nameOK = !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let codeOK = !friendCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        isProfileComplete = nameOK && codeOK
    }

    func hasShownOnboardingTutorial() -> Bool { // Returns whether the signed-in user has already completed or skipped onboarding cards.
        guard let uid = authUid else { return false }
        return UserDefaults.standard.bool(forKey: scopedKey(kHasShownOnboardingTutorial, uid: uid))
    }

    func markOnboardingTutorialShown() { // Persists that onboarding cards were completed or skipped and closes the tutorial presentation.
        guard let uid = authUid else { return }
        UserDefaults.standard.set(true, forKey: scopedKey(kHasShownOnboardingTutorial, uid: uid))
        isShowingOnboardingTutorial = false
    }

    func resetToDefaults() { // Resets in-memory user state to defaults.
        displayName = ""
        friendCode = ""
        stars = 0
        honey = 100
        maxHostRoom = AppConfig.Mushroom.defaultHostRoomLimit
        maxJoinRoom = AppConfig.Mushroom.defaultJoinRoomLimit
        isProfileComplete = false
        isShowingOnboardingTutorial = false
        profileActionBadgeCount = 0
    }

    /// Stores a sanitized actionable badge count for profile/tab/app-icon updates.
    /// - Parameter count: Raw actionable count from profile/mushroom/postcard queries.
    func updateProfileActionBadgeCount(_ count: Int) {
        profileActionBadgeCount = max(0, count)
    }

    private func loadLocalProfile(for uid: String) { // Loads user-scoped profile values from local persistence.
        if let name = UserDefaults.standard.string(forKey: scopedKey(kDisplayName, uid: uid)) {
            displayName = name
        } else {
            displayName = ""
        }

        if let code = UserDefaults.standard.string(forKey: scopedKey(kFriendCode, uid: uid)) {
            friendCode = code
        } else {
            friendCode = ""
        }

        if UserDefaults.standard.object(forKey: scopedKey(kStars, uid: uid)) != nil {
            stars = max(0, UserDefaults.standard.integer(forKey: scopedKey(kStars, uid: uid)))
        } else {
            stars = 0
        }

        if UserDefaults.standard.object(forKey: scopedKey(kHoney, uid: uid)) != nil {
            honey = max(0, UserDefaults.standard.integer(forKey: scopedKey(kHoney, uid: uid)))
        } else {
            honey = 100
        }

        if UserDefaults.standard.object(forKey: scopedKey(kMaxHostRoom, uid: uid)) != nil {
            let value = UserDefaults.standard.integer(forKey: scopedKey(kMaxHostRoom, uid: uid))
            maxHostRoom = max(AppConfig.Mushroom.defaultHostRoomLimit, value)
        } else {
            maxHostRoom = AppConfig.Mushroom.defaultHostRoomLimit
        }

        if UserDefaults.standard.object(forKey: scopedKey(kMaxJoinRoom, uid: uid)) != nil {
            let value = UserDefaults.standard.integer(forKey: scopedKey(kMaxJoinRoom, uid: uid))
            maxJoinRoom = max(AppConfig.Mushroom.defaultJoinRoomLimit, value)
        } else {
            maxJoinRoom = AppConfig.Mushroom.defaultJoinRoomLimit
        }

        updateProfileCompletionFromFields()
    }
}
