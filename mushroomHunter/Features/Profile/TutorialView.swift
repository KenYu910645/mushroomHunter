//
//  TutorialView.swift
//  mushroomHunter
//
//  Purpose:
//  - Presents a one-time swipe tutorial for first-time players after profile creation.
//
//  Defined in this file:
//  - TutorialView and supporting models for screenshot highlights, auto arrows, and text callouts.
//
import SwiftUI
import UIKit

/// Shape type used for highlight overlays in tutorial screenshots.
private enum TutorialHighlightShape {
    /// Circular highlight around a target area.
    case circle

    /// Rounded-rectangle highlight around a target area.
    case rectangle
}

/// Target highlight descriptor used by each callout.
private struct TutorialHighlight: Identifiable {
    /// Stable identity used by SwiftUI lists.
    let id: Int

    /// Highlight shape displayed on screenshot.
    let shape: TutorialHighlightShape

    /// Horizontal center in normalized coordinates (0...1).
    let x: CGFloat

    /// Vertical center in normalized coordinates (0...1).
    let y: CGFloat

    /// Highlight width in normalized image-width units (0...1).
    let widthRatio: CGFloat

    /// Highlight height in normalized image-height units (0...1).
    let heightRatio: CGFloat

    /// Stroke color used by highlight and auto arrow.
    let color: Color
}

/// Text label descriptor for tutorial callouts.
private struct TutorialLabel {
    /// Label center X in normalized coordinates (0...1).
    let x: CGFloat

    /// Label center Y in normalized coordinates (0...1).
    let y: CGFloat

    /// Label text shown to users.
    let text: String
}

/// One callout item composed of a highlight and its label.
private struct TutorialCallout: Identifiable {
    /// Stable identity used by SwiftUI lists.
    let id: Int

    /// Highlight target shown on screenshot.
    let highlight: TutorialHighlight

    /// Text bubble shown near the target.
    let label: TutorialLabel
}

/// Model used to render each tutorial card.
private struct TutorialCard: Identifiable {
    /// Stable card identity for list rendering.
    let id: Int

    /// Card description explaining the value for first-time users.
    let description: String

    /// Screenshot asset name stored in `Assets.xcassets`.
    let imageName: String

    /// Callouts shown on top of screenshot.
    let callouts: [TutorialCallout]
}

/// Full-screen swipeable tutorial shown once after first profile completion.
struct TutorialView: View {
    /// Shared session used to persist tutorial completion state.
    @EnvironmentObject private var session: UserSessionStore

    /// Dismiss action for modal presentations opened from profile settings.
    @Environment(\.dismiss) private var dismiss

    /// Current page index in the swipeable tutorial.
    @State private var currentIndex: Int = 0

    /// Ordered tutorial cards shown to first-time users.
    private let cards: [TutorialCard] = [
        TutorialCard(
            id: 0,
            description: "Use this screen to browse raids, open room details, and join with honey deposit.",
            imageName: "Mushroom",
            callouts: [
                TutorialCallout(
                    id: 0,
                    highlight: TutorialHighlight(
                        id: 0,
                        shape: .circle,
                        x: 0.92,
                        y: 0.25,
                        widthRatio: 0.13,
                        heightRatio: 0.1,
                        color: .red
                    ),
                    label: TutorialLabel(x: 0.6, y: 0.17, text: "Host Mushroom Raid")
                ),
                TutorialCallout(
                    id: 1,
                    highlight: TutorialHighlight(
                        id: 1,
                        shape: .rectangle,
                        x: 0.13,
                        y: 0.25,
                        widthRatio: 0.25,
                        heightRatio: 0.05,
                        color: .red
                    ),
                    label: TutorialLabel(x: 0.50, y: 0.25, text: "Your honey")
                ),
                TutorialCallout(
                    id: 2,
                    highlight: TutorialHighlight(
                        id: 2,
                        shape: .rectangle,
                        x: 0.5,
                        y: 0.47,
                        widthRatio: 0.9,
                        heightRatio: 0.12,
                        color: .red
                    ),
                    label: TutorialLabel(x: 0.50, y: 0.58, text: "Tap to join a mushroom raid")
                ),
                TutorialCallout(
                    id: 3,
                    highlight: TutorialHighlight(
                        id: 3,
                        shape: .circle,
                        x: 0.23,
                        y: 0.92,
                        widthRatio: 0.25,
                        heightRatio: 0.2,
                        color: .red
                    ),
                    label: TutorialLabel(x: 0.50, y: 0.8, text: "Mushroom Raid List")
                )
            ]
        ),
        TutorialCard(
            id: 1,
            description: "Browse listings, open details, and buy/sell with shipping status updates.",
            imageName: "Postcard",
            callouts: [
                TutorialCallout(
                    id: 0,
                    highlight: TutorialHighlight(
                        id: 0,
                        shape: .rectangle,
                        x: 0.50,
                        y: 0.40,
                        widthRatio: 0.42,
                        heightRatio: 0.24,
                        color: .orange
                    ),
                    label: TutorialLabel(x: 0.26, y: 0.16, text: "Search and filter here")
                )
            ]
        ),
        TutorialCard(
            id: 2,
            description: "Manage your account, review your activity, and update display name or friend code.",
            imageName: "Profile",
            callouts: [
                TutorialCallout(
                    id: 0,
                    highlight: TutorialHighlight(
                        id: 0,
                        shape: .circle,
                        x: 0.50,
                        y: 0.18,
                        widthRatio: 0.18,
                        heightRatio: 0.18,
                        color: .blue
                    ),
                    label: TutorialLabel(x: 0.74, y: 0.34, text: "Your identity and stats")
                )
            ]
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
                .indexViewStyle(.page(backgroundDisplayMode: .always))

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
        dismiss()
    }
}

/// Single tutorial card visual used inside the pager.
private struct TutorialCardView: View {
    /// Content model for this card.
    let card: TutorialCard

    /// Visual layout for one tutorial card.
    var body: some View {
        VStack(spacing: 12) {
            TutorialAnnotatedImageView(card: card)
                .frame(maxWidth: .infinity)
                .frame(height: 560)
            Text(card.description)
                .font(.body)
                .foregroundStyle(card.id == 0 ? .red : .secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .padding(18)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
}

/// Screenshot renderer that draws highlights, labels, and auto-computed arrows.
private struct TutorialAnnotatedImageView: View {
    /// Card content containing screenshot and callout payload.
    let card: TutorialCard

    /// Image aspect ratio used by iPhone screenshots to keep coordinates stable.
    private let imageAspectRatio: CGFloat = 9.0 / 19.5

    /// Visual layout that keeps overlays aligned with the rendered screenshot frame.
    var body: some View {
        GeometryReader { proxy in
            let frame = fittedImageFrame(in: proxy.size)
            ZStack(alignment: .topLeading) {
                screenshotImage
                    .resizable()
                    .scaledToFit()
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)

                ForEach(card.callouts) { callout in
                    highlightView(callout.highlight, in: frame)
                }

                ForEach(card.callouts) { callout in
                    let arrowStart = labelPoint(for: callout.label, in: frame)
                    let arrowEnd = closestPointOnHighlightBorder(from: arrowStart, highlight: callout.highlight, frame: frame)
                    TutorialArrowShape(start: arrowStart, end: arrowEnd)
                        .stroke(callout.highlight.color, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }

                ForEach(card.callouts) { callout in
                    labelView(callout.label, in: frame, textColor: card.id == 0 ? .red : .white)
                }
            }
        }
    }

    /// Renders a highlight shape using normalized coordinates.
    private func highlightView(_ highlight: TutorialHighlight, in frame: CGRect) -> some View {
        let width = frame.width * highlight.widthRatio
        let height = frame.height * highlight.heightRatio
        let center = CGPoint(
            x: frame.minX + (frame.width * highlight.x),
            y: frame.minY + (frame.height * highlight.y)
        )

        return Group {
            switch highlight.shape {
            case .circle:
                Circle()
                    .stroke(highlight.color, lineWidth: 3)
                    .frame(width: width, height: width)
                    .position(center)
            case .rectangle:
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(highlight.color, lineWidth: 3)
                    .frame(width: width, height: height)
                    .position(center)
            }
        }
    }

    /// Renders a callout text label at normalized coordinates.
    private func labelView(_ label: TutorialLabel, in frame: CGRect, textColor: Color) -> some View {
        Text(label.text)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.72))
            .foregroundStyle(textColor)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .position(labelPoint(for: label, in: frame))
    }

    /// Converts label normalized coordinates into real image-frame coordinates.
    private func labelPoint(for label: TutorialLabel, in frame: CGRect) -> CGPoint {
        CGPoint(
            x: frame.minX + (frame.width * label.x),
            y: frame.minY + (frame.height * label.y)
        )
    }

    /// Computes closest point on highlight border to auto-place arrow head.
    private func closestPointOnHighlightBorder(from point: CGPoint, highlight: TutorialHighlight, frame: CGRect) -> CGPoint {
        let center = CGPoint(
            x: frame.minX + (frame.width * highlight.x),
            y: frame.minY + (frame.height * highlight.y)
        )
        let width = frame.width * highlight.widthRatio
        let height = frame.height * highlight.heightRatio

        switch highlight.shape {
        case .circle:
            let radius = max(width / 2, 1)
            let dx = point.x - center.x
            let dy = point.y - center.y
            let distance = max(sqrt(dx * dx + dy * dy), 1)
            return CGPoint(
                x: center.x + (dx / distance) * radius,
                y: center.y + (dy / distance) * radius
            )
        case .rectangle:
            let minX = center.x - width / 2
            let maxX = center.x + width / 2
            let minY = center.y - height / 2
            let maxY = center.y + height / 2

            let nearestX = min(max(point.x, minX), maxX)
            let nearestY = min(max(point.y, minY), maxY)

            let leftDistance = abs(point.x - minX)
            let rightDistance = abs(point.x - maxX)
            let topDistance = abs(point.y - minY)
            let bottomDistance = abs(point.y - maxY)

            let minDistance = min(leftDistance, rightDistance, topDistance, bottomDistance)
            if minDistance == leftDistance {
                return CGPoint(x: minX, y: nearestY)
            }
            if minDistance == rightDistance {
                return CGPoint(x: maxX, y: nearestY)
            }
            if minDistance == topDistance {
                return CGPoint(x: nearestX, y: minY)
            }
            return CGPoint(x: nearestX, y: maxY)
        }
    }

    /// Chooses either the uploaded screenshot asset or a placeholder preview image.
    private var screenshotImage: Image {
        if UIImage(named: card.imageName) != nil {
            return Image(card.imageName)
        }
        return Image(systemName: "photo")
    }

    /// Calculates the exact image frame for `.scaledToFit` so annotations align correctly.
    private func fittedImageFrame(in containerSize: CGSize) -> CGRect {
        let containerRatio = containerSize.width / max(containerSize.height, 1)
        if containerRatio > imageAspectRatio {
            let fittedHeight = containerSize.height
            let fittedWidth = fittedHeight * imageAspectRatio
            let originX = (containerSize.width - fittedWidth) / 2
            return CGRect(x: originX, y: 0, width: fittedWidth, height: fittedHeight)
        }

        let fittedWidth = containerSize.width
        let fittedHeight = fittedWidth / imageAspectRatio
        let originY = (containerSize.height - fittedHeight) / 2
        return CGRect(x: 0, y: originY, width: fittedWidth, height: fittedHeight)
    }
}

/// Arrow path with a line segment and two head segments.
private struct TutorialArrowShape: Shape {
    /// Arrow tail point in parent coordinates.
    let start: CGPoint

    /// Arrow head point in parent coordinates.
    let end: CGPoint

    /// Creates an arrow path for this annotation.
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)

        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength: CGFloat = 12
        let headAngle: CGFloat = .pi / 6

        let left = CGPoint(
            x: end.x - headLength * cos(angle - headAngle),
            y: end.y - headLength * sin(angle - headAngle)
        )
        let right = CGPoint(
            x: end.x - headLength * cos(angle + headAngle),
            y: end.y - headLength * sin(angle + headAngle)
        )

        path.move(to: end)
        path.addLine(to: left)
        path.move(to: end)
        path.addLine(to: right)
        return path
    }
}
