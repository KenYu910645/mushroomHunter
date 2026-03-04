//
//  ProfileStatusBadge.swift
//  mushroomHunter
//
//  Purpose:
//  - Provides shared urgency badge and action-dot UI primitives reused by mushroom/postcard views.
//
import SwiftUI

/// Urgency palette used by rounded status badges.
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

    /// Subtle background tint for rounded status badges.
    var backgroundColor: Color {
        foregroundColor.opacity(0.14)
    }

    /// Border tint to keep badges visible on mixed backgrounds.
    var borderColor: Color {
        foregroundColor.opacity(0.35)
    }
}

/// Rounded status badge used by room and postcard row states.
struct ProfileStatusBadge: View {
    /// Localized status label rendered inside the badge.
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

/// Tiny red dot indicator used to mark actionable list rows.
struct ProfileActionDot: View {
    /// Dot diameter used for compact slot-level notification markers.
    private let dotSize: CGFloat = 8

    /// Renders the red dot marker.
    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: dotSize, height: dotSize)
            .accessibilityHidden(true)
    }
}
