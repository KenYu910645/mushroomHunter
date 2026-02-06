//
//  LoginView.swift
//  mushroomHunter
//
//  Created by Ken on 2/2/2026.
//

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

}
