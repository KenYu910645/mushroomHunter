//
//  SessionStore.swift
//  mushroomHunter
//
//  Purpose:
//  - Owns authenticated user session state and profile/auth synchronization.
//
//  Defined in this file:
//  - SessionStore published state, auth flows, and profile persistence helpers.
//
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
    @Published var isLoggedIn: Bool = false // State or dependency property.
    @Published var displayName: String = "" // State or dependency property.
    @Published var friendCode: String = ""          // ✅ NEW
    @Published var stars: Int = 0   // ⭐ Community reputation
    @Published var honey: Int = 0 // State or dependency property.
    @Published var maxHostRoom: Int = AppConfig.Mushroom.defaultHostRoomLimit // State or dependency property.
    @Published var maxJoinRoom: Int = AppConfig.Mushroom.defaultJoinRoomLimit // State or dependency property.
    @Published var authUid: String? = nil // State or dependency property.
    @Published var fcmToken: String? = nil // State or dependency property.
    @Published var isProfileComplete: Bool = false // State or dependency property.
    @Published var isLoading: Bool = false // State or dependency property.
    @Published var errorMessage: String? = nil // State or dependency property.
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

    init() { // Initializes this type.
        // Default local profile before login; will be replaced after auth
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

    deinit {
        if let handle = authHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    // MARK: - Profile updates (used by ProfileView)

    func updateDisplayName(_ newName: String) { // Handles updateDisplayName flow.
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        displayName = trimmed
        if let uid = authUid {
            UserDefaults.standard.set(trimmed, forKey: scopedKey(kDisplayName, uid: uid))
        }
        let newComplete = !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !friendCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        isProfileComplete = isProfileComplete || newComplete

        // Optional: later push to Firebase user profile / Firestore users/{uid}
        // For Google users, you *can* update Firebase displayName:
        // Auth.auth().currentUser?.createProfileChangeRequest().displayName = trimmed ...
        var fields: [String: Any] = ["displayName": trimmed]
        if isProfileComplete {
            fields["profileComplete"] = true
        }
        Task { await syncProfileFields(fields) }
        Task { await syncHostedRoomProfile(displayName: trimmed) }
    }

    func updateFriendCode(_ code: String) { // Handles updateFriendCode flow.
        friendCode = code
        if let uid = authUid {
            UserDefaults.standard.set(code, forKey: scopedKey(kFriendCode, uid: uid))
        }
        let newComplete = !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !friendCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        isProfileComplete = isProfileComplete || newComplete

        // Optional: later push to Firestore users/{uid}
        var fields: [String: Any] = ["friendCode": code]
        if isProfileComplete {
            fields["profileComplete"] = true
        }
        Task { await syncProfileFields(fields) }
        Task { await syncHostedRoomProfile(friendCode: code) }
    }

    func completeProfile(name: String, friendCode: String) async { // Handles completeProfile flow.
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = friendCode.filter { $0.isNumber }
        guard !trimmedName.isEmpty, digits.count == AppConfig.Profile.friendCodeDigits else { return }

        displayName = trimmedName
        self.friendCode = digits
        isProfileComplete = true

        if let uid = authUid {
            UserDefaults.standard.set(trimmedName, forKey: scopedKey(kDisplayName, uid: uid))
            UserDefaults.standard.set(digits, forKey: scopedKey(kFriendCode, uid: uid))
        }

        await syncProfileFields([
            "displayName": trimmedName,
            "friendCode": digits,
            "profileComplete": true
        ])
        await syncHostedRoomProfile(displayName: trimmedName, friendCode: digits, stars: stars)
        await ensureUserProfile()
    }

    func updateStars(_ newValue: Int) { // Handles updateStars flow.
        stars = max(0, newValue)
        if let uid = authUid {
            UserDefaults.standard.set(stars, forKey: scopedKey(kStars, uid: uid))
        }
        Task { await syncProfileFields(["stars": stars]) }
        Task { await syncHostedRoomProfile(stars: stars) }
    }

    func canAffordHoney(_ amount: Int) -> Bool { // Handles canAffordHoney flow.
        guard amount >= 0 else { return false }
        return honey >= amount
    }

    @discardableResult
    func spendHoney(_ amount: Int) -> Bool { // Handles spendHoney flow.
        guard amount >= 0, honey >= amount else { return false }
        honey -= amount
        if let uid = authUid {
            UserDefaults.standard.set(honey, forKey: scopedKey(kHoney, uid: uid))
        }
        return true
    }

    func addHoney(_ amount: Int) { // Handles addHoney flow.
        guard amount > 0 else { return }
        honey += amount
        if let uid = authUid {
            UserDefaults.standard.set(honey, forKey: scopedKey(kHoney, uid: uid))
        }
        Task { await syncProfileFields(["honey": honey]) }
    }

    func updateFcmToken(_ token: String) { // Handles updateFcmToken flow.
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
                    "profileComplete": isProfileComplete,
                    "createdAt": now,
                    "updatedAt": now
                ], merge: true)
        } catch {
            print("❌ ensureUserProfile error:", error)
        }
    }

    private func syncHostedRoomProfile(displayName: String? = nil, friendCode: String? = nil, stars: Int? = nil) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        var attendeeUpdates: [String: Any] = [:]
        if let displayName {
            attendeeUpdates["name"] = displayName
        }
        if let friendCode {
            attendeeUpdates["friendCode"] = friendCode
        }
        if let stars {
            attendeeUpdates["stars"] = stars
        }

        guard !attendeeUpdates.isEmpty else { return }

        let now = Timestamp(date: Date())
        attendeeUpdates["updatedAt"] = now

        do {
            let snap = try await Firestore.firestore()
                .collectionGroup("attendees")
                .whereField("status", isEqualTo: AttendeeStatus.host.rawValue)
                .getDocuments()

            if snap.documents.isEmpty { return }

            let batch = Firestore.firestore().batch()
            for doc in snap.documents {
                guard doc.documentID == uid else { continue }
                batch.setData(attendeeUpdates, forDocument: doc.reference, merge: true)
                if let roomRef = doc.reference.parent.parent {
                    batch.updateData(["updatedAt": now], forDocument: roomRef)
                }
            }
            try await batch.commit()
        } catch {
            print("❌ syncHostedRoomProfile error:", error)
        }
    }

    // MARK: - Backend sync

    func refreshProfileFromBackend() async { // Handles refreshProfileFromBackend flow.
        guard let uid = Auth.auth().currentUser?.uid else { return }

        do {
            let snap = try await Firestore.firestore().collection("users").document(uid).getDocument()
            guard let data = snap.data() else { return }

            var needsDefaults: [String: Any] = [:]

            if let name = data["displayName"] as? String, !name.isEmpty {
                displayName = name
                if let uid = authUid {
                    UserDefaults.standard.set(name, forKey: scopedKey(kDisplayName, uid: uid))
                }
            }

            if let code = data["friendCode"] as? String {
                friendCode = code
                if let uid = authUid {
                    UserDefaults.standard.set(code, forKey: scopedKey(kFriendCode, uid: uid))
                }
            }

            if let starsValue = data["stars"] as? Int {
                stars = max(0, starsValue)
                if let uid = authUid {
                    UserDefaults.standard.set(stars, forKey: scopedKey(kStars, uid: uid))
                }
            }

            if let honeyValue = data["honey"] as? Int {
                honey = max(0, honeyValue)
                if let uid = authUid {
                    UserDefaults.standard.set(honey, forKey: scopedKey(kHoney, uid: uid))
                }
            }

            if let maxHostValue = data["maxHostRoom"] as? Int {
                maxHostRoom = max(AppConfig.Mushroom.defaultHostRoomLimit, maxHostValue)
                if let uid = authUid {
                    UserDefaults.standard.set(maxHostRoom, forKey: scopedKey(kMaxHostRoom, uid: uid))
                }
            } else {
                maxHostRoom = AppConfig.Mushroom.defaultHostRoomLimit
                if let uid = authUid {
                    UserDefaults.standard.set(maxHostRoom, forKey: scopedKey(kMaxHostRoom, uid: uid))
                }
                needsDefaults["maxHostRoom"] = maxHostRoom
            }

            if let maxJoinValue = data["maxJoinRoom"] as? Int {
                maxJoinRoom = max(AppConfig.Mushroom.defaultJoinRoomLimit, maxJoinValue)
                if let uid = authUid {
                    UserDefaults.standard.set(maxJoinRoom, forKey: scopedKey(kMaxJoinRoom, uid: uid))
                }
            } else {
                maxJoinRoom = AppConfig.Mushroom.defaultJoinRoomLimit
                if let uid = authUid {
                    UserDefaults.standard.set(maxJoinRoom, forKey: scopedKey(kMaxJoinRoom, uid: uid))
                }
                needsDefaults["maxJoinRoom"] = maxJoinRoom
            }

            let nameOK = !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let codeOK = !friendCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let computedComplete = nameOK && codeOK

            if let complete = data["profileComplete"] as? Bool, complete == true {
                isProfileComplete = true
            } else {
                isProfileComplete = isProfileComplete || computedComplete
                if isProfileComplete {
                    needsDefaults["profileComplete"] = true
                }
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

    // MARK: - Local profile

    private func resetToDefaults() {
        displayName = ""
        friendCode = ""
        stars = 0
        honey = 100
        maxHostRoom = AppConfig.Mushroom.defaultHostRoomLimit
        maxJoinRoom = AppConfig.Mushroom.defaultJoinRoomLimit
        isProfileComplete = false
    }

    private func scopedKey(_ key: String, uid: String) -> String {
        "\(key).\(uid)"
    }

    private func loadLocalProfile(for uid: String) {
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
            maxHostRoom = max(AppConfig.Mushroom.defaultHostRoomLimit, UserDefaults.standard.integer(forKey: scopedKey(kMaxHostRoom, uid: uid)))
        } else {
            maxHostRoom = AppConfig.Mushroom.defaultHostRoomLimit
        }

        if UserDefaults.standard.object(forKey: scopedKey(kMaxJoinRoom, uid: uid)) != nil {
            maxJoinRoom = max(AppConfig.Mushroom.defaultJoinRoomLimit, UserDefaults.standard.integer(forKey: scopedKey(kMaxJoinRoom, uid: uid)))
        } else {
            maxJoinRoom = AppConfig.Mushroom.defaultJoinRoomLimit
        }

        let nameOK = !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let codeOK = !friendCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        isProfileComplete = nameOK && codeOK
    }
    
    // MARK: - Auth

    func signOut() { // Handles signOut flow.
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

    /// Google Sign-In then Firebase Auth
    func signInWithGoogle(presenting viewController: UIViewController) async { // Handles signInWithGoogle flow.
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

            // Do not auto-fill display name; user must set it in Profile.
            UserDefaults.standard.set(self.displayName, forKey: self.scopedKey(self.kDisplayName, uid: authResult.user.uid))

            await ensureUserProfile()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Apple Sign-In then Firebase Auth

    func configureAppleRequest(_ request: ASAuthorizationAppleIDRequest) { // Handles configureAppleRequest flow.
        errorMessage = nil
        let nonce = randomNonceString()
        currentAppleNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
    }

    func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) async { // Handles handleAppleCompletion flow.
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

                // Do not auto-fill display name; user must set it in Profile.
                UserDefaults.standard.set(self.displayName, forKey: self.scopedKey(self.kDisplayName, uid: authResult.user.uid))
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
