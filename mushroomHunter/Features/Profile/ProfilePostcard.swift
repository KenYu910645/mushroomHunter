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

    /// Loading state for on-shelf postcard fetch.
    let isLoading: Bool

    /// Optional fetch error message for on-shelf postcards.
    let errorMessage: String?

    /// Row tap callback used to navigate to postcard detail.
    let onSelectPostcard: (PostcardListing) -> Void

    /// Equality gate used by `.equatable()` to skip unnecessary redraws.
    static func == (lhs: OnShelfPostcardsSection, rhs: OnShelfPostcardsSection) -> Bool {
        lhs.postcards == rhs.postcards
            && lhs.isLoading == rhs.isLoading
            && lhs.errorMessage == rhs.errorMessage
    }

    /// On-shelf postcard list rendering, including loading, empty, and error states.
    var body: some View {
        Group {
            Text(LocalizedStringKey("profile_postcard_onshelf_section"))
                .font(.subheadline.weight(.semibold))

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            if isLoading && postcards.isEmpty {
                HStack {
                    ProgressView()
                    Text(LocalizedStringKey("profile_loading_onshelf_postcards"))
                        .foregroundStyle(.secondary)
                }
            } else if postcards.isEmpty {
                ContentUnavailableView(
                    LocalizedStringKey("profile_onshelf_empty_title"),
                    systemImage: "shippingbox"
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(postcards) { postcard in
                    PostcardSummaryRow(postcard: postcard) {
                        onSelectPostcard(postcard)
                    }
                }
            }
        }
    }
}

/// Ordered postcard list content shown in profile postcard section.
struct OrderedPostcardsSection: View, Equatable {
    /// Postcards purchased by the user.
    let postcards: [PostcardListing]

    /// Loading state for ordered postcard fetch.
    let isLoading: Bool

    /// Optional fetch error message for ordered postcards.
    let errorMessage: String?

    /// Row tap callback used to navigate to postcard detail.
    let onSelectPostcard: (PostcardListing) -> Void

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

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            if isLoading && postcards.isEmpty {
                HStack {
                    ProgressView()
                    Text(LocalizedStringKey("profile_loading_ordered_postcards"))
                        .foregroundStyle(.secondary)
                }
            } else if postcards.isEmpty {
                ContentUnavailableView(
                    LocalizedStringKey("profile_ordered_empty_title"),
                    systemImage: "cart"
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(postcards) { postcard in
                    PostcardSummaryRow(postcard: postcard) {
                        onSelectPostcard(postcard)
                    }
                }
            }
        }
    }
}

/// Reusable row style for postcard list items in profile tab.
private struct PostcardSummaryRow: View {
    /// Postcard model used to render title, location, price, and stock.
    let postcard: PostcardListing

    /// Tap callback for row selection.
    let onTap: () -> Void

    /// Shared postcard row layout used by on-shelf and ordered lists.
    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(postcard.title)
                        .font(.headline)
                        .lineLimit(1)

                    Text(postcard.location.shortLabel)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("\(postcard.priceHoney)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()

                        Image("HoneyIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 12, height: 12)
                    }

                    Text("x\(postcard.stock)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .buttonStyle(.plain)
    }
}
