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

        displayName = trimmedName
        self.friendCode = digits
        isProfileComplete = true

        persistScopedString(kDisplayName, value: trimmedName)
        persistScopedString(kFriendCode, value: digits)

        if isNameChanged || isFriendCodeChanged || isProfileCompletionChanged {
            await syncProfileFields([
                "displayName": trimmedName,
                "friendCode": digits,
                "profileComplete": true
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
            if !hasShownOnboardingTutorial() {
                isShowingOnboardingTutorial = true
            }
        }
        return true
    }

    func updateFcmToken(_ token: String) { // Handles FCM-token update flow.
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
        guard let uid = Auth.auth().currentUser?.uid else { return }

        do {
            let snap = try await Firestore.firestore().collection("users").document(uid).getDocument()
            guard let data = snap.data() else { return }

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
            if let backendFcmToken = data["fcmToken"] as? String {
                lastSyncedFcmTokenByUid[uid] = backendFcmToken
            }

            if let maxHostValue = data["maxHostRoom"] as? Int {
                maxHostRoom = max(AppConfig.Mushroom.defaultHostRoomLimit, maxHostValue)
                persistScopedInt(kMaxHostRoom, value: maxHostRoom)
            } else {
                maxHostRoom = AppConfig.Mushroom.defaultHostRoomLimit
                persistScopedInt(kMaxHostRoom, value: maxHostRoom)
                needsDefaults["maxHostRoom"] = maxHostRoom
            }

            if let maxJoinValue = data["maxJoinRoom"] as? Int {
                maxJoinRoom = max(AppConfig.Mushroom.defaultJoinRoomLimit, maxJoinValue)
                persistScopedInt(kMaxJoinRoom, value: maxJoinRoom)
            } else {
                maxJoinRoom = AppConfig.Mushroom.defaultJoinRoomLimit
                persistScopedInt(kMaxJoinRoom, value: maxJoinRoom)
                needsDefaults["maxJoinRoom"] = maxJoinRoom
            }

            if let complete = data["profileComplete"] as? Bool, complete == true {
                isProfileComplete = true
            } else {
                updateProfileCompletionFromFields()
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
            print("❌ refreshProfileFromBackend error:", error)
        }
    }

    func syncFcmToken(_ token: String) async { // Syncs FCM token to backend user document.
        guard let uid = Auth.auth().currentUser?.uid else { return }
        if lastSyncedFcmTokenByUid[uid] == token { return }

        do {
            try await Firestore.firestore()
                .collection("users")
                .document(uid)
                .setData([
                    "fcmToken": token,
                    "updatedAt": Timestamp(date: Date())
                ], merge: true)
            lastSyncedFcmTokenByUid[uid] = token
        } catch {
            print("❌ syncFcmToken error:", error)
        }
    }

    func syncProfileFields(_ fields: [String: Any]) async { // Syncs selected profile fields to backend user document.
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

    func ensureUserProfile() async { // Ensures a minimally complete backend user document exists.
        guard let uid = Auth.auth().currentUser?.uid else { return }
        if isUserProfileEnsuredInCurrentSession { return }

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
            isUserProfileEnsuredInCurrentSession = true
        } catch {
            print("❌ ensureUserProfile error:", error)
        }
    }

    func syncHostedRoomProfile(displayName: String? = nil, friendCode: String? = nil, stars: Int? = nil, fcmToken: String? = nil) async { // Syncs host attendee snapshots across room attendee docs.
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
