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

/// Login entry screen with branded icon and provider sign-in actions.
struct LoginView: View {
    /// Shared user session used for sign-in actions and auth error/loading state.
    @EnvironmentObject private var session: UserSessionStore

    /// Color scheme used to style Apple sign-in button and background.
    @Environment(\.colorScheme) private var scheme

    /// Tracks whether the current color scheme is dark mode.
    private var isDarkMode: Bool {
        scheme == .dark
    }

    /// Brand color used for Google sign-in action emphasis.
    private var googleBrandBlue: Color {
        Color(red: 66 / 255, green: 133 / 255, blue: 244 / 255)
    }

    /// Login screen layout with Apple/Google auth entry actions.
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient(for: scheme)
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    Spacer(minLength: 40)

                    VStack(spacing: 14) {
                        Image("HoneyIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 84, height: 84)
                            .padding(16)
                            .background(
                                Circle()
                                    .fill(Theme.cardBackground(for: scheme))
                            )
                            .overlay(
                                Circle()
                                    .strokeBorder(.white.opacity(isDarkMode ? 0.18 : 0.45), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(isDarkMode ? 0.35 : 0.15), radius: 14, x: 0, y: 6)

                        Text(LocalizedStringKey("login_title"))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text(LocalizedStringKey("login_subtitle"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    VStack(spacing: 12) {
                        SignInWithAppleButton(.signIn) { request in
                            session.configureAppleRequest(request)
                        } onCompletion: { result in
                            Task { await session.handleAppleCompletion(result) }
                        }
                        .signInWithAppleButtonStyle(isDarkMode ? .white : .black)
                        .frame(height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                                Image(systemName: "g.circle.fill")
                                    .font(.title3)
                                Text(LocalizedStringKey("login_continue_google"))
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                        }
                        .foregroundStyle(.white)
                        .background(googleBrandBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(.white.opacity(isDarkMode ? 0.22 : 0.3), lineWidth: 1)
                        )
                        .disabled(session.isLoading)

                        if let err = session.errorMessage {
                            Text(err)
                                .foregroundStyle(.red)
                                .font(.footnote)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 4)
                        }

                        if session.isLoading {
                            ProgressView()
                                .padding(.top, 8)
                        }
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Theme.cardBackground(for: scheme))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(.white.opacity(isDarkMode ? 0.22 : 0.45), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(isDarkMode ? 0.25 : 0.08), radius: 20, x: 0, y: 10)

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
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
