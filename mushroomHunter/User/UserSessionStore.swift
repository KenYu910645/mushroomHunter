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
import FirebaseFirestore

@MainActor
final class UserSessionStore: ObservableObject {
    @Published var isLoggedIn: Bool = false // State or dependency property.
    @Published var displayName: String = "" // State or dependency property.
    @Published var friendCode: String = "" // State or dependency property.
    @Published var stars: Int = 0 // State or dependency property.
    @Published var honey: Int = 0 // State or dependency property.
    @Published var maxHostRoom: Int = AppConfig.Mushroom.defaultHostRoomLimit // State or dependency property.
    @Published var maxJoinRoom: Int = AppConfig.Mushroom.defaultJoinRoomLimit // State or dependency property.
    @Published var isPremium: Bool = false // State or dependency property.
    @Published var premiumProductId: String = "" // State or dependency property.
    @Published var premiumExpirationDate: Date? = nil // State or dependency property.
    @Published var authUid: String? = nil // State or dependency property.
    @Published var fcmToken: String? = nil // State or dependency property.
    @Published var isProfileComplete: Bool = false // State or dependency property.
    @Published var isShowingOnboardingTutorial: Bool = false // Tracks whether the first-time tutorial sheet is currently presented.
    @Published var isFeatureTutorialActive: Bool = false // Indicates any interactive feature tutorial is currently active and should lock tab switching.
    @Published var isFeatureTutorialTransitionPending: Bool = false // Keeps tutorial chrome hidden while onboarding hands off into the first feature tutorial.
    @Published var isDailyRewardPending: Bool = false // Indicates whether today's Taipei DailyReward has not been claimed yet.
    @Published var isLoading: Bool = false // State or dependency property.
    @Published var errorMessage: String? = nil // State or dependency property.

    let kDisplayName: String = "mh.displayName" // Local persistence key.
    let kFriendCode: String = "mh.friendCode" // Local persistence key.
    let kStars: String = "mh.stars" // Local persistence key.
    let kHoney: String = "mh.honey" // Local persistence key.
    let kFcmToken: String = "mh.fcmToken" // Local persistence key.
    let kMaxHostRoom: String = "mh.maxHostRoom" // Local persistence key.
    let kMaxJoinRoom: String = "mh.maxJoinRoom" // Local persistence key.
    let kIsPremium: String = "mh.isPremium" // Local persistence key.
    let kPremiumProductId: String = "mh.premiumProductId" // Local persistence key.
    let kPremiumExpirationDate: String = "mh.premiumExpirationDate" // Local persistence key.
    let kHasShownOnboardingTutorial: String = "mh.hasShownOnboardingTutorial" // Local persistence key for one-time tutorial visibility.

    var authHandle: AuthStateDidChangeListenerHandle? // Firebase auth state listener handle.
    var userProfileListener: ListenerRegistration? // Live listener for the signed-in user's backend profile document.
    var currentAppleNonce: String? // Temporary nonce used during Apple sign-in.
    var lastSyncedFcmTokenByUid: [String: String] = [:] // Tracks the most recently synced FCM token per uid to avoid duplicate writes.
    var isUserProfileEnsuredInCurrentSession: Bool = false // Tracks whether ensureUserProfile already wrote for the current signed-in uid.
    var lastObservedAuthUid: String? = nil // Keeps the previous auth uid so session-scoped sync guards reset when user changes.
    private var activeFeatureTutorialCount: Int = 0 // Reference count for active feature tutorials to keep lock state consistent across nested presentations.

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
                self.bindUserProfileListener(for: user.uid)
                Task { await self.refreshProfileFromBackend() }
            } else {
                self.unbindUserProfileListener()
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
        userProfileListener?.remove()
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

    /// Saves a user-scoped boolean value locally.
    /// - Parameters:
    ///   - key: Base persistence key.
    ///   - value: Boolean value to persist for the current user.
    func persistScopedBool(_ key: String, value: Bool) {
        guard let uid = authUid else { return }
        UserDefaults.standard.set(value, forKey: scopedKey(key, uid: uid))
    }

    /// Saves a user-scoped date value locally.
    /// - Parameters:
    ///   - key: Base persistence key.
    ///   - value: Date value to persist for the current user, or `nil` to clear it.
    func persistScopedDate(_ key: String, value: Date?) {
        guard let uid = authUid else { return }
        let scopedStorageKey = scopedKey(key, uid: uid)
        if let value {
            UserDefaults.standard.set(value.timeIntervalSince1970, forKey: scopedStorageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: scopedStorageKey)
        }
    }

    /// Effective DailyReward amount for the current user entitlement state.
    var dailyRewardHoneyAmount: Int {
        isPremium ? AppConfig.DailyReward.premiumRewardHoney : AppConfig.DailyReward.rewardHoney
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
        isPremium = false
        premiumProductId = ""
        premiumExpirationDate = nil
        isProfileComplete = false
        isShowingOnboardingTutorial = false
        isFeatureTutorialActive = false
        isFeatureTutorialTransitionPending = false
        activeFeatureTutorialCount = 0
        isDailyRewardPending = false
    }

    /// Starts a live Firestore listener for the current signed-in user's profile document.
    /// - Parameter uid: Authenticated user id whose profile should drive in-memory session fields.
    private func bindUserProfileListener(for uid: String) {
        userProfileListener?.remove()
        userProfileListener = Firestore.firestore()
            .collection("users")
            .document(uid)
            .addSnapshotListener { [weak self] snapshot, error in
                guard error == nil else { return }
                guard let data = snapshot?.data() else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.applyBackendProfileSnapshot(data, uid: uid)
                }
            }
    }

    /// Stops the active Firestore profile listener when auth state changes or the store deinitializes.
    private func unbindUserProfileListener() {
        userProfileListener?.remove()
        userProfileListener = nil
    }

    /// Applies backend profile fields to local session state and persistence.
    /// - Parameters:
    ///   - data: Raw `users/{uid}` payload received from Firestore.
    ///   - uid: Signed-in user id whose scoped local cache should be updated.
    private func applyBackendProfileSnapshot(_ data: [String: Any], uid: String) {
        let previousStars = stars
        let previousHoney = honey
        if let name = data["displayName"] as? String, name.isEmpty == false {
            displayName = name
            UserDefaults.standard.set(name, forKey: scopedKey(kDisplayName, uid: uid))
        }

        if let code = data["friendCode"] as? String {
            let sanitizedFriendCode = FriendCode.digitsOnly(code)
            friendCode = sanitizedFriendCode
            UserDefaults.standard.set(sanitizedFriendCode, forKey: scopedKey(kFriendCode, uid: uid))
        }

        if let starsValue = data["stars"] as? Int {
            stars = max(0, starsValue)
            UserDefaults.standard.set(stars, forKey: scopedKey(kStars, uid: uid))
        }

        if let honeyValue = data["honey"] as? Int {
            honey = max(0, honeyValue)
            UserDefaults.standard.set(honey, forKey: scopedKey(kHoney, uid: uid))
        }

        updateProfileCompletionFromFields()
        if previousStars != stars || previousHoney != honey {
            print(
                "🔎 [UserSession] profileListener uid=\(uid) " +
                "stars \(previousStars)->\(stars) honey \(previousHoney)->\(honey)"
            )
        }
    }

    /// Marks that one interactive feature tutorial presentation started.
    /// Uses a reference count so multiple begin/end pairs remain balanced.
    func beginFeatureTutorialPresentation() {
        isFeatureTutorialTransitionPending = false
        activeFeatureTutorialCount += 1
        isFeatureTutorialActive = activeFeatureTutorialCount > 0
    }

    /// Arms tutorial chrome hiding before the destination screen appears.
    func prepareFeatureTutorialPresentation() {
        isFeatureTutorialTransitionPending = true
    }

    /// Clears a pending tutorial handoff when normal feature loading should continue instead.
    func cancelPreparedFeatureTutorialPresentation() {
        isFeatureTutorialTransitionPending = false
    }

    /// Marks that one interactive feature tutorial presentation finished.
    /// Prevents negative counts when end is called defensively on disappear.
    func endFeatureTutorialPresentation() {
        activeFeatureTutorialCount = max(0, activeFeatureTutorialCount - 1)
        isFeatureTutorialActive = activeFeatureTutorialCount > 0
    }

    /// Updates whether today's Taipei DailyReward still needs to be claimed.
    /// - Parameter isPending: True when today's reward is still available to claim.
    func updateDailyRewardPendingState(_ isPending: Bool) {
        isDailyRewardPending = isPending
    }

    /// Updates user stars locally and syncs stars/profile snapshot updates to backend.
    /// - Parameter newValue: New stars value that will be clamped to zero minimum.
    func updateStars(_ newValue: Int) {
        stars = max(0, newValue)
        persistScopedInt(kStars, value: stars)

        Task { await syncProfileFields(["stars": stars]) }
        Task { await syncHostedRoomProfile(stars: stars) }
    }

    /// Checks whether current honey balance can pay a requested amount.
    /// - Parameter amount: Honey amount to validate.
    /// - Returns: `true` when the amount is non-negative and balance is sufficient.
    func canAffordHoney(_ amount: Int) -> Bool {
        guard amount >= 0 else { return false }
        return honey >= amount
    }

    /// Deducts honey locally when balance is sufficient.
    /// - Parameter amount: Honey amount to spend.
    /// - Returns: `true` when deduction succeeds.
    @discardableResult
    func spendHoney(_ amount: Int) -> Bool {
        guard amount >= 0, honey >= amount else { return false }

        honey -= amount
        persistScopedInt(kHoney, value: honey)
        return true
    }

    /// Adds honey locally and syncs latest balance to backend.
    /// - Parameter amount: Honey amount to add.
    func addHoney(_ amount: Int) {
        guard amount > 0 else { return }

        honey += amount
        persistScopedInt(kHoney, value: honey)
        Task { await syncProfileFields(["honey": honey]) }
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

        if UserDefaults.standard.object(forKey: scopedKey(kIsPremium, uid: uid)) != nil {
            isPremium = UserDefaults.standard.bool(forKey: scopedKey(kIsPremium, uid: uid))
        } else {
            isPremium = false
        }

        if let storedProductId = UserDefaults.standard.string(forKey: scopedKey(kPremiumProductId, uid: uid)) {
            premiumProductId = storedProductId
        } else {
            premiumProductId = ""
        }

        if UserDefaults.standard.object(forKey: scopedKey(kPremiumExpirationDate, uid: uid)) != nil {
            let timestamp = UserDefaults.standard.double(forKey: scopedKey(kPremiumExpirationDate, uid: uid))
            premiumExpirationDate = Date(timeIntervalSince1970: timestamp)
        } else {
            premiumExpirationDate = nil
        }

        updateProfileCompletionFromFields()
    }

    /// Resolves whether today's DailyReward is already claimed from backend snapshot data.
    /// - Parameter data: Raw `users/{uid}` payload received from Firestore.
    /// - Returns: True when today's reward is still pending.
    func resolveIsDailyRewardPending(from data: [String: Any]) -> Bool {
        let rewardData = data["dailyReward"] as? [String: Any] ?? [:]
        let lastClaimedDayKey = (rewardData["lastClaimedDayKey"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return lastClaimedDayKey != currentDailyRewardDayKey()
    }

    /// Builds the current Taipei day key used by DailyReward business rules.
    /// - Returns: Day key in `YYYY-MM-DD` form.
    func currentDailyRewardDayKey() -> String {
        let timeZone = TimeZone(identifier: AppConfig.DailyReward.resetTimeZoneIdentifier) ?? .current
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
