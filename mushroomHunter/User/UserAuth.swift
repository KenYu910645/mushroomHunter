//
//  UserAuth.swift
//  mushroomHunter
//
//  Purpose:
//  - Implements authentication-specific behavior for UserSessionStore.
//
//  Defined in this file:
//  - UserSessionStore authentication methods, auth notifications, and Apple auth helpers.
//
import Foundation
import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import UIKit
import AuthenticationServices
import CryptoKit

extension UserSessionStore {
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
}

extension Notification.Name {
    static let didReceiveFcmToken = Notification.Name("mh.didReceiveFcmToken") // Notification for newly received FCM token.
    static let didOpenRoomFromPush = Notification.Name("mh.didOpenRoomFromPush") // Notification for room deep-link routing.
    static let didOpenRoomConfirmationFromPush = Notification.Name("mh.didOpenRoomConfirmationFromPush") // Notification for room confirmation queue deep-link routing.
    static let didOpenPostcardFromLink = Notification.Name("mh.didOpenPostcardFromLink") // Notification for postcard deep-link routing.
    static let didOpenPostcardOrderFromPush = Notification.Name("mh.didOpenPostcardOrderFromPush") // Notification for postcard order deep-link routing.
    static let didReceiveActionPushBadgeUpdate = Notification.Name("mh.didReceiveActionPushBadgeUpdate") // Notification for actionable push badge refresh requests.
}

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
