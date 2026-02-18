//
//  LoginView.swift
//  mushroomHunter
//
//  Purpose:
//  - Implements the sign-in screen and auth entry actions.
//
//  Defined in this file:
//  - LoginView layout and sign-in trigger handlers.
//
import SwiftUI
import UIKit
import AuthenticationServices

struct LoginView: View {
    /// Shared user session used for sign-in actions and auth error/loading state.
    @EnvironmentObject private var session: UserSessionStore

    /// Color scheme used to style Apple sign-in button and background.
    @Environment(\.colorScheme) private var scheme

    /// Login screen layout with Apple/Google auth entry actions.
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Spacer()

                Image(systemName: "leaf.circle.fill")
                    .font(.system(size: 64))
                    .symbolRenderingMode(.hierarchical)

                Text(LocalizedStringKey("login_title"))
                    .font(.largeTitle.bold())

                Spacer()

                if let err = session.errorMessage {
                    Text(err)
                        .foregroundStyle(.red)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                SignInWithAppleButton(.signIn) { request in
                    session.configureAppleRequest(request)
                } onCompletion: { result in
                    Task { await session.handleAppleCompletion(result) }
                }
                .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
                .frame(height: 48)
                .disabled(session.isLoading)

                // Google sign-in entry action.
                Button {
                    guard let vc = topViewController() else {
                        session.errorMessage = NSLocalizedString("login_google_error", comment: "")
                        return
                    }
                    Task { await session.signInWithGoogle(presenting: vc) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "g.circle")
                        Text(LocalizedStringKey("login_continue_google"))
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
            .background(Theme.backgroundGradient(for: scheme))
            .navigationBarHidden(true)
        }
    }

    /// Resolves the top-most UIKit view controller required by Google Sign-In SDK presentation.
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

}
