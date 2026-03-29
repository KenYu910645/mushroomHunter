//
//  AccountDeletionStore.swift
//  mushroomHunter
//
//  Purpose:
//  - Coordinates the in-app account deletion flow and backend callable cleanup.
//
//  Defined in this file:
//  - AccountDeletionStore account-deletion state, callable bridge, and local session teardown.
//
import Foundation
import Combine
import FirebaseAuth
import FirebaseFunctions
import GoogleSignIn
import os

/// Shared account-deletion coordinator used by Profile settings.
@MainActor
final class AccountDeletionStore: ObservableObject {
    /// Structured logger used to trace account-deletion auth state during hard-issue debugging.
    private let logger = Logger(subsystem: "com.kenyu.mushroomHunter", category: "AccountDeletion")
    /// Published while the deletion request is running so UI can block repeated taps.
    @Published private(set) var isDeletingAccount: Bool = false
    /// User-facing error shown when account deletion fails.
    @Published var errorMessage: String? = nil

    /// Firebase callable handle used for server-side cleanup and auth deletion.
    private let functions = Functions.functions(region: "us-central1")

    /// Executes account deletion for the current user.
    /// - Parameter session: Shared session state that should return to login on success.
    /// - Returns: `true` when the account was deleted successfully.
    func deleteCurrentAccount(session: UserSessionStore) async -> Bool {
        guard isDeletingAccount == false else { return false }

        isDeletingAccount = true
        errorMessage = nil
        defer { isDeletingAccount = false }

        guard let currentUser = Auth.auth().currentUser else {
            logger.error("Delete account aborted because Firebase Auth currentUser is nil. sessionAuthUid=\(session.authUid ?? "nil", privacy: .public)")
            errorMessage = NSLocalizedString("account_delete_error_signed_out", comment: "")
            return false
        }
        let deletedUserId = currentUser.uid
        logger.info("Delete account requested. firebaseUid=\(deletedUserId, privacy: .public) sessionAuthUid=\(session.authUid ?? "nil", privacy: .public)")

        if AppTesting.isUITesting {
            GIDSignIn.sharedInstance.signOut()
            session.handleDeletedAccountLocally(deletedUserId: deletedUserId)
            return true
        }

        do {
            let tokenResult = try await currentUser.getIDTokenResult(forcingRefresh: true)
            logger.info("Delete account token refresh succeeded. authTime=\(tokenResult.authDate.description, privacy: .public) expiration=\(tokenResult.expirationDate.description, privacy: .public)")
            _ = try await functions.httpsCallable("deleteUserAccount").call([:])
            logger.info("Delete account callable completed successfully for uid=\(deletedUserId, privacy: .public)")
            GIDSignIn.sharedInstance.signOut()
            session.handleDeletedAccountLocally(deletedUserId: deletedUserId)
            return true
        } catch {
            logDeletionError(error, uid: deletedUserId)
            errorMessage = normalizedErrorMessage(from: error)
            return false
        }
    }

    /// Emits structured error diagnostics so device logs can distinguish auth, transport, and callable failures.
    /// - Parameters:
    ///   - error: Raw error thrown by Firebase Auth or Firebase Functions.
    ///   - uid: Current Firebase uid attempting deletion.
    private func logDeletionError(_ error: Error, uid: String) {
        let nsError = error as NSError
        logger.error(
            """
            Delete account failed. uid=\(uid, privacy: .public) \
            domain=\(nsError.domain, privacy: .public) \
            code=\(nsError.code, privacy: .public) \
            description=\(nsError.localizedDescription, privacy: .public)
            """
        )
    }

    /// Maps backend/function failures into user-facing account-deletion copy.
    /// - Parameter error: Raw error thrown by Firebase Functions.
    /// - Returns: Localized message safe for UI presentation.
    private func normalizedErrorMessage(from error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == AuthErrorDomain,
           let authErrorCode = AuthErrorCode(rawValue: nsError.code) {
            switch authErrorCode {
            case .requiresRecentLogin, .userTokenExpired, .invalidUserToken, .userNotFound:
                return NSLocalizedString("account_delete_error_recent_login_required", comment: "")
            default:
                break
            }
        }

        let normalizedMessage = nsError.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedMessage.uppercased().contains("UNAUTHENTICATED") {
            return NSLocalizedString("account_delete_error_recent_login_required", comment: "")
        }
        guard normalizedMessage.isEmpty == false else {
            return NSLocalizedString("account_delete_error_generic", comment: "")
        }
        return normalizedMessage
    }
}
