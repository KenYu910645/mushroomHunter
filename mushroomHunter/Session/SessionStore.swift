import Foundation
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import GoogleSignIn
import UIKit
import Combine
import AuthenticationServices
import CryptoKit

@MainActor
final class SessionStore: ObservableObject {
    @Published var isLoggedIn: Bool = false
    @Published var displayName: String = "Ken"
    @Published var friendCode: String = ""          // ✅ NEW
    @Published var stars: Int = 0   // ⭐ Community reputation
    @Published var honey: Int = 0
    @Published var maxHostRoom: Int = 1
    @Published var maxJoinRoom: Int = 3
    @Published var authUid: String? = nil
    @Published var fcmToken: String? = nil

    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    private var authHandle: AuthStateDidChangeListenerHandle?
    private var currentAppleNonce: String?

    // Local persistence keys (prototype-friendly)
    private let kDisplayName = "mh.displayName"
    private let kFriendCode  = "mh.friendCode"
    private let kStars = "mh.stars"
    private let kHoney = "mh.honey"
    private let kFcmToken = "mh.fcmToken"
    private let kMaxHostRoom = "mh.maxHostRoom"
    private let kMaxJoinRoom = "mh.maxJoinRoom"

    init() {
        // Load local profile for convenience (prototype)
        displayName = UserDefaults.standard.string(forKey: kDisplayName) ?? "Ken"
        friendCode  = UserDefaults.standard.string(forKey: kFriendCode) ?? ""
        stars = UserDefaults.standard.integer(forKey: kStars)
        if UserDefaults.standard.object(forKey: kHoney) == nil {
            honey = 100
            UserDefaults.standard.set(honey, forKey: kHoney)
        } else {
            honey = UserDefaults.standard.integer(forKey: kHoney)
        }
        if UserDefaults.standard.object(forKey: kMaxHostRoom) == nil {
            maxHostRoom = 1
            UserDefaults.standard.set(maxHostRoom, forKey: kMaxHostRoom)
        } else {
            maxHostRoom = max(1, UserDefaults.standard.integer(forKey: kMaxHostRoom))
        }
        if UserDefaults.standard.object(forKey: kMaxJoinRoom) == nil {
            maxJoinRoom = 3
            UserDefaults.standard.set(maxJoinRoom, forKey: kMaxJoinRoom)
        } else {
            maxJoinRoom = max(1, UserDefaults.standard.integer(forKey: kMaxJoinRoom))
        }
        fcmToken = UserDefaults.standard.string(forKey: kFcmToken)

        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }

            self.authUid = user?.uid
            self.isLoggedIn = (user != nil)

            // If Firebase provides a displayName, prefer it.
            // (You can flip this behavior later if you want local override.)
            if let user, let name = user.displayName, !name.isEmpty {
                self.displayName = name
                UserDefaults.standard.set(name, forKey: self.kDisplayName)
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

    deinit {
        if let handle = authHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    // MARK: - Profile updates (used by ProfileView)

    func updateDisplayName(_ newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        displayName = trimmed
        UserDefaults.standard.set(trimmed, forKey: kDisplayName)

        // Optional: later push to Firebase user profile / Firestore users/{uid}
        // For Google users, you *can* update Firebase displayName:
        // Auth.auth().currentUser?.createProfileChangeRequest().displayName = trimmed ...
        Task { await syncProfileFields(["displayName": trimmed]) }
    }

    func updateFriendCode(_ code: String) {
        friendCode = code
        UserDefaults.standard.set(code, forKey: kFriendCode)

        // Optional: later push to Firestore users/{uid}
        Task { await syncProfileFields(["friendCode": code]) }
    }

    func updateStars(_ newValue: Int) {
        stars = max(0, newValue)
        UserDefaults.standard.set(stars, forKey: kStars)
        Task { await syncProfileFields(["stars": stars]) }
    }

    func canAffordHoney(_ amount: Int) -> Bool {
        guard amount >= 0 else { return false }
        return honey >= amount
    }

    @discardableResult
    func spendHoney(_ amount: Int) -> Bool {
        guard amount >= 0, honey >= amount else { return false }
        honey -= amount
        UserDefaults.standard.set(honey, forKey: kHoney)
        return true
    }

    func addHoney(_ amount: Int) {
        guard amount > 0 else { return }
        honey += amount
        UserDefaults.standard.set(honey, forKey: kHoney)
        Task { await syncProfileFields(["honey": honey]) }
    }

    func updateFcmToken(_ token: String) {
        fcmToken = token
        UserDefaults.standard.set(token, forKey: kFcmToken)
        Task {
            await syncFcmToken(token)
            await ensureUserProfile()
        }
    }

    private func syncFcmToken(_ token: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await Firestore.firestore()
                .collection("users")
                .document(uid)
                .setData([
                    "fcmToken": token,
                    "updatedAt": Timestamp(date: Date())
                ], merge: true)
        } catch {
            print("❌ syncFcmToken error:", error)
        }
    }

    private func syncProfileFields(_ fields: [String: Any]) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        var data = fields
        data["updatedAt"] = Timestamp(date: Date())
        do {
            try await Firestore.firestore()
                .collection("users")
                .document(uid)
                .setData(data, merge: true)
        } catch {
            print("❌ syncProfileFields error:", error)
        }
    }

    private func ensureUserProfile() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            let now = Timestamp(date: Date())
            try await Firestore.firestore()
                .collection("users")
                .document(uid)
                .setData([
                    "displayName": displayName,
                    "friendCode": friendCode,
                    "stars": stars,
                    "honey": honey,
                    "maxHostRoom": maxHostRoom,
                    "maxJoinRoom": maxJoinRoom,
                    "createdAt": now,
                    "updatedAt": now
                ], merge: true)
        } catch {
            print("❌ ensureUserProfile error:", error)
        }
    }

    // MARK: - Backend sync

    func refreshProfileFromBackend() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        do {
            let snap = try await Firestore.firestore().collection("users").document(uid).getDocument()
            guard let data = snap.data() else { return }

            var needsDefaults: [String: Any] = [:]

            if let name = data["displayName"] as? String, !name.isEmpty {
                displayName = name
                UserDefaults.standard.set(name, forKey: kDisplayName)
            }

            if let code = data["friendCode"] as? String {
                friendCode = code
                UserDefaults.standard.set(code, forKey: kFriendCode)
            }

            if let starsValue = data["stars"] as? Int {
                stars = max(0, starsValue)
                UserDefaults.standard.set(stars, forKey: kStars)
            }

            if let honeyValue = data["honey"] as? Int {
                honey = max(0, honeyValue)
                UserDefaults.standard.set(honey, forKey: kHoney)
            }

            if let maxHostValue = data["maxHostRoom"] as? Int {
                maxHostRoom = max(1, maxHostValue)
                UserDefaults.standard.set(maxHostRoom, forKey: kMaxHostRoom)
            } else {
                maxHostRoom = 1
                UserDefaults.standard.set(maxHostRoom, forKey: kMaxHostRoom)
                needsDefaults["maxHostRoom"] = maxHostRoom
            }

            if let maxJoinValue = data["maxJoinRoom"] as? Int {
                maxJoinRoom = max(1, maxJoinValue)
                UserDefaults.standard.set(maxJoinRoom, forKey: kMaxJoinRoom)
            } else {
                maxJoinRoom = 3
                UserDefaults.standard.set(maxJoinRoom, forKey: kMaxJoinRoom)
                needsDefaults["maxJoinRoom"] = maxJoinRoom
            }

            if !needsDefaults.isEmpty {
                needsDefaults["updatedAt"] = Timestamp(date: Date())
                try await Firestore.firestore()
                    .collection("users")
                    .document(uid)
                    .setData(needsDefaults, merge: true)
            }
        } catch {
            // Keep local values if backend fetch fails.
            print("❌ refreshProfileFromBackend error:", error)
        }
    }
    
    // MARK: - Auth

    func signOut() {
        isLoading = true
        defer { isLoading = false }
        do {
            try Auth.auth().signOut()
            isLoggedIn = false
            authUid = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Google Sign-In then Firebase Auth
    func signInWithGoogle(presenting viewController: UIViewController) async {
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

            self.authUid = authResult.user.uid
            self.isLoggedIn = true

            // Prefer Firebase display name if available
            if let name = authResult.user.displayName, !name.isEmpty {
                self.displayName = name
                UserDefaults.standard.set(name, forKey: self.kDisplayName)
            } else {
                // Keep locally saved name (already loaded in init)
                UserDefaults.standard.set(self.displayName, forKey: self.kDisplayName)
            }

            await ensureUserProfile()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Apple Sign-In then Firebase Auth

    func configureAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        errorMessage = nil
        let nonce = randomNonceString()
        currentAppleNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
    }

    func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) async {
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
                self.authUid = authResult.user.uid
                self.isLoggedIn = true

                let currentDisplayName = authResult.user.displayName ?? ""
                if currentDisplayName.isEmpty {
                    if let fullName = appleIDCredential.fullName {
                        let formatter = PersonNameComponentsFormatter()
                        let nameString = formatter.string(from: fullName)
                        if !nameString.isEmpty {
                            self.displayName = nameString
                            UserDefaults.standard.set(nameString, forKey: self.kDisplayName)
                        }
                    }
                } else {
                    self.displayName = currentDisplayName
                    UserDefaults.standard.set(currentDisplayName, forKey: self.kDisplayName)
                }
            } catch {
                errorMessage = error.localizedDescription
            }

            await ensureUserProfile()
        }
    }
}

extension Notification.Name {
    static let didReceiveFcmToken = Notification.Name("mh.didReceiveFcmToken")
    static let didOpenRoomFromPush = Notification.Name("mh.didOpenRoomFromPush")
}

// MARK: - Apple Sign-In helpers

private func randomNonceString(length: Int = 32) -> String {
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

private func sha256(_ input: String) -> String {
    let inputData = Data(input.utf8)
    let hashed = SHA256.hash(data: inputData)
    return hashed.compactMap { String(format: "%02x", $0) }.joined()
}
