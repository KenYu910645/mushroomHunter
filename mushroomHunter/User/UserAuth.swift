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
import FirebaseFunctions
import GoogleSignIn
import UIKit
import AuthenticationServices
import CryptoKit

extension UserSessionStore {
    /// Firebase callable handle used by the private review-access deep-link login flow.
    private var reviewAccessFunctions: Functions {
        Functions.functions(region: "us-central1")
    }

    func signOut() { // Handles sign-out flow.
        isLoading = true
        defer { isLoading = false }

        do {
            try signOutFromAllProviders()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Google Sign-In then Firebase Auth.
    func signInWithGoogle(presenting viewController: UIViewController) async { // Handles Google sign-in flow.
        isLoading = true
        errorMessage = nil
        isDemoReviewSession = false
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
            let isReviewSessionUser = isReviewAccount(authResult.user)

            authUid = authResult.user.uid
            isLoggedIn = true
            isDemoReviewSession = isReviewSessionUser
            UserDefaults.standard.set(displayName, forKey: scopedKey(kDisplayName, uid: authResult.user.uid))
            if isReviewSessionUser {
                try await seedReviewProfileIfNeeded(from: authResult.user)
                applyReviewSessionBypassIfNeeded()
            }
            await ensureUserProfile()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Signs in through the private App Review deep link by exchanging its secret for a Firebase custom token.
    /// - Parameter payload: Parsed review-access payload extracted from the incoming URL.
    func signInWithReviewAccess(_ payload: ReviewAccessPayload) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let trimmedSecret = payload.secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedSecret.isEmpty == false else {
            errorMessage = NSLocalizedString("login_review_link_invalid", comment: "")
            return
        }

        do {
            if let currentUser = Auth.auth().currentUser,
               currentUser.uid != AppConfig.ReviewAccount.authUid {
                try signOutFromAllProviders()
            }

            if let currentUser = Auth.auth().currentUser,
               currentUser.uid == AppConfig.ReviewAccount.authUid,
               isDemoReviewSession {
                applyReviewSessionBypassIfNeeded()
                await refreshProfileFromBackend()
                return
            }

            let callableResult = try await reviewAccessFunctions
                .httpsCallable("createReviewAccessToken")
                .call([
                    "secret": trimmedSecret
                ])
            let resultData = callableResult.data as? [String: Any] ?? [:]
            let customToken = (resultData["customToken"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard customToken.isEmpty == false else {
                errorMessage = NSLocalizedString("login_review_link_invalid", comment: "")
                return
            }

            let authResult = try await Auth.auth().signIn(withCustomToken: customToken)
            authUid = authResult.user.uid
            isLoggedIn = true
            isDemoReviewSession = isReviewAccount(authResult.user)
            UserDefaults.standard.set(displayName, forKey: scopedKey(kDisplayName, uid: authResult.user.uid))
            try await seedReviewProfileIfNeeded(from: authResult.user)
            applyReviewSessionBypassIfNeeded()
            await ensureUserProfile()
        } catch {
            errorMessage = normalizedReviewAccessErrorMessage(from: error)
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
        errorMessage = nil
        isDemoReviewSession = false
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
                isDemoReviewSession = isReviewAccount(authResult.user)
                UserDefaults.standard.set(displayName, forKey: scopedKey(kDisplayName, uid: authResult.user.uid))
                if isDemoReviewSession {
                    try await seedReviewProfileIfNeeded(from: authResult.user)
                    applyReviewSessionBypassIfNeeded()
                }
            } catch {
                errorMessage = error.localizedDescription
            }

            await ensureUserProfile()
        }
    }

    /// Signs out Firebase Auth plus any cached Google provider session before auth switching.
    private func signOutFromAllProviders() throws {
        GIDSignIn.sharedInstance.signOut()
        try Auth.auth().signOut()
        isLoggedIn = false
        authUid = nil
        resetToDefaults()
    }

    /// Maps review-link auth failures into user-facing login copy.
    /// - Parameter error: Raw callable/auth error thrown during review-link sign-in.
    /// - Returns: Localized message safe for the login screen.
    private func normalizedReviewAccessErrorMessage(from error: Error) -> String {
        let nsError = error as NSError
        let normalizedMessage = nsError.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedMessage.uppercased().contains("PERMISSION_DENIED") ||
            normalizedMessage.uppercased().contains("INVALID REVIEW ACCESS LINK") {
            return NSLocalizedString("login_review_link_invalid", comment: "")
        }
        guard normalizedMessage.isEmpty == false else {
            return NSLocalizedString("login_review_link_invalid", comment: "")
        }
        return normalizedMessage
    }
}

extension Notification.Name {
    static let didReceiveFcmToken = Notification.Name("mh.didReceiveFcmToken") // Notification for newly received FCM token.
    static let didOpenRoomFromPush = Notification.Name("mh.didOpenRoomFromPush") // Notification for room deep-link routing.
    static let didOpenRoomConfirmationFromPush = Notification.Name("mh.didOpenRoomConfirmationFromPush") // Notification for room confirmation queue deep-link routing.
    static let didOpenPostcardFromLink = Notification.Name("mh.didOpenPostcardFromLink") // Notification for postcard deep-link routing.
    static let didOpenPostcardOrderFromPush = Notification.Name("mh.didOpenPostcardOrderFromPush") // Notification for postcard order deep-link routing.
    static let didOpenDailyRewardReminder = Notification.Name("mh.didOpenDailyRewardReminder") // Notification for opening the shared DailyReward sheet from push or inbox actions.
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
