////
////  SessionStore.swift
////  mushroomHunter
////
////  Created by Ken on 2/2/2026.
////

import Foundation
import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import UIKit
import Combine

@MainActor
final class SessionStore: ObservableObject {
    @Published var isLoggedIn: Bool = false
    @Published var displayName: String = "Ken"
    @Published var authUid: String? = nil

    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    private var authHandle: AuthStateDidChangeListenerHandle?

    init() {
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            self.authUid = user?.uid
            self.isLoggedIn = (user != nil)
            if let user, let name = user.displayName, !name.isEmpty {
                self.displayName = name
            }
        }
    }

    deinit {
        if let handle = authHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

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
            // Start Google Sign-In
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: viewController)

            guard let idToken = result.user.idToken?.tokenString else {
                errorMessage = "Missing Google ID token."
                return
            }

            let accessToken = result.user.accessToken.tokenString

            // Exchange for Firebase credential
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)

            let authResult = try await Auth.auth().signIn(with: credential)

            self.authUid = authResult.user.uid
            self.isLoggedIn = true
            if let name = authResult.user.displayName, !name.isEmpty {
                self.displayName = name
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}


//
//import Foundation
//import Combine
//import FirebaseAuth
//
//@MainActor
//final class SessionStore: ObservableObject {
//    @Published var isLoggedIn: Bool = false
//    @Published var displayName: String = "Ken"
//    @Published var authUid: String? = nil
//
//    @Published var isLoading: Bool = false
//    @Published var errorMessage: String? = nil
//
//    private var authHandle: AuthStateDidChangeListenerHandle?
//
//    init() {
//        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
//            guard let self else { return }
//            self.authUid = user?.uid
//            self.isLoggedIn = (user != nil)
//        }
//    }
//
//    deinit {
//        if let handle = authHandle {
//            Auth.auth().removeStateDidChangeListener(handle)
//        }
//    }
//
//    func signOut() {
//        isLoading = true
//        defer { isLoading = false }
//
//        do {
//            try Auth.auth().signOut()
//            isLoggedIn = false
//            authUid = nil
//        } catch {
//            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
//        }
//    }
//}
