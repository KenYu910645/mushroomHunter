//
//  TutorialHighlightAnchor.swift
//  mushroomHunter
//
//  Purpose:
//  - Provides tutorial highlight targets, anchor/frame resolution helpers, and floating overlay UI bridge.
//
import SwiftUI
import UIKit

/// Stable anchor IDs used by tutorial steps to resolve live highlight frames from real UI elements.
enum TutorialHighlightTarget: Hashable {
    /// Honey amount tag in Mushroom browse top action bar.
    case mushroomBrowseHoneyTag
    /// Search button in Mushroom browse top action bar.
    case mushroomBrowseSearchButton
    /// Create button in Mushroom browse top action bar.
    case mushroomBrowseCreateButton
    /// Daily reward calendar button in Mushroom browse navigation toolbar.
    case mushroomBrowseDailyRewardButton
    /// Event inbox bell button in Mushroom browse navigation toolbar.
    case mushroomBrowseEventInboxButton
    /// Pinned room rows area in Mushroom browse list.
    case mushroomBrowsePinnedRoomsArea
    /// Joinable room rows area in Mushroom browse list.
    case mushroomBrowseJoinableRoomsArea
    /// Header section in room detail view.
    case roomHeaderSection
    /// Top three attendee cards area in room detail tutorial view.
    case roomAttendeeTopThreeArea
    /// One attendee row in room detail attendee list, keyed by rendered row index.
    case roomAttendeeRow(index: Int)
    /// Host friend-code area inside the attendee list.
    case roomHostInfoFriendCodeArea
    /// First non-host attendee stats strip (status/honey/stars) inside attendee list.
    case roomFirstNonHostStatusStrip
    /// Pending join-request action buttons (approve/reject) for host flow.
    case roomPendingJoinActionButtons
    /// Attendee confirmation queue button in room detail toolbar.
    case roomAttendeeConfirmationButton
    /// Attendee edit-deposit button in room detail toolbar.
    case roomAttendeeEditDepositButton
    /// Host share button in room detail toolbar.
    case roomHostShareButton
    /// Host raid-history button in room detail toolbar.
    case roomHostRaidHistoryButton
    /// Host edit-room button in room detail toolbar.
    case roomHostEditRoomButton
    /// Host claim rewards button in room detail bottom dock.
    case roomHostClaimButton
    /// Honey amount tag in Postcard browse top action bar.
    case postcardBrowseHoneyTag
    /// Search button in Postcard browse top action bar.
    case postcardBrowseSearchButton
    /// Create button in Postcard browse top action bar.
    case postcardBrowseCreateButton
    /// Pinned ownership cards area in postcard browse grid.
    case postcardBrowsePinnedOwnershipArea
    /// Non-owned postcard cards area in postcard browse grid.
    case postcardBrowseGeneralListingsArea
    /// Postcard snapshot hero image in postcard detail view.
    case postcardDetailSnapshot
    /// Listing information section in postcard detail view.
    case postcardDetailInfoSection
    /// Buyer "Buy" button in postcard detail view.
    case postcardBuyerBuyButton
    /// Seller share button in postcard detail toolbar.
    case postcardSellerShareButton
    /// Seller shipping button in postcard detail toolbar.
    case postcardSellerShippingButton
    /// Seller edit button in postcard detail toolbar.
    case postcardSellerEditButton
}

extension TutorialHighlightTarget {
    /// Resolves one stable attendee-row target for a zero-based row index.
    /// - Parameter index: Row index shown in the attendee list.
    /// - Returns: Matching row target when index is non-negative.
    static func roomAttendeeRow(_ index: Int) -> TutorialHighlightTarget? {
        guard index >= 0 else { return nil }
        return .roomAttendeeRow(index: index)
    }

    /// Indicates this target belongs to top-right navigation toolbar actions.
    /// Toolbar targets need a floating top-level stroke to avoid being occluded by UIKit toolbar rendering.
    var isNavigationToolbarActionTarget: Bool {
        switch self {
        case .roomHostShareButton,
             .roomHostRaidHistoryButton,
             .roomHostEditRoomButton,
             .roomAttendeeConfirmationButton,
             .roomAttendeeEditDepositButton,
             .mushroomBrowseDailyRewardButton,
             .mushroomBrowseEventInboxButton,
             .postcardSellerShareButton,
             .postcardSellerShippingButton,
             .postcardSellerEditButton:
            return true
        default:
            return false
        }
    }

    /// Indicates resolver should use only the first matched anchor instead of unioning all anchors.
    /// This is used for per-row attendee targets so highlights stay tightly scoped to a single row.
    var shouldResolveWithFirstAnchorOnly: Bool {
        switch self {
        case .roomAttendeeRow,
             .roomHostInfoFriendCodeArea,
             .roomFirstNonHostStatusStrip,
             .roomPendingJoinActionButtons:
            return true
        default:
            return false
        }
    }

}

/// Preference payload that collects one or more anchors per tutorial target.
struct TutorialHighlightAnchorPreferenceKey: PreferenceKey {
    /// Merged anchor map collected from descendant views.
    static var defaultValue: [TutorialHighlightTarget: [Anchor<CGRect>]] = [:]

    /// Merges anchor maps emitted by descendant views.
    /// - Parameters:
    ///   - value: Current merged value.
    ///   - nextValue: Next descendant map value.
    static func reduce(
        value: inout [TutorialHighlightTarget: [Anchor<CGRect>]],
        nextValue: () -> [TutorialHighlightTarget: [Anchor<CGRect>]]
    ) {
        for (target, anchors) in nextValue() {
            value[target, default: []].append(contentsOf: anchors)
        }
    }
}

extension View {
    /// Registers this view's bounds as a tutorial highlight anchor for the specified target.
    /// - Parameter target: Stable target identifier consumed by tutorial steps.
    /// - Returns: View decorated with anchor preference for tutorial highlight resolution.
    @ViewBuilder
    func tutorialHighlightAnchor(_ target: TutorialHighlightTarget?) -> some View {
        if let target {
            self.anchorPreference(
                key: TutorialHighlightAnchorPreferenceKey.self,
                value: .bounds
            ) { anchor in
                [target: [anchor]]
            }
        } else {
            self
        }
    }

    /// Registers this view's bounds for multiple tutorial targets in one preference emission.
    /// Use this when one UI element should be targetable by more than one tutorial step id.
    /// - Parameter targets: Target identifiers that share the same bounds anchor.
    /// - Returns: View decorated with one merged anchor-preference payload.
    @ViewBuilder
    func tutorialHighlightAnchors(_ targets: [TutorialHighlightTarget]) -> some View {
        let validTargets = Array(Set(targets))
        if validTargets.isEmpty {
            self
        } else {
            self.anchorPreference(
                key: TutorialHighlightAnchorPreferenceKey.self,
                value: .bounds
            ) { anchor in
                Dictionary(uniqueKeysWithValues: validTargets.map { target in
                    (target, [anchor])
                })
            }
        }
    }
}

/// Utility namespace for converting tutorial target anchors into highlight rectangles.
enum TutorialHighlightFrameResolver {
    /// Resolves one highlight frame using target anchors only.
    /// - Parameters:
    ///   - target: Optional live target identifier from tutorial config.
    ///   - anchors: Anchor map emitted by descendant views.
    ///   - proxy: Geometry proxy for converting anchor values.
    ///   - padding: Extra highlight padding applied around resolved frame.
    /// - Returns: Concrete frame in overlay coordinates, or nil when no highlight should be rendered.
    static func resolveFrame(
        target: TutorialHighlightTarget?,
        anchors: [TutorialHighlightTarget: [Anchor<CGRect>]],
        proxy: GeometryProxy,
        padding: CGFloat = 6
    ) -> CGRect? {
        if let target,
           let targetAnchors = anchors[target],
           targetAnchors.isEmpty == false {
            if target.shouldResolveWithFirstAnchorOnly {
                let firstFrame = proxy[targetAnchors[0]]
                return firstFrame.insetBy(dx: -padding, dy: -padding)
            }
            let mergedFrame = targetAnchors
                .map { proxy[$0] }
                .reduce(into: CGRect.null) { partialResult, nextFrame in
                    partialResult = partialResult.union(nextFrame)
                }
            if mergedFrame.isNull == false {
                return mergedFrame.insetBy(dx: -padding, dy: -padding)
            }
        }
        return nil
    }

    /// Resolves tutorial message-box center Y with target-aware automatic placement.
    /// Placement policy:
    /// - Prefer below highlight when there is enough room.
    /// - Otherwise place above highlight.
    /// - If both sides are tight, choose the side with more remaining space.
    /// - For intro/no-highlight steps, use the shared default center position.
    /// - Parameters:
    ///   - highlightFrame: Resolved highlight frame for current step, if any.
    ///   - proxy: Geometry proxy of the tutorial overlay container.
    /// - Returns: Message-box center Y in overlay coordinates.
    static func resolveMessageBoxCenterY(
        highlightFrame: CGRect?,
        proxy: GeometryProxy
    ) -> CGFloat {
        /// Estimated half-height of tutorial message card used for collision avoidance.
        let estimatedMessageHalfHeight: CGFloat = 92
        /// Vertical spacing between highlight border and message card.
        let targetGap: CGFloat = 4
        /// Top boundary where message card center can safely sit.
        let topBoundary: CGFloat = estimatedMessageHalfHeight + 16
        /// Bottom boundary where message card center can safely sit.
        let bottomBoundary: CGFloat = proxy.size.height - estimatedMessageHalfHeight - 20

        /// Shared center Y used by intro/no-highlight steps.
        let defaultCenterY = max(topBoundary, min(0.6 * proxy.size.height, bottomBoundary))
        guard let highlightFrame else { return defaultCenterY }

        /// Preferred center Y when card is placed below the highlight.
        let preferredBelowCenterY = highlightFrame.maxY + targetGap + estimatedMessageHalfHeight
        /// Preferred center Y when card is placed above the highlight.
        let preferredAboveCenterY = highlightFrame.minY - targetGap - estimatedMessageHalfHeight

        let isBelowPlacementValid = preferredBelowCenterY <= bottomBoundary
        let isAbovePlacementValid = preferredAboveCenterY >= topBoundary
        if isBelowPlacementValid { return preferredBelowCenterY }
        if isAbovePlacementValid { return preferredAboveCenterY }

        /// Available space below highlight after preserving boundaries.
        let availableSpaceBelow = bottomBoundary - (highlightFrame.maxY + targetGap)
        /// Available space above highlight after preserving boundaries.
        let availableSpaceAbove = (highlightFrame.minY - targetGap) - topBoundary

        if availableSpaceBelow >= availableSpaceAbove {
            return min(preferredBelowCenterY, bottomBoundary)
        }
        return max(preferredAboveCenterY, topBoundary)
    }
}

/// SwiftUI bridge that controls a floating highlight-stroke window for tutorial toolbar targets.
struct TutorialHightlighAnchorUI: UIViewRepresentable {
    /// Optional screen-space frame for the highlight rectangle.
    let frame: CGRect?
    /// Whether the floating highlight feature should be active.
    let isVisible: Bool

    /// Builds coordinator that owns the floating window lifecycle.
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// Creates a transparent anchor view used to resolve the current scene window.
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }

    /// Updates floating highlight window with latest visibility and frame values.
    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.update(
            frame: frame,
            isVisible: isVisible,
            sourceWindow: uiView.window
        )
    }

    /// Cleans up floating resources when the bridge is removed.
    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.clear()
    }

    /// Coordinator that manages one non-interactive overlay window above the host scene.
    final class Coordinator {
        /// Floating overlay window used to render the topmost highlight stroke.
        private var overlayWindow: UIWindow?
        /// Hosting controller that renders SwiftUI highlight content inside the overlay window.
        private var hostingController: UIHostingController<TutorialFloatingHighlightOverlayView>?

        /// Updates overlay window visibility and highlight frame.
        /// - Parameters:
        ///   - frame: Optional screen-space frame for highlight stroke.
        ///   - isVisible: Whether overlay feature should remain active.
        ///   - sourceWindow: Window from the embedding SwiftUI hierarchy.
        func update(frame: CGRect?, isVisible: Bool, sourceWindow: UIWindow?) {
            guard isVisible, let sourceWindow else {
                clear()
                return
            }

            if overlayWindow == nil || overlayWindow?.windowScene !== sourceWindow.windowScene {
                buildOverlayWindow(sourceWindow: sourceWindow)
            }

            guard let overlayWindow, let hostingController else { return }
            hostingController.rootView = TutorialFloatingHighlightOverlayView(frame: frame)
            overlayWindow.isHidden = false
        }

        /// Builds floating overlay window within the same scene as the source window.
        /// - Parameter sourceWindow: Source scene window from current SwiftUI hierarchy.
        private func buildOverlayWindow(sourceWindow: UIWindow) {
            guard let windowScene = sourceWindow.windowScene else { return }
            let window = UIWindow(windowScene: windowScene)
            window.backgroundColor = .clear
            window.isUserInteractionEnabled = false
            window.windowLevel = sourceWindow.windowLevel + 2

            let hostingController = UIHostingController(
                rootView: TutorialFloatingHighlightOverlayView(frame: nil)
            )
            hostingController.view.backgroundColor = .clear

            window.rootViewController = hostingController
            window.isHidden = false

            self.overlayWindow = window
            self.hostingController = hostingController
        }

        /// Tears down floating overlay resources.
        func clear() {
            overlayWindow?.isHidden = true
            hostingController = nil
            overlayWindow = nil
        }
    }
}

/// Simple stroke-only overlay view rendered in the floating highlight window.
private struct TutorialFloatingHighlightOverlayView: View {
    /// Optional screen-space frame for the highlight stroke.
    let frame: CGRect?

    /// Highlight overlay body.
    var body: some View {
        ZStack {
            if let frame {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.yellow, lineWidth: 2)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}
