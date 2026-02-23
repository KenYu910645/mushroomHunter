//
//  ProfilePostcard.swift
//  mushroomHunter
//
//  Purpose:
//  - Hosts profile postcard list sections for on-shelf and ordered postcards.
//
import SwiftUI

/// On-shelf postcard list content shown in profile postcard section.
struct OnShelfPostcardsSection: View, Equatable {
    /// Postcard listings owned by the user.
    let postcards: [PostcardListing]

    /// Listing ids that currently have pending seller order queue items.
    let pendingOrderPostcardIds: Set<String>
    /// Pending seller-order counts grouped by postcard id.
    let pendingOrderCountsByPostcardId: [String: Int]

    /// Loading state for on-shelf postcard fetch.
    let isLoading: Bool

    /// Optional fetch error message for on-shelf postcards.
    let errorMessage: String?

    /// Row tap callback used to navigate to postcard detail.
    let onSelectPostcard: (PostcardListing) -> Void

    /// Equality gate used by `.equatable()` to skip unnecessary redraws.
    static func == (lhs: OnShelfPostcardsSection, rhs: OnShelfPostcardsSection) -> Bool {
        lhs.postcards == rhs.postcards
            && lhs.pendingOrderPostcardIds == rhs.pendingOrderPostcardIds
            && lhs.pendingOrderCountsByPostcardId == rhs.pendingOrderCountsByPostcardId
            && lhs.isLoading == rhs.isLoading
            && lhs.errorMessage == rhs.errorMessage
    }

    /// On-shelf postcard list rendering, including loading, empty, and error states.
    var body: some View {
        Group {
            Text(LocalizedStringKey("profile_postcard_onshelf_section"))
                .font(.subheadline.weight(.semibold))

            ProfileSectionStateView(
                isLoading: isLoading,
                isEmpty: postcards.isEmpty,
                errorMessage: errorMessage,
                loadingTextKey: LocalizedStringKey("profile_loading_onshelf_postcards")
            ) {
                ForEach(postcards) { postcard in
                    let statusKey = statusKey(for: postcard.id)
                    let statusUrgency = statusUrgency(for: postcard.id)
                    PostcardSummaryRow(
                        postcard: postcard,
                        statusKey: statusKey,
                        statusUrgency: statusUrgency,
                        actionCount: pendingOrderCountsByPostcardId[postcard.id] ?? 0,
                        isLocationVisible: false,
                        isPriceVisible: false
                    ) {
                        onSelectPostcard(postcard)
                    }
                }
            } emptyContent: {
                ContentUnavailableView(
                    LocalizedStringKey("profile_onshelf_empty_title"),
                    systemImage: "shippingbox"
                )
                .listRowBackground(Color.clear)
            }
        }
    }

    /// Maps on-shelf listing id to seller status text.
    /// - Parameter postcardId: Listing id being rendered in profile.
    /// - Returns: Localized status text key for on-shelf row.
    private func statusKey(for postcardId: String) -> LocalizedStringKey {
        let isOrderReceived = pendingOrderPostcardIds.contains(postcardId)
        return isOrderReceived
            ? LocalizedStringKey("profile_postcard_status_order_received")
            : LocalizedStringKey("profile_postcard_status_on_shelf")
    }

    /// Maps on-shelf listing id to seller status urgency color.
    /// - Parameter postcardId: Listing id being rendered in profile.
    /// - Returns: Urgency palette for on-shelf status badge.
    private func statusUrgency(for postcardId: String) -> ProfileStatusUrgency {
        let isOrderReceived = pendingOrderPostcardIds.contains(postcardId)
        return isOrderReceived ? .warning : .success
    }
}

/// Ordered postcard list content shown in profile postcard section.
struct OrderedPostcardsSection: View, Equatable {
    /// Postcards purchased by the user with current order status.
    let postcards: [OrderedPostcardSummary]

    /// Loading state for ordered postcard fetch.
    let isLoading: Bool

    /// Optional fetch error message for ordered postcards.
    let errorMessage: String?

    /// Row tap callback used to navigate to postcard detail.
    let onSelectPostcard: (OrderedPostcardSummary) -> Void

    /// Equality gate used by `.equatable()` to skip unnecessary redraws.
    static func == (lhs: OrderedPostcardsSection, rhs: OrderedPostcardsSection) -> Bool {
        lhs.postcards == rhs.postcards
            && lhs.isLoading == rhs.isLoading
            && lhs.errorMessage == rhs.errorMessage
    }

    /// Ordered postcard list rendering, including loading, empty, and error states.
    var body: some View {
        Group {
            Text(LocalizedStringKey("profile_postcard_ordered_section"))
                .font(.subheadline.weight(.semibold))

            ProfileSectionStateView(
                isLoading: isLoading,
                isEmpty: postcards.isEmpty,
                errorMessage: errorMessage,
                loadingTextKey: LocalizedStringKey("profile_loading_ordered_postcards")
            ) {
                ForEach(postcards) { postcardSummary in
                    PostcardSummaryRow(
                        postcard: postcardSummary.listing,
                        statusKey: statusKey(for: postcardSummary.status),
                        statusUrgency: statusUrgency(for: postcardSummary.status),
                        actionCount: actionCount(for: postcardSummary.status),
                        isLocationVisible: true,
                        isPriceVisible: true
                    ) {
                        onSelectPostcard(postcardSummary)
                    }
                }
            } emptyContent: {
                ContentUnavailableView(
                    LocalizedStringKey("profile_ordered_empty_title"),
                    systemImage: "cart"
                )
                .listRowBackground(Color.clear)
            }
        }
    }

    /// Maps order status to profile ordered-row status text.
    /// - Parameter status: Latest active order status.
    /// - Returns: Localized status text key for ordered section.
    private func statusKey(for status: PostcardOrderStatus) -> LocalizedStringKey {
        switch status {
        case .sellerConfirmPending, .awaitingShipping:
            return LocalizedStringKey("profile_postcard_status_wait_for_shipping")
        case .shipped:
            return LocalizedStringKey("profile_postcard_status_on_the_way")
        default:
            return LocalizedStringKey("profile_postcard_status_wait_for_shipping")
        }
    }

    /// Maps order status to profile badge urgency color.
    /// - Parameter status: Latest active order status.
    /// - Returns: Urgency palette for status badge.
    private func statusUrgency(for status: PostcardOrderStatus) -> ProfileStatusUrgency {
        switch status {
        case .sellerConfirmPending, .awaitingShipping:
            return .warning
        case .shipped:
            return .neutral
        default:
            return .warning
        }
    }

    /// Maps buyer order status to actionable badge count.
    /// - Parameter status: Latest buyer order status for a postcard row.
    /// - Returns: `1` when buyer should confirm receipt, otherwise `0`.
    private func actionCount(for status: PostcardOrderStatus) -> Int {
        let isWaitingBuyerReceive = status == .shipped
        return isWaitingBuyerReceive ? 1 : 0
    }
}

/// Reusable row style for postcard list items in profile tab.
private struct PostcardSummaryRow: View {
    /// Postcard model used to render title, location, and price.
    let postcard: PostcardListing
    /// Status text key shown in place of stock value.
    let statusKey: LocalizedStringKey
    /// Urgency palette that controls status badge color.
    let statusUrgency: ProfileStatusUrgency
    /// Actionable count used to determine whether row should show a leading red dot marker.
    let actionCount: Int
    /// Indicates whether location text should be displayed in this row.
    let isLocationVisible: Bool
    /// Indicates whether honey price chip should be displayed in this row.
    let isPriceVisible: Bool

    /// Tap callback for row selection.
    let onTap: () -> Void

    /// Shared postcard row layout used by on-shelf and ordered lists.
    var body: some View {
        Button {
            onTap()
        } label: {
            ProfileActionHighlightContainer(actionCount: actionCount) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(postcard.title)
                            .font(.headline)
                            .lineLimit(1)

                        if isLocationVisible {
                            Text(postcard.location.shortLabel)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .leading, spacing: 4) {
                        if isPriceVisible {
                            HStack(spacing: 4) {
                                Text("\(postcard.priceHoney)")
                                    .foregroundStyle(Color.orange)
                                    .monospacedDigit()
                            }
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.orange.opacity(0.14))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.orange.opacity(0.35), lineWidth: 1)
                            )
                        }

                        ProfileStatusBadge(
                            titleKey: statusKey,
                            urgency: statusUrgency
                        )
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}
