//
//  DailyRewardToolbarActions.swift
//  mushroomHunter
//
//  Purpose:
//  - Provides the shared calendar + bell toolbar actions used across all three tabs.
//
//  Defined in this file:
//  - DailyRewardToolbarActions shared navigation-bar button row.
//
import SwiftUI

/// Shared toolbar action row that opens DailyReward and Event Inbox sheets.
struct DailyRewardToolbarActions: View {
    /// Callback fired when the calendar button is tapped.
    let onOpenDailyReward: () -> Void
    /// Callback fired when the notification bell is tapped.
    let onOpenNotificationInbox: () -> Void
    /// True when the calendar button should show a pending DailyReward red dot.
    let isDailyRewardPending: Bool
    /// Current unread action-event count shown as the bell red dot.
    let unreadCount: Int
    /// Accessibility label applied to the bell button.
    let bellAccessibilityLabel: LocalizedStringKey
    /// Accessibility identifier applied to the bell button.
    let bellAccessibilityIdentifier: String
    /// Optional tutorial highlight target attached to the calendar button.
    let dailyRewardTutorialTarget: TutorialHighlightTarget?
    /// Optional tutorial highlight target attached to the bell button.
    let eventInboxTutorialTarget: TutorialHighlightTarget?

    /// Main toolbar row containing the calendar and bell actions.
    var body: some View {
        HStack(spacing: 16) {
            Button(action: onOpenDailyReward) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "calendar")
                    if isDailyRewardPending {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .offset(x: 4, y: -3)
                    }
                }
            }
            .accessibilityLabel(LocalizedStringKey("daily_reward_toolbar_accessibility"))
            .accessibilityValue(isDailyRewardPending ? Text("pending") : Text("none"))
            .accessibilityIdentifier("daily_reward_button")
            .tutorialHighlightAnchor(dailyRewardTutorialTarget)

            Button(action: onOpenNotificationInbox) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell")
                    if unreadCount > 0 {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .offset(x: 4, y: -3)
                    }
                }
            }
            .accessibilityLabel(bellAccessibilityLabel)
            .accessibilityIdentifier(bellAccessibilityIdentifier)
            .tutorialHighlightAnchor(eventInboxTutorialTarget)
        }
    }
}
