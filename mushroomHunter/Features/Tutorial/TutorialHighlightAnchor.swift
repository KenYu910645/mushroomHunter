//
//  TutorialHighlightAnchor.swift
//  mushroomHunter
//
//  Purpose:
//  - Provides reusable tutorial highlight anchor IDs and geometry resolution helpers.
//
import SwiftUI

/// Stable anchor IDs used by tutorial steps to resolve live highlight frames from real UI elements.
enum TutorialHighlightTarget: String, Hashable {
    /// Honey amount tag in Mushroom browse top action bar.
    case mushroomBrowseHoneyTag
    /// Search button in Mushroom browse top action bar.
    case mushroomBrowseSearchButton
    /// Create button in Mushroom browse top action bar.
    case mushroomBrowseCreateButton
    /// Pinned room rows area in Mushroom browse list.
    case mushroomBrowsePinnedRoomsArea
    /// Joinable room rows area in Mushroom browse list.
    case mushroomBrowseJoinableRoomsArea
    /// Header section in room detail view.
    case roomHeaderSection
    /// Attendee section in room detail view.
    case roomAttendeeSection
    /// Attendee row #0 in room detail attendee list.
    case roomAttendeeRow0
    /// Attendee row #1 in room detail attendee list.
    case roomAttendeeRow1
    /// Attendee row #2 in room detail attendee list.
    case roomAttendeeRow2
    /// Attendee row #3 in room detail attendee list.
    case roomAttendeeRow3
    /// Attendee row #4 in room detail attendee list.
    case roomAttendeeRow4
    /// Attendee row #5 in room detail attendee list.
    case roomAttendeeRow5
    /// Attendee row #6 in room detail attendee list.
    case roomAttendeeRow6
    /// Attendee row #7 in room detail attendee list.
    case roomAttendeeRow7
    /// Attendee row #8 in room detail attendee list.
    case roomAttendeeRow8
    /// Attendee row #9 in room detail attendee list.
    case roomAttendeeRow9
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
    /// Postcard browse top action bar.
    case postcardBrowseTopActionBar
    /// Honey amount tag in Postcard browse top action bar.
    case postcardBrowseHoneyTag
    /// Search button in Postcard browse top action bar.
    case postcardBrowseSearchButton
    /// Create button in Postcard browse top action bar.
    case postcardBrowseCreateButton
    /// Pinned ownership cards area in postcard browse grid.
    case postcardBrowsePinnedOwnershipArea
    /// Listing information section in postcard detail view.
    case postcardDetailInfoSection
    /// Buyer "Buy" button in postcard detail view.
    case postcardBuyerBuyButton
    /// Seller shipping button in postcard detail toolbar.
    case postcardSellerShippingButton
}

extension TutorialHighlightTarget {
    /// Resolves one stable attendee-row target for a zero-based row index.
    /// - Parameter index: Row index shown in the attendee list.
    /// - Returns: Matching row target when index is in supported range.
    static func roomAttendeeRow(_ index: Int) -> TutorialHighlightTarget? {
        switch index {
        case 0:
            return .roomAttendeeRow0
        case 1:
            return .roomAttendeeRow1
        case 2:
            return .roomAttendeeRow2
        case 3:
            return .roomAttendeeRow3
        case 4:
            return .roomAttendeeRow4
        case 5:
            return .roomAttendeeRow5
        case 6:
            return .roomAttendeeRow6
        case 7:
            return .roomAttendeeRow7
        case 8:
            return .roomAttendeeRow8
        case 9:
            return .roomAttendeeRow9
        default:
            return nil
        }
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
             .postcardSellerShippingButton:
            return true
        default:
            return false
        }
    }

    /// Indicates resolver should use only the first matched anchor instead of unioning all anchors.
    /// This is used for per-row attendee targets so highlights stay tightly scoped to a single row.
    var shouldResolveWithFirstAnchorOnly: Bool {
        switch self {
        case .roomAttendeeRow0,
             .roomAttendeeRow1,
             .roomAttendeeRow2,
             .roomAttendeeRow3,
             .roomAttendeeRow4,
             .roomAttendeeRow5,
             .roomAttendeeRow6,
             .roomAttendeeRow7,
             .roomAttendeeRow8,
             .roomAttendeeRow9:
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
