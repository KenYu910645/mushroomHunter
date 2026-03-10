//
//  ColorfulTag.swift
//  mushroomHunter
//
//  Purpose:
//  - Provides one shared colorful rounded-rectangle tag style reused across mushroom/postcard/profile UI.
//
import SwiftUI

/// Shared salmon accent used by star/reputation tags.
private let starSalmonColor = Color(red: 0.93, green: 0.47, blue: 0.43)

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
            return starSalmonColor
        case .ownership:
            return .white
        }
    }

    /// Foreground tint used when rendering a fully solid background style.
    var solidForegroundColor: Color {
        switch self {
        case .honey, .host, .ownership:
            return .white
        case .ready:
            return .green
        case .waiting:
            return .yellow
        case .rejected:
            return .red
        case .star:
            return starSalmonColor
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
            return starSalmonColor.opacity(0.14)
        case .ownership:
            return Color.blue
        }
    }

    /// Solid background tint used by high-contrast chips over busy surfaces.
    var solidBackgroundColor: Color {
        switch self {
        case .ready:
            return .green
        case .waiting:
            return .yellow
        case .rejected:
            return .red
        case .host, .ownership:
            return .blue
        case .honey:
            return .orange
        case .star:
            return starSalmonColor
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
            return starSalmonColor.opacity(0.35)
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

    /// When true, renders a fully solid background fill for improved contrast over images.
    let isSolidBackground: Bool

    /// Optional explicit background override color used when a tag needs feature-specific contrast tuning.
    let customBackgroundColor: Color?

    /// Content rendered inside the rounded tag shell.
    let content: () -> Content

    /// Creates a colorful tag using custom content.
    init(
        tone: ColorfulTagTone,
        horizontalPadding: CGFloat = 8,
        verticalPadding: CGFloat = 4,
        font: Font = .caption.weight(.semibold),
        isSolidBackground: Bool = false,
        customBackgroundColor: Color? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.tone = tone
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.font = font
        self.isSolidBackground = isSolidBackground
        self.customBackgroundColor = customBackgroundColor
        self.content = content
    }

    /// Creates a colorful tag from a localized text key.
    init(
        titleKey: LocalizedStringKey,
        tone: ColorfulTagTone,
        horizontalPadding: CGFloat = 8,
        verticalPadding: CGFloat = 4,
        font: Font = .caption.weight(.semibold),
        isSolidBackground: Bool = false,
        customBackgroundColor: Color? = nil
    ) where Content == Text {
        self.tone = tone
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.font = font
        self.isSolidBackground = isSolidBackground
        self.customBackgroundColor = customBackgroundColor
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
            .foregroundStyle(isSolidBackground ? tone.solidForegroundColor : tone.foregroundColor)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(customBackgroundColor ?? (isSolidBackground ? tone.solidBackgroundColor : tone.backgroundColor))
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
