//
//  TutorialListView.swift
//  mushroomHunter
//
//  Purpose:
//  - Provides a help entry that lists all tutorial scenarios and replay routes.
//
import SwiftUI

/// Help page that lets users choose and replay tutorials by scenario.
struct TutorialListView: View {
    /// Shared user session used for completion-state chips.
    @EnvironmentObject private var session: UserSessionStore

    /// Main tutorial list layout.
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(TutorialScenario.allCases) { scenario in
                        tutorialRow(for: scenario)
                    }
                }
            }
            .navigationTitle(LocalizedStringKey("tutorial_catalog_title"))
        }
    }

    /// Renders one tutorial list row with replay route or "coming soon" state.
    /// - Parameter scenario: Target scenario represented by this row.
    @ViewBuilder
    private func tutorialRow(for scenario: TutorialScenario) -> some View {
        NavigationLink {
            tutorialDestination(for: scenario)
        } label: {
            tutorialRowLabel(for: scenario)
        }
        .accessibilityIdentifier("tutorial_catalog_row_\(scenario.rawValue)")
    }

    /// Shared row label for one tutorial scenario.
    /// - Parameter scenario: Target scenario represented by this row.
    private func tutorialRowLabel(for scenario: TutorialScenario) -> some View {
        HStack(spacing: 6) {
            Text(scenario.titleKey)
                .font(.body.weight(.semibold))
            if session.isTutorialScenarioCompleted(scenario) {
                Text(LocalizedStringKey("tutorial_catalog_completed_chip"))
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.green.opacity(0.2), in: Capsule())
            }
        }
    }

    /// Returns destination view for one implemented scenario.
    /// - Parameter scenario: Scenario selected by user.
    /// - Returns: Tutorial replay destination.
    @ViewBuilder
    private func tutorialDestination(for scenario: TutorialScenario) -> some View {
        TutorialReplayDestinationView(scenario: scenario)
            .environmentObject(session)
    }
}

/// Navigation destination wrapper for tutorial replay entries.
/// Uses destination-local dismiss so "Done" pops back to the tutorial list.
private struct TutorialReplayDestinationView: View {
    /// Target replay scenario selected from the catalog list.
    let scenario: TutorialScenario
    /// Shared user session propagated from catalog.
    @EnvironmentObject private var session: UserSessionStore
    /// Local dismiss action for the pushed replay destination.
    @Environment(\.dismiss) private var dismiss

    /// Builds the replay destination for one tutorial scenario.
    @ViewBuilder
    var body: some View {
        switch scenario {
        case .mushroomBrowseFirstVisit:
            RoomBrowseView(
                session: session,
                tutorialScenarioOverride: .mushroomBrowseFirstVisit,
                onTutorialReplayFinished: { dismiss() }
            )
        case .roomPersonalFirstVisit:
            RoomView(
                vm: RoomViewModel(
                    roomId: TutorialScene.RoomJoiner.replayRoomId,
                    session: session,
                    seededRole: .attendee
                ),
                tutorialScenarioOverride: .roomPersonalFirstVisit,
                onTutorialReplayFinished: { dismiss() }
            )
        case .roomHostFirstVisit:
            RoomView(
                vm: RoomViewModel(
                    roomId: TutorialScene.RoomHost.replayRoomId,
                    session: session,
                    seededRole: .host
                ),
                tutorialScenarioOverride: .roomHostFirstVisit,
                onTutorialReplayFinished: { dismiss() }
            )
        case .postcardBrowseFirstVisit:
            PostcardBrowseView(
                tutorialScenarioOverride: .postcardBrowseFirstVisit,
                onTutorialReplayFinished: { dismiss() }
            )
        case .postcardBuyerFirstVisit:
            PostcardView(
                listing: TutorialScene.PostcardBuyer.scenario.fakeListing,
                tutorialScenarioOverride: .postcardBuyerFirstVisit,
                onTutorialReplayFinished: { dismiss() }
            )
        case .postcardSellerFirstVisit:
            PostcardView(
                listing: TutorialScene.PostcardSeller.scenario.fakeListing,
                tutorialScenarioOverride: .postcardSellerFirstVisit,
                onTutorialReplayFinished: { dismiss() }
            )
        }
    }
}

#Preview {
    TutorialListView()
        .environmentObject(UserSessionStore())
}
