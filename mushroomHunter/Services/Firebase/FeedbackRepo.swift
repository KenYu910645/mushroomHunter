//
//  FeedbackRepo.swift
//  mushroomHunter
//
//  Purpose:
//  - Repository for in-app feedback submit flow.
//
//  Related flow:
//  - Profile -> Feedback -> submit message.
//
//  Field access legend:
//  [R] Represent Read
//  [X] Represent dont care
//  [W] Represent write
//
//  Feedback submission document (`feedbackSubmissions/{submissionId}`):
//  [X] - `submissionId`: Firestore auto-generates document id; repo does not read/write id field.
//  [W] - `userId`: Writes resolved user id (explicit id or current auth uid).
//  [W] - `displayName`: Writes trimmed display name from session/form.
//  [W] - `friendCode`: Writes trimmed friend code from session/form.
//  [W] - `subject`: Writes trimmed feedback subject.
//  [W] - `message`: Writes trimmed feedback message (required non-empty).
//  [W] - `appVersion`: Writes app short version for support context.
//  [W] - `buildNumber`: Writes build number for support context.
//  [W] - `bundleId`: Writes app bundle identifier.
//  [W] - `localeIdentifier`: Writes current locale identifier.
//  [W] - `platform`: Writes fixed platform value (`iOS`).
//  [W] - `createdAt`: Writes submission timestamp.
//
import Foundation
import FirebaseAuth
import FirebaseFirestore

enum FeedbackRepoError: LocalizedError {
    case emptyMessage

    var errorDescription: String? {
        switch self {
        case .emptyMessage:
            return NSLocalizedString("feedback_submit_failed_message", comment: "")
        }
    }
}

final class FbFeedbackRepo {
    private let db = Firestore.firestore()

    func submitFeedback(
        userId: String?,
        displayName: String,
        friendCode: String,
        subject: String,
        message: String
    ) async throws {
        let explicitUserId = userId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let authUserId = Auth.auth().currentUser?.uid ?? ""
        let resolvedUserId = explicitUserId.isEmpty ? authUserId : explicitUserId

        let cleanSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanMessage.isEmpty else { throw FeedbackRepoError.emptyMessage }

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        let bundleId = Bundle.main.bundleIdentifier ?? ""

        try await db.collection("feedbackSubmissions").addDocument(data: [
            "userId": resolvedUserId,
            "displayName": displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            "friendCode": friendCode.trimmingCharacters(in: .whitespacesAndNewlines),
            "subject": cleanSubject,
            "message": cleanMessage,
            "appVersion": version,
            "buildNumber": build,
            "bundleId": bundleId,
            "localeIdentifier": Locale.current.identifier,
            "platform": "iOS",
            "createdAt": Timestamp(date: Date())
        ])
    }
}
