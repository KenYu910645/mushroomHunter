//
//  ColorfulTag.swift
//  mushroomHunter
//
//  Purpose:
//  - Provides one shared colorful rounded-rectangle tag style reused across mushroom/postcard/profile UI.
//
import SwiftUI

/// Palette used by the shared colorful tag surface.
enum ColorfulTagTone {
    /// Attendee/flow state indicating a ready or successful state.
    case ready

    /// Attendee/flow state indicating waiting or pending response.
    case waiting

    /// Attendee/flow state indicating rejected/negative result.
    case rejected

    /// Host or host-owned contextual state.
    case host

    /// Honey balance/value state.
    case honey

    /// Stars/reputation state.
    case star

    /// Solid blue ownership marker used by pinned ownership chips.
    case ownership

    /// Foreground tint used by tag text/icons.
    var foregroundColor: Color {
        switch self {
        case .ready:
            return .green
        case .waiting:
            return .yellow
        case .rejected:
            return .red
        case .host:
            return .blue
        case .honey:
            return .orange
        case .star:
            return .yellow
        case .ownership:
            return .white
        }
    }

    /// Background tint used by the rounded tag container.
    var backgroundColor: Color {
        switch self {
        case .ready:
            return Color.green.opacity(0.14)
        case .waiting:
            return Color.yellow.opacity(0.14)
        case .rejected:
            return Color.red.opacity(0.14)
        case .host:
            return Color.blue.opacity(0.14)
        case .honey:
            return Color.orange.opacity(0.14)
        case .star:
            return Color.yellow.opacity(0.14)
        case .ownership:
            return Color.blue
        }
    }

    /// Border tint used by the rounded tag container.
    var borderColor: Color {
        switch self {
        case .ready:
            return Color.green.opacity(0.35)
        case .waiting:
            return Color.yellow.opacity(0.45)
        case .rejected:
            return Color.red.opacity(0.35)
        case .host:
            return Color.blue.opacity(0.35)
        case .honey:
            return Color.orange.opacity(0.35)
        case .star:
            return Color.yellow.opacity(0.35)
        case .ownership:
            return Color.blue
        }
    }
}

/// Shared colorful rounded-rectangle tag shell with customizable content.
struct ColorfulTag<Content: View>: View {
    /// Tone that controls foreground/background/border colors.
    let tone: ColorfulTagTone

    /// Horizontal content inset inside the rounded tag shell.
    let horizontalPadding: CGFloat

    /// Vertical content inset inside the rounded tag shell.
    let verticalPadding: CGFloat

    /// Font applied to text content inside the tag.
    let font: Font

    /// Content rendered inside the rounded tag shell.
    let content: () -> Content

    /// Creates a colorful tag using custom content.
    init(
        tone: ColorfulTagTone,
        horizontalPadding: CGFloat = 8,
        verticalPadding: CGFloat = 4,
        font: Font = .caption.weight(.semibold),
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.tone = tone
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.font = font
        self.content = content
    }

    /// Creates a colorful tag from a localized text key.
    init(
        titleKey: LocalizedStringKey,
        tone: ColorfulTagTone,
        horizontalPadding: CGFloat = 8,
        verticalPadding: CGFloat = 4,
        font: Font = .caption.weight(.semibold)
    ) where Content == Text {
        self.tone = tone
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.font = font
        self.content = {
            Text(titleKey)
        }
    }

    /// Renders the colorful rounded-rectangle tag shell.
    var body: some View {
        content()
            .font(font)
            .lineLimit(1)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .foregroundStyle(tone.foregroundColor)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tone.backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(tone.borderColor, lineWidth: 1)
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
