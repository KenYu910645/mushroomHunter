//
//  ProfileSectionStateView.swift
//  mushroomHunter
//
//  Purpose:
//  - Reuses loading/error/empty/content state rendering for profile section lists.
//
import SwiftUI

/// Urgency palette used by profile status badges.
enum ProfileStatusUrgency {
    /// Stable/complete state with no urgent action.
    case success
    /// In-progress state that needs attention soon.
    case warning
    /// Blocked/failed state that needs immediate attention.
    case critical
    /// Neutral informative state.
    case neutral

    /// Foreground color for badge text.
    var foregroundColor: Color {
        switch self {
        case .success:
            return .green
        case .warning:
            return .orange
        case .critical:
            return .red
        case .neutral:
            return .blue
        }
    }

    /// Subtle background tint for rounded status badge.
    var backgroundColor: Color {
        foregroundColor.opacity(0.14)
    }

    /// Border tint to keep badge visible across list backgrounds.
    var borderColor: Color {
        foregroundColor.opacity(0.35)
    }
}

/// Rounded status badge used by profile mushroom/postcard list rows.
struct ProfileStatusBadge: View {
    /// Localized status label rendered inside badge.
    let titleKey: LocalizedStringKey

    /// Urgency palette that controls badge colors.
    let urgency: ProfileStatusUrgency

    /// Badge rendering with rounded-rectangle highlight.
    var body: some View {
        Text(titleKey)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(urgency.foregroundColor)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(urgency.backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(urgency.borderColor, lineWidth: 1)
            )
    }
}

/// Generic container that renders error, loading, empty, and content states for profile lists.
struct ProfileSectionStateView<Content: View, Empty: View>: View {
    /// Loading state for current section fetch.
    let isLoading: Bool

    /// Whether the backing collection is empty.
    let isEmpty: Bool

    /// Optional error message shown above content.
    let errorMessage: String?

    /// Localized loading label shown with a progress view.
    let loadingTextKey: LocalizedStringKey

    /// View builder for non-empty section rows.
    let content: () -> Content

    /// View builder for empty-state placeholder UI.
    let emptyContent: () -> Empty

    /// Creates state container with section-specific empty/content builders.
    init(
        isLoading: Bool,
        isEmpty: Bool,
        errorMessage: String?,
        loadingTextKey: LocalizedStringKey,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder emptyContent: @escaping () -> Empty
    ) {
        self.isLoading = isLoading
        self.isEmpty = isEmpty
        self.errorMessage = errorMessage
        self.loadingTextKey = loadingTextKey
        self.content = content
        self.emptyContent = emptyContent
    }

    /// Unified rendering for section state transitions.
    var body: some View {
        Group {
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            if isLoading && isEmpty {
                HStack {
                    ProgressView()
                    Text(loadingTextKey)
                        .foregroundStyle(.secondary)
                }
            } else if isEmpty {
                emptyContent()
            } else {
                content()
            }
        }
    }
}
