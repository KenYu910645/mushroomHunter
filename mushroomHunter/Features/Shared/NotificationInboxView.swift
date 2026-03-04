//
//  NotificationInboxView.swift
//  mushroomHunter
//
//  Purpose:
//  - Renders the in-app notification inbox list and unread/read states.
//
//  Defined in this file:
//  - NotificationInboxView and row presentation helpers.
//
import SwiftUI

/// In-app notification inbox list that opens route actions on row tap.
struct NotificationInboxView: View {
    /// Dismiss action for this modal screen.
    @Environment(\.dismiss) private var dismiss
    /// Shared notification inbox state.
    @EnvironmentObject private var notificationInbox: NotificationInboxStore
    /// Callback fired when user opens one notification route.
    let onOpenRoute: (NotificationInboxRoute) -> Void

    /// Main inbox screen content.
    var body: some View {
        NavigationStack {
            List {
                if notificationInbox.items.isEmpty && notificationInbox.isLoadingInitialPage == false {
                    ContentUnavailableView(
                        LocalizedStringKey("notification_inbox_empty_title"),
                        systemImage: "bell.slash",
                        description: Text(LocalizedStringKey("notification_inbox_empty_message"))
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(notificationInbox.items) { item in
                        Button {
                            guard item.isActionEvent else { return }
                            onOpenRoute(item.route)
                            dismiss()
                        } label: {
                            NotificationInboxRow(item: item)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("notification_inbox_item_\(item.id)")
                        .onAppear {
                            notificationInbox.loadNextPageIfNeeded(currentItemId: item.id)
                        }
                    }

                    if notificationInbox.isLoadingNextPage {
                        HStack {
                            Spacer(minLength: 0)
                            ProgressView()
                            Spacer(minLength: 0)
                        }
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .navigationTitle(LocalizedStringKey("notification_inbox_title"))
            .overlay {
                if notificationInbox.isLoadingInitialPage {
                    ProgressView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(LocalizedStringKey("common_close")) {
                        dismiss()
                    }
                    .accessibilityIdentifier("notification_inbox_close_button")
                }

            }
        }
        .onAppear {
            notificationInbox.loadInitialPageIfNeeded()
        }
    }
}

/// One notification row with unread indicators and message summary.
private struct NotificationInboxRow: View {
    /// Notification payload rendered by this row.
    let item: NotificationInboxItem

    /// Relative receive-time text.
    private var receivedAtText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: item.receivedAt, relativeTo: Date())
    }

    /// Row UI with unread red dot + bold text.
    var body: some View {
        let isShowingPendingState = item.isActionEvent && item.isResolved == false
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(isShowingPendingState ? Color.red : Color.clear)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline)
                    .fontWeight(isShowingPendingState ? .bold : .regular)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)

                Text(item.message)
                    .font(.footnote)
                    .fontWeight(isShowingPendingState ? .semibold : .regular)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)

                Text(receivedAtText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}
