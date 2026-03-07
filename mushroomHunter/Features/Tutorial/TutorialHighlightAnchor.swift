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
    /// Attendee confirmation queue button in room detail toolbar.
    case roomAttendeeConfirmationButton
    /// Host share button in room detail toolbar.
    case roomHostShareButton
    /// Host claim rewards button in room detail bottom dock.
    case roomHostClaimButton
    /// Postcard browse top action bar.
    case postcardBrowseTopActionBar
    /// Pinned ownership cards area in postcard browse grid.
    case postcardBrowsePinnedOwnershipArea
    /// Listing information section in postcard detail view.
    case postcardDetailInfoSection
    /// Buyer "Buy" button in postcard detail view.
    case postcardBuyerBuyButton
    /// Seller shipping button in postcard detail toolbar.
    case postcardSellerShippingButton
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
    /// Resolves one highlight frame using target anchors first, then normalized fallback rect.
    /// - Parameters:
    ///   - target: Optional live target identifier from tutorial config.
    ///   - fallbackNormalizedRect: Optional normalized fallback rectangle from tutorial config.
    ///   - anchors: Anchor map emitted by descendant views.
    ///   - proxy: Geometry proxy for converting anchor values.
    ///   - padding: Extra highlight padding applied around resolved frame.
    /// - Returns: Concrete frame in overlay coordinates, or nil when no highlight should be rendered.
    static func resolveFrame(
        target: TutorialHighlightTarget?,
        fallbackNormalizedRect: CGRect?,
        anchors: [TutorialHighlightTarget: [Anchor<CGRect>]],
        proxy: GeometryProxy,
        padding: CGFloat = 6
    ) -> CGRect? {
        if let target,
           let targetAnchors = anchors[target],
           targetAnchors.isEmpty == false {
            let mergedFrame = targetAnchors
                .map { proxy[$0] }
                .reduce(into: CGRect.null) { partialResult, nextFrame in
                    partialResult = partialResult.union(nextFrame)
                }
            if mergedFrame.isNull == false {
                return mergedFrame.insetBy(dx: -padding, dy: -padding)
            }
        }

        guard let fallbackNormalizedRect else { return nil }
        let fallbackFrame = CGRect(
            x: proxy.size.width * fallbackNormalizedRect.minX,
            y: proxy.size.height * fallbackNormalizedRect.minY,
            width: proxy.size.width * fallbackNormalizedRect.width,
            height: proxy.size.height * fallbackNormalizedRect.height
        )
        return fallbackFrame.insetBy(dx: -padding, dy: -padding)
    }
}
