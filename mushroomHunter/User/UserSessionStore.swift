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
    @Published var isLoading: Bool = false // State or dependency property.
    @Published var errorMessage: String? = nil // State or dependency property.

    let kDisplayName: String = "mh.displayName" // Local persistence key.
    let kFriendCode: String = "mh.friendCode" // Local persistence key.
    let kStars: String = "mh.stars" // Local persistence key.
    let kHoney: String = "mh.honey" // Local persistence key.
    let kFcmToken: String = "mh.fcmToken" // Local persistence key.
    let kMaxHostRoom: String = "mh.maxHostRoom" // Local persistence key.
    let kMaxJoinRoom: String = "mh.maxJoinRoom" // Local persistence key.

    var authHandle: AuthStateDidChangeListenerHandle? // Firebase auth state listener handle.
    var currentAppleNonce: String? // Temporary nonce used during Apple sign-in.

    init() { // Initializes this type.
        resetToDefaults()
        fcmToken = UserDefaults.standard.string(forKey: kFcmToken)

        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }

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

    func resetToDefaults() { // Resets in-memory user state to defaults.
        displayName = ""
        friendCode = ""
        stars = 0
        honey = 100
        maxHostRoom = AppConfig.Mushroom.defaultHostRoomLimit
        maxJoinRoom = AppConfig.Mushroom.defaultJoinRoomLimit
        isProfileComplete = false
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
