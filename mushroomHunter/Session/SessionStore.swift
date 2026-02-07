import Foundation
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import GoogleSignIn
import UIKit
import Combine

@MainActor
final class SessionStore: ObservableObject {
    @Published var isLoggedIn: Bool = false
    @Published var displayName: String = "Ken"
    @Published var friendCode: String = ""          // ✅ NEW
    @Published var stars: Int = 0   // ⭐ Community reputation
    @Published var honey: Int = 0
    @Published var authUid: String? = nil

    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    private var authHandle: AuthStateDidChangeListenerHandle?

    // Local persistence keys (prototype-friendly)
    private let kDisplayName = "mh.displayName"
    private let kFriendCode  = "mh.friendCode"
    private let kStars = "mh.stars"
    private let kHoney = "mh.honey"

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
    }

    func updateFriendCode(_ code: String) {
        friendCode = code
        UserDefaults.standard.set(code, forKey: kFriendCode)

        // Optional: later push to Firestore users/{uid}
    }

    func updateStars(_ newValue: Int) {
        stars = max(0, newValue)
        UserDefaults.standard.set(stars, forKey: kStars)
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
    }

    // MARK: - Backend sync

    func refreshProfileFromBackend() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        do {
            let snap = try await Firestore.firestore().collection("users").document(uid).getDocument()
            guard let data = snap.data() else { return }

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
            errorMessage = "Missing Firebase clientID."
            return
        }

        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: viewController)

            guard let idToken = result.user.idToken?.tokenString else {
                errorMessage = "Missing Google ID token."
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

        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
