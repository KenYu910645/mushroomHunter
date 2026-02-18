//
//  TutorialView.swift
//  mushroomHunter
//
//  Purpose:
//  - Presents a one-time swipe tutorial for first-time players after profile creation.
//
//  Defined in this file:
//  - TutorialView and its supporting onboarding card model and card view.
//
import SwiftUI

/// Model used to render each onboarding tutorial card.
private struct TutorialCard: Identifiable {
    /// Stable card identity for list rendering.
    let id: Int

    /// Card title shown at the top.
    let title: String

    /// Card description explaining the value for first-time users.
    let description: String

    /// SF Symbol used as the card icon.
    let systemImage: String
}

/// Full-screen swipeable tutorial shown once after first profile completion.
struct TutorialView: View {
    /// Shared session used to persist tutorial completion state.
    @EnvironmentObject private var session: UserSessionStore

    /// Current page index in the swipeable tutorial.
    @State private var currentIndex: Int = 0

    /// Ordered tutorial cards shown to first-time users.
    private let cards: [TutorialCard] = [
        TutorialCard(
            id: 0,
            title: "Honey & Stars",
            description: "Use honey to join raids and buy postcards. Earn stars through trustworthy raid and trade actions.",
            systemImage: "drop.fill"
        ),
        TutorialCard(
            id: 1,
            title: "Join Mushroom Rooms",
            description: "Browse rooms, check target details, deposit honey, and track room status until confirmation.",
            systemImage: "person.3.fill"
        ),
        TutorialCard(
            id: 2,
            title: "Host a Room",
            description: "Create a room with target color, attribute, and size, then share your invite link or QR code.",
            systemImage: "flag.checkered.2.crossed"
        ),
        TutorialCard(
            id: 3,
            title: "Postcard Market",
            description: "Buy or sell postcards, track shipping updates, and confirm receipt to finish transactions.",
            systemImage: "mail.stack.fill"
        )
    ]

    /// Indicates whether the current page is the last tutorial card.
    private var isLastCard: Bool {
        currentIndex >= cards.count - 1
    }

    /// Main tutorial layout with swipeable cards and bottom actions.
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                TabView(selection: $currentIndex) {
                    ForEach(cards) { card in
                        TutorialCardView(card: card)
                            .padding(.horizontal, 20)
                            .tag(card.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                HStack(spacing: 12) {
                    Button("Skip") {
                        completeTutorial()
                    }
                    .buttonStyle(.bordered)

                    Button(isLastCard ? "Get Started" : "Next") {
                        if isLastCard {
                            completeTutorial()
                        } else {
                            currentIndex += 1
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.bottom, 12)
            }
            .padding(.top, 16)
            .navigationTitle("Welcome to HoneyHub")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// Persists tutorial completion and closes the full-screen cover.
    private func completeTutorial() {
        session.markOnboardingTutorialShown()
    }
}

/// Single tutorial card visual used inside the pager.
private struct TutorialCardView: View {
    /// Content model for this card.
    let card: TutorialCard

    /// Visual layout for one tutorial card.
    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 20)
            Image(systemName: card.systemImage)
                .font(.system(size: 60, weight: .semibold))
                .foregroundStyle(.green)
            Text(card.title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(card.description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            Spacer(minLength: 20)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
}

