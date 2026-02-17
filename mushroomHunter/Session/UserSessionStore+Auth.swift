//
//  UserSessionStore+Auth.swift
//  mushroomHunter
//
//  Purpose:
//  - Owns authenticated user session state and authentication lifecycle.
//
//  Defined in this file:
//  - UserSessionStore state container, local persistence helpers, and auth flows.
//
import Foundation
import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import UIKit
import Combine
import AuthenticationServices
import CryptoKit

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

    private var authHandle: AuthStateDidChangeListenerHandle? // Firebase auth state listener handle.
    private var currentAppleNonce: String? // Temporary nonce used during Apple sign-in.

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

    func signOut() { // Handles sign-out flow.
        isLoading = true
        defer { isLoading = false }

        do {
            try Auth.auth().signOut()
            isLoggedIn = false
            authUid = nil
            resetToDefaults()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Google Sign-In then Firebase Auth.
    func signInWithGoogle(presenting viewController: UIViewController) async { // Handles Google sign-in flow.
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let clientID = FirebaseApp.app()?.options.clientID else {
            errorMessage = NSLocalizedString("session_error_missing_client_id", comment: "")
            return
        }

        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: viewController)

            guard let idToken = result.user.idToken?.tokenString else {
                errorMessage = NSLocalizedString("session_error_missing_id_token", comment: "")
                return
            }

            let accessToken = result.user.accessToken.tokenString
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)

            let authResult = try await Auth.auth().signIn(with: credential)
            authUid = authResult.user.uid
            isLoggedIn = true

            UserDefaults.standard.set(displayName, forKey: scopedKey(kDisplayName, uid: authResult.user.uid))
            await ensureUserProfile()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Configures Apple Sign-In request values.
    func configureAppleRequest(_ request: ASAuthorizationAppleIDRequest) { // Handles Apple request configuration.
        errorMessage = nil
        let nonce = randomNonceString()
        currentAppleNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
    }

    /// Completes Apple Sign-In and exchanges the credential with Firebase Auth.
    func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) async { // Handles Apple completion flow.
        isLoading = true
        defer { isLoading = false }

        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription

        case .success(let authorization):
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = NSLocalizedString("session_error_apple_credential", comment: "")
                return
            }
            guard let nonce = currentAppleNonce else {
                errorMessage = NSLocalizedString("session_error_apple_nonce", comment: "")
                return
            }
            guard let appleIDToken = appleIDCredential.identityToken else {
                errorMessage = NSLocalizedString("session_error_apple_token", comment: "")
                return
            }
            guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                errorMessage = NSLocalizedString("session_error_apple_token_format", comment: "")
                return
            }

            let credential = OAuthProvider.credential(
                providerID: .apple,
                idToken: idTokenString,
                rawNonce: nonce
            )

            do {
                let authResult = try await Auth.auth().signIn(with: credential)
                authUid = authResult.user.uid
                isLoggedIn = true
                UserDefaults.standard.set(displayName, forKey: scopedKey(kDisplayName, uid: authResult.user.uid))
            } catch {
                errorMessage = error.localizedDescription
            }

            await ensureUserProfile()
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

    private func resetToDefaults() { // Resets in-memory user state to defaults.
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

extension Notification.Name {
    static let didReceiveFcmToken = Notification.Name("mh.didReceiveFcmToken") // Notification for newly received FCM token.
    static let didOpenRoomFromPush = Notification.Name("mh.didOpenRoomFromPush") // Notification for room deep-link routing.
    static let didOpenPostcardFromLink = Notification.Name("mh.didOpenPostcardFromLink") // Notification for postcard deep-link routing.
}

// MARK: - Apple Sign-In helpers

private func randomNonceString(length: Int = 32) -> String { // Generates a cryptographically secure random nonce string.
    precondition(length > 0)
    let charset: [Character] =
        Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
    var result = ""
    var remainingLength = length

    while remainingLength > 0 {
        var randoms: [UInt8] = Array(repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
        if status != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(status)")
        }

        randoms.forEach { random in
            if remainingLength == 0 { return }
            if random < charset.count {
                result.append(charset[Int(random)])
                remainingLength -= 1
            }
        }
    }

    return result
}

private func sha256(_ input: String) -> String { // Returns the SHA-256 hex digest for the provided input string.
    let inputData = Data(input.utf8)
    let hashed = SHA256.hash(data: inputData)
    return hashed.compactMap { String(format: "%02x", $0) }.joined()
}
