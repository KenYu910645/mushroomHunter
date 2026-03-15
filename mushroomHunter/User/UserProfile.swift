//
//  UserProfile.swift
//  mushroomHunter
//
//  Purpose:
//  - Manages profile state updates and backend synchronization.
//
//  Defined in this file:
//  - UserSessionStore profile mutations, Firestore profile sync, and profile refresh flows.
//
import Foundation
import FirebaseAuth
import FirebaseFirestore

extension UserSessionStore {
    /// Builds the default field set required for a complete `users/{uid}` document.
    /// - Parameter now: Shared timestamp for one ensure transaction pass.
    /// - Returns: Default user-profile fields written on first creation or missing-field repair.
    private func defaultUserProfileFields(now: Timestamp) -> [String: Any] {
        [
            "displayName": displayName,
            "friendCode": friendCode,
            "stars": stars,
            "honey": honey,
            "maxHostRoom": maxHostRoom,
            "maxJoinRoom": maxJoinRoom,
            "isPremium": false,
            "premiumProductId": "",
            "localeIdentifier": currentLocaleIdentifier,
            "isProfileComplete": isProfileComplete,
            "createdAt": now
        ]
    }

    /// Current device locale identifier used for server-side event snapshot localization.
    private var currentLocaleIdentifier: String {
        Locale.current.identifier
    }

    /// Returns whether the provided premium entitlement is still active at the current time.
    /// - Parameters:
    ///   - isPremiumFlag: Stored backend premium flag.
    ///   - expirationDate: Stored backend expiration timestamp.
    /// - Returns: `true` when the entitlement is marked premium and not expired.
    private func isPremiumEntitlementActive(
        isPremiumFlag: Bool,
        expirationDate: Date?
    ) -> Bool {
        guard isPremiumFlag else { return false }
        guard let expirationDate else { return false }
        return expirationDate > Date()
    }

    /// Applies premium entitlement fields and derives effective room limits for the session.
    /// - Parameters:
    ///   - isPremiumFlag: Stored backend premium flag.
    ///   - productId: StoreKit product id currently linked to the user.
    ///   - expirationDate: Premium subscription expiration date when present.
    ///   - maxHostRoomValue: Backend fallback host-room limit field.
    ///   - maxJoinRoomValue: Backend fallback joined-room limit field.
    private func applyPremiumState(
        isPremiumFlag: Bool,
        productId: String,
        expirationDate: Date?,
        maxHostRoomValue: Int?,
        maxJoinRoomValue: Int?
    ) {
        let isEntitlementActive = isPremiumEntitlementActive(
            isPremiumFlag: isPremiumFlag,
            expirationDate: expirationDate
        )

        isPremium = isEntitlementActive
        premiumProductId = productId
        premiumExpirationDate = expirationDate

        persistScopedBool(kIsPremium, value: isPremium)
        persistScopedString(kPremiumProductId, value: productId)
        persistScopedDate(kPremiumExpirationDate, value: expirationDate)

        if isEntitlementActive {
            maxHostRoom = AppConfig.Premium.premiumHostRoomLimit
            maxJoinRoom = AppConfig.Premium.premiumJoinRoomLimit
        } else {
            let backendHostLimit = maxHostRoomValue ?? AppConfig.Mushroom.defaultHostRoomLimit
            let backendJoinLimit = maxJoinRoomValue ?? AppConfig.Mushroom.defaultJoinRoomLimit
            maxHostRoom = max(AppConfig.Mushroom.defaultHostRoomLimit, backendHostLimit)
            maxJoinRoom = max(AppConfig.Mushroom.defaultJoinRoomLimit, backendJoinLimit)
        }

        persistScopedInt(kMaxHostRoom, value: maxHostRoom)
        persistScopedInt(kMaxJoinRoom, value: maxJoinRoom)
    }
    /// Source context for a profile save operation.
    enum ProfileSaveSource {
        /// Save originated from first-time onboarding completion.
        case onboarding

        /// Save originated from in-app profile editing.
        case edit
    }

    // MARK: - Profile updates

    /// Saves profile fields and syncs local/backend room snapshots.
    /// - Returns: `true` when input passed validation and save work completed.
    func saveProfile(name: String, friendCode: String, source: ProfileSaveSource) async -> Bool { // Handles shared profile-save flow.
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = FriendCode.digitsOnly(friendCode)
        guard !trimmedName.isEmpty, FriendCode.validationError(digits) == nil else { return false }
        let isNameChanged = displayName != trimmedName
        let isFriendCodeChanged = self.friendCode != digits
        let isProfileCompletionChanged = !isProfileComplete
        let isOnboardingTutorialPending = (
            source == .onboarding &&
            AppTesting.isUITesting == false &&
            !isTutorialScenarioCompleted(.mushroomBrowseFirstVisit)
        )

        if isOnboardingTutorialPending {
            prepareFeatureTutorialPresentation()
        }

        displayName = trimmedName
        self.friendCode = digits
        isProfileComplete = true

        persistScopedString(kDisplayName, value: trimmedName)
        persistScopedString(kFriendCode, value: digits)

        if isNameChanged || isFriendCodeChanged || isProfileCompletionChanged {
            if AppTesting.isUITesting {
                return true
            }
            await syncProfileFields([
                "displayName": trimmedName,
                "friendCode": digits,
                "isProfileComplete": true
            ])
        }
        if isNameChanged || isFriendCodeChanged {
            await syncHostedRoomProfile(
                displayName: isNameChanged ? trimmedName : nil,
                friendCode: isFriendCodeChanged ? digits : nil,
                stars: nil
            )
        }
        if source == .onboarding {
            await ensureUserProfile()
        }
        return true
    }

    func updateFcmToken(_ token: String) { // Handles FCM-token update flow.
        if AppTesting.isUITesting { return }
        if fcmToken == token { return }
        fcmToken = token
        UserDefaults.standard.set(token, forKey: kFcmToken)

        Task {
            await syncFcmToken(token)
            await syncHostedRoomProfile(fcmToken: token)
            await ensureUserProfile()
        }
    }

    func refreshProfileFromBackend() async { // Handles backend profile refresh flow.
        if AppTesting.isUITesting { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }

        do {
            let snap = try await Firestore.firestore().collection("users").document(uid).getDocument()
            guard let data = snap.data() else { return }
            let backendStars = data["stars"] as? Int ?? -1
            let backendHoney = data["honey"] as? Int ?? -1
            print("🔎 [UserProfile] refreshProfileFromBackend uid=\(uid) backendStars=\(backendStars) backendHoney=\(backendHoney)")

            var needsDefaults: [String: Any] = [:]

            if let name = data["displayName"] as? String, !name.isEmpty {
                displayName = name
                persistScopedString(kDisplayName, value: name)
            }

            if let code = data["friendCode"] as? String {
                let sanitizedFriendCode = FriendCode.digitsOnly(code)
                friendCode = sanitizedFriendCode
                persistScopedString(kFriendCode, value: sanitizedFriendCode)
            }

            if let starsValue = data["stars"] as? Int {
                stars = max(0, starsValue)
                persistScopedInt(kStars, value: stars)
            }

            if let honeyValue = data["honey"] as? Int {
                honey = max(0, honeyValue)
                persistScopedInt(kHoney, value: honey)
            }
            updateDailyRewardPendingState(resolveIsDailyRewardPending(from: data))
            if let backendFcmToken = data["fcmToken"] as? String {
                lastSyncedFcmTokenByUid[uid] = backendFcmToken
            }

            let premiumProductId = (data["premiumProductId"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let premiumExpirationDate = (data["premiumExpirationAt"] as? Timestamp)?.dateValue()
            let backendPremiumFlag = data["isPremium"] as? Bool ?? false
            let maxHostValue = data["maxHostRoom"] as? Int
            let maxJoinValue = data["maxJoinRoom"] as? Int

            applyPremiumState(
                isPremiumFlag: backendPremiumFlag,
                productId: premiumProductId,
                expirationDate: premiumExpirationDate,
                maxHostRoomValue: maxHostValue,
                maxJoinRoomValue: maxJoinValue
            )

            if maxHostValue == nil {
                needsDefaults["maxHostRoom"] = maxHostRoom
            }

            if maxJoinValue == nil {
                needsDefaults["maxJoinRoom"] = maxJoinRoom
            }

            if let complete = (data["isProfileComplete"] as? Bool) ?? (data["profileComplete"] as? Bool), complete == true {
                isProfileComplete = true
            } else {
                updateProfileCompletionFromFields()
                if isProfileComplete {
                    needsDefaults["isProfileComplete"] = true
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
            print("❌ refreshProfileFromBackend error:", error)
        }
    }

    func syncFcmToken(_ token: String) async { // Syncs FCM token to backend user document.
        if AppTesting.isUITesting { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        if lastSyncedFcmTokenByUid[uid] == token { return }

        do {
            try await Firestore.firestore()
                .collection("users")
                .document(uid)
                .setData([
                    "fcmToken": token,
                    "localeIdentifier": currentLocaleIdentifier,
                    "updatedAt": Timestamp(date: Date())
                ], merge: true)
            lastSyncedFcmTokenByUid[uid] = token
        } catch {
            print("❌ syncFcmToken error:", error)
        }
    }

    func syncProfileFields(_ fields: [String: Any]) async { // Syncs selected profile fields to backend user document.
        if AppTesting.isUITesting { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }

        var data = fields
        data["localeIdentifier"] = currentLocaleIdentifier
        data["updatedAt"] = Timestamp(date: Date())
        if fields.keys.contains("stars") || fields.keys.contains("honey") {
            print("🔎 [UserProfile] syncProfileFields uid=\(uid) payload=\(data)")
        }

        do {
            try await Firestore.firestore()
                .collection("users")
                .document(uid)
                .setData(data, merge: true)
        } catch {
            print("❌ syncProfileFields error:", error)
        }
    }

    func ensureUserProfile() async { // Ensures a minimally complete backend user document exists.
        if AppTesting.isUITesting { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        if isUserProfileEnsuredInCurrentSession { return }

        do {
            let now = Timestamp(date: Date())
            let userRef = Firestore.firestore().collection("users").document(uid)
            _ = try await Firestore.firestore().runTransaction { [self] transaction, errorPointer in
                let userSnapshot: DocumentSnapshot
                do {
                    userSnapshot = try transaction.getDocument(userRef)
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }

                if userSnapshot.exists == false {
                    var newUserData = self.defaultUserProfileFields(now: now)
                    newUserData["updatedAt"] = now
                    print("🔎 [UserProfile] ensureUserProfile create uid=\(uid) stars=\(self.stars) honey=\(self.honey)")
                    transaction.setData(newUserData, forDocument: userRef)
                    return nil
                }

                let existingData = userSnapshot.data() ?? [:]
                var missingFields: [String: Any] = [:]
                let defaultFields = self.defaultUserProfileFields(now: now)

                for (field, defaultValue) in defaultFields where existingData[field] == nil {
                    missingFields[field] = defaultValue
                }

                guard missingFields.isEmpty == false else { return nil }
                missingFields["updatedAt"] = now
                print("🔎 [UserProfile] ensureUserProfile fill-missing uid=\(uid) fields=\(missingFields)")
                transaction.setData(missingFields, forDocument: userRef, merge: true)
                return nil
            }
            isUserProfileEnsuredInCurrentSession = true
        } catch {
            print("❌ ensureUserProfile error:", error)
        }
    }

    func syncHostedRoomProfile(displayName: String? = nil, friendCode: String? = nil, stars: Int? = nil, fcmToken: String? = nil) async { // Syncs host attendee snapshots across room attendee docs.
        if AppTesting.isUITesting { return }
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
        if let fcmToken {
            attendeeUpdates["fcmToken"] = fcmToken
        }

        guard !attendeeUpdates.isEmpty else { return }

        let now = Timestamp(date: Date())
        attendeeUpdates["updatedAt"] = now
        var roomUpdates: [String: Any] = [
            "updatedAt": now
        ]
        if let fcmToken {
            roomUpdates["hostFcmToken"] = fcmToken
        }

        do {
            let hostedRoomsSnap = try await Firestore.firestore()
                .collection("rooms")
                .whereField("hostUid", isEqualTo: uid)
                .getDocuments()

            let batch = Firestore.firestore().batch()
            var isHasAnyUpdateTarget = false
            for roomDoc in hostedRoomsSnap.documents {
                let roomRef = roomDoc.reference
                let hostAttendeeRef = roomRef.collection("attendees").document(uid)
                batch.setData(attendeeUpdates, forDocument: hostAttendeeRef, merge: true)
                batch.updateData(roomUpdates, forDocument: roomRef)
                isHasAnyUpdateTarget = true
            }

            if !isHasAnyUpdateTarget { return }
            try await batch.commit()
        } catch {
            print("❌ syncHostedRoomProfile error:", error)
        }
    }
}
