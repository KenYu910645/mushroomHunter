//
//  FeedbackRepo.swift
//  mushroomHunter
//
//  Purpose:
//  - Contains Firestore write operations for in-app feedback submissions.
//
//  Defined in this file:
//  - FeedbackRepo error definitions and submit helpers.
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

final class FirebaseFeedbackRepository {
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
