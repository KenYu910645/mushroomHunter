//
//  LoginView.swift
//  mushroomHunter
//
//  Created by Ken on 2/2/2026.
//

import SwiftUI
import AuthenticationServices
import FirebaseAuth

import SwiftUI
import UIKit

struct LoginView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Spacer()

                Image(systemName: "leaf.circle.fill")
                    .font(.system(size: 64))
                    .symbolRenderingMode(.hierarchical)

                Text("Mushroom Hunter")
                    .font(.largeTitle.bold())

                Spacer()

                if let err = session.errorMessage {
                    Text(err)
                        .foregroundStyle(.red)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // Apple button can stay visible but disabled / not implemented
                Button {
                    session.errorMessage = "Apple Sign-In requires Apple Developer Program membership ($99/year)."
                } label: {
                    Text("Continue with Apple (not available)")
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(.bordered)
                .disabled(session.isLoading)

                // ✅ Google Sign-In implemented
                Button {
                    guard let vc = topViewController() else {
                        session.errorMessage = "Unable to find a view controller to present Google Sign-In."
                        return
                    }
                    Task { await session.signInWithGoogle(presenting: vc) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "g.circle")
                        Text("Continue with Google")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.isLoading)

                if session.isLoading {
                    ProgressView()
                        .padding(.top, 8)
                }

                Spacer()
            }
            .padding()
            .navigationBarHidden(true)
        }
    }

    // Simple helper to present Google UI from SwiftUI
    private func topViewController() -> UIViewController? {
        guard
            let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let window = scene.windows.first,
            var top = window.rootViewController
        else { return nil }

        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    // MARK: - Apple Sign-In -> Firebase Auth

//    private func handleAppleSignIn(result: Result<ASAuthorization, Error>) async {
//        defer { session.isLoading = false }
//
//        switch result {
//        case .failure(let error):
//            session.errorMessage = error.localizedDescription
//            return
//
//        case .success(let auth):
//            guard
//                let appleCredential = auth.credential as? ASAuthorizationAppleIDCredential
//            else {
//                session.errorMessage = "Invalid Apple credential."
//                return
//            }
//
//            guard let nonce = currentNonce else {
//                session.errorMessage = "Missing login state. Please try again."
//                return
//            }
//
//            guard let appleIDToken = appleCredential.identityToken else {
//                session.errorMessage = "Unable to fetch identity token."
//                return
//            }
//
//            guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
//                session.errorMessage = "Unable to serialize token string."
//                return
//            }
//
//            let credential = OAuthProvider.credential(
//                providerID: .apple,
//                idToken: idTokenString,
//                rawNonce: nonce
//            )
//
//            do {
//                let authResult = try await Auth.auth().signIn(with: credential)
//                session.authUid = authResult.user.uid
//                session.isLoggedIn = true
//
//                // Optional: update displayName if Apple provided it
//                // Apple only provides fullName the first time user authorizes.
//                if let fullName = appleCredential.fullName {
//                    let name = [
//                        fullName.givenName,
//                        fullName.familyName
//                    ]
//                    .compactMap { $0 }
//                    .joined(separator: " ")
//                    .trimmingCharacters(in: .whitespacesAndNewlines)
//
//                    if !name.isEmpty {
//                        session.displayName = name
//                    }
//                }
//            } catch {
//                session.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
//            }
//        }
//    }
}

