//
//  TutorialCatalogView.swift
//  mushroomHunter
//
//  Purpose:
//  - Provides a help entry that lists all tutorial scenarios and replay routes.
//
import SwiftUI

/// Help page that lets users choose and replay tutorials by scenario.
struct TutorialCatalogView: View {
    /// Shared user session used for completion-state chips.
    @EnvironmentObject private var session: UserSessionStore
    /// Dismiss action for sheet presentation.
    @Environment(\.dismiss) private var dismiss

    /// Main tutorial list layout.
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(TutorialScenario.allCases) { scenario in
                        tutorialRow(for: scenario)
                    }
                } footer: {
                    Text(LocalizedStringKey("tutorial_catalog_footer"))
                }
            }
            .navigationTitle(LocalizedStringKey("tutorial_catalog_title"))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityIdentifier("tutorial_catalog_close_button")
                }
            }
        }
    }

    /// Renders one tutorial list row with replay route or "coming soon" state.
    /// - Parameter scenario: Target scenario represented by this row.
    @ViewBuilder
    private func tutorialRow(for scenario: TutorialScenario) -> some View {
        if scenario.isImplemented {
            NavigationLink {
                tutorialDestination(for: scenario)
            } label: {
                tutorialRowLabel(for: scenario)
            }
            .accessibilityIdentifier("tutorial_catalog_row_\(scenario.rawValue)")
        } else {
            HStack(spacing: 10) {
                tutorialRowLabel(for: scenario)
                Spacer(minLength: 0)
                Text(LocalizedStringKey("tutorial_catalog_coming_soon"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("tutorial_catalog_row_\(scenario.rawValue)_coming_soon")
        }
    }

    /// Shared row label for one tutorial scenario.
    /// - Parameter scenario: Target scenario represented by this row.
    private func tutorialRowLabel(for scenario: TutorialScenario) -> some View {
        VStack(alignment: .leading, spacing: 4) {
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

            Text(scenario.subtitleKey)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// Returns destination view for one implemented scenario.
    /// - Parameter scenario: Scenario selected by user.
    /// - Returns: Tutorial replay destination.
    @ViewBuilder
    private func tutorialDestination(for scenario: TutorialScenario) -> some View {
        switch scenario {
        case .mushroomBrowseFirstVisit:
            RoomBrowseView(
                session: session,
                tutorialScenarioOverride: .mushroomBrowseFirstVisit,
                onTutorialReplayFinished: { dismiss() }
            )
        case .roomPersonalFirstVisit,
             .roomHostFirstVisit,
             .postcardBrowseFirstVisit,
             .postcardBuyerFirstVisit,
             .postcardSellerFirstVisit:
            EmptyView()
        }
    }
}

#Preview {
    TutorialCatalogView()
        .environmentObject(UserSessionStore())
}
