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
    // MARK: - Profile updates

    func updateDisplayName(_ newName: String) { // Handles display-name update flow.
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        displayName = trimmed
        persistScopedString(kDisplayName, value: trimmed)

        var fields: [String: Any] = ["displayName": trimmed]
        if shouldMarkProfileComplete() {
            isProfileComplete = true
            fields["profileComplete"] = true
        }

        Task { await syncProfileFields(fields) }
        Task { await syncHostedRoomProfile(displayName: trimmed) }
    }

    func updateFriendCode(_ code: String) { // Handles friend-code update flow.
        friendCode = code
        persistScopedString(kFriendCode, value: code)

        var fields: [String: Any] = ["friendCode": code]
        if shouldMarkProfileComplete() {
            isProfileComplete = true
            fields["profileComplete"] = true
        }

        Task { await syncProfileFields(fields) }
        Task { await syncHostedRoomProfile(friendCode: code) }
    }

    func completeProfile(name: String, friendCode: String) async { // Handles profile-completion flow.
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = friendCode.filter { $0.isNumber }
        guard !trimmedName.isEmpty, digits.count == AppConfig.Profile.friendCodeDigits else { return }

        displayName = trimmedName
        self.friendCode = digits
        isProfileComplete = true

        persistScopedString(kDisplayName, value: trimmedName)
        persistScopedString(kFriendCode, value: digits)

        await syncProfileFields([
            "displayName": trimmedName,
            "friendCode": digits,
            "profileComplete": true
        ])
        await syncHostedRoomProfile(displayName: trimmedName, friendCode: digits, stars: stars)
        await ensureUserProfile()
    }

    func updateFcmToken(_ token: String) { // Handles FCM-token update flow.
        fcmToken = token
        UserDefaults.standard.set(token, forKey: kFcmToken)

        Task {
            await syncFcmToken(token)
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
                friendCode = code
                persistScopedString(kFriendCode, value: code)
            }

            if let starsValue = data["stars"] as? Int {
                stars = max(0, starsValue)
                persistScopedInt(kStars, value: stars)
            }

            if let honeyValue = data["honey"] as? Int {
                honey = max(0, honeyValue)
                persistScopedInt(kHoney, value: honey)
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

    func syncHostedRoomProfile(displayName: String? = nil, friendCode: String? = nil, stars: Int? = nil) async { // Syncs host attendee snapshots across room attendee docs.
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

    private func shouldMarkProfileComplete() -> Bool { // Evaluates whether current profile fields satisfy completion requirements.
        let nameOK = !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let codeOK = !friendCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return nameOK && codeOK
    }
}
