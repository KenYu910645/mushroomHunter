//
//  PostcardOrdersView.swift
//  mushroomHunter
//
//  Purpose:
//  - Renders seller shipping queue and shipment confirmation actions.
//
import SwiftUI
import UIKit

/// Seller shipping queue screen for one postcard listing.
struct PostcardOrdersView: View {
    /// Listing whose buyer queue is being managed.
    let postcard: PostcardListing

    /// Dismiss action for this sheet.
    @Environment(\.dismiss) private var dismiss
    /// Buyers currently waiting for seller to ship or decline.
    @State private var recipients: [PostcardShippingRecipient] = []
    /// Seller rating tasks that still need buyer stars after completion.
    @State private var ratingTasks: [PostcardOrderRatingContext] = []
    /// Indicates whether recipient list is loading.
    @State private var isLoading: Bool = false
    /// Order id currently being marked as shipped.
    @State private var isSendingOrderId: String? = nil
    /// Order id currently being rejected by seller.
    @State private var isRejectingOrderId: String? = nil
    /// Inline error message shown in the list.
    @State private var errorMessage: String?
    /// Controls shipment success alert visibility.
    @State private var isShipSuccessAlertPresented: Bool = false
    /// Recipient currently waiting for seller sent-confirmation.
    @State private var pendingSentConfirmationRecipient: PostcardShippingRecipient?
    /// Recipient currently waiting for seller reject-confirmation.
    @State private var pendingRejectConfirmationRecipient: PostcardShippingRecipient?
    /// Controls temporary copied toast visibility.
    @State private var isCopyToastVisible: Bool = false
    /// Firebase-backed repository for shipping actions.
    private let repo = FbPostcardRepo()
    /// Shared dirty-bit state used to invalidate postcard caches after seller order actions.
    private let dirtyBits = CacheDirtyBitStore.shared

    /// Main shipping queue UI.
    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            if isLoading && recipients.isEmpty && ratingTasks.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if recipients.isEmpty && ratingTasks.isEmpty {
                Text(LocalizedStringKey("postcard_shipping_empty"))
                    .foregroundStyle(.secondary)
            }

            if recipients.isEmpty == false {
                Section(LocalizedStringKey("postcard_shipping_section_title")) {
                    ForEach(recipients) { recipient in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(
                                String(
                                    format: NSLocalizedString("postcard_shipping_ordered_title_format", comment: ""),
                                    recipient.buyerName,
                                    postcard.title
                                )
                            )
                                .font(.headline)
                            friendRequestInstruction(for: recipient)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                            HStack(spacing: 8) {
                                Button {
                                    pendingSentConfirmationRecipient = recipient
                                } label: {
                                    if isSendingOrderId == recipient.id {
                                        ProgressView()
                                            .frame(maxWidth: .infinity)
                                    } else {
                                        Text(LocalizedStringKey("postcard_shipping_send_button"))
                                            .frame(maxWidth: .infinity)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(isPendingActionLocked)
                                .accessibilityIdentifier("postcard_shipping_send_button_\(recipient.id)")

                                Button {
                                    pendingRejectConfirmationRecipient = recipient
                                } label: {
                                    if isRejectingOrderId == recipient.id {
                                        ProgressView()
                                            .frame(maxWidth: .infinity)
                                    } else {
                                        Text(LocalizedStringKey("postcard_shipping_reject_button"))
                                            .frame(maxWidth: .infinity)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                                .disabled(isPendingActionLocked)
                                .accessibilityIdentifier("postcard_shipping_reject_button_\(recipient.id)")
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            if ratingTasks.isEmpty == false {
                Section(LocalizedStringKey("postcard_pending_ratings_section_title")) {
                    ForEach(ratingTasks) { ratingTask in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(
                                String(
                                    format: NSLocalizedString("postcard_rating_title_format", comment: ""),
                                    ratingTask.counterpartName
                                )
                            )
                                .font(.headline)

                            Text(Optional(ratingTask.completedAt).relativeShortString())
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 8) {
                                Button(LocalizedStringKey("room_msg_rate_one_star")) {
                                    Task { await submitSellerRating(task: ratingTask, stars: 1) }
                                }
                                .buttonStyle(.bordered)

                                Button(LocalizedStringKey("room_msg_rate_two_stars")) {
                                    Task { await submitSellerRating(task: ratingTask, stars: 2) }
                                }
                                .buttonStyle(.bordered)

                                Button(LocalizedStringKey("room_msg_rate_three_stars")) {
                                    Task { await submitSellerRating(task: ratingTask, stars: 3) }
                                }
                                .buttonStyle(.bordered)
                            }

                            Button(LocalizedStringKey("common_skip")) {
                                Task { await skipSellerRating(task: ratingTask) }
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle(LocalizedStringKey("postcard_shipping_title"))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(LocalizedStringKey("common_close")) {
                    dismiss()
                }
                .accessibilityIdentifier("postcard_shipping_close_button")
            }
        }
        .task {
            await loadRecipients()
        }
        .refreshable {
            await loadRecipients()
        }
        .overlay {
            if let recipient = pendingSentConfirmationRecipient {
                MessageBox(
                    title: NSLocalizedString("postcard_msg_sent_confirm_title", comment: ""),
                    message: String(
                        format: NSLocalizedString("postcard_msg_sent_confirm_message_format", comment: ""),
                        postcard.title,
                        recipient.buyerName
                    ),
                    buttons: [
                        MessageBoxButton(
                            id: "postcard_shipping_sent_confirm_yes",
                            title: NSLocalizedString("postcard_msg_sent_confirm_yes_button", comment: "")
                        ) {
                            pendingSentConfirmationRecipient = nil
                            Task { await markSent(recipient) }
                        },
                        MessageBoxButton(
                            id: "postcard_shipping_sent_confirm_cancel",
                            title: NSLocalizedString("common_cancel", comment: ""),
                            role: .cancel
                        ) {
                            pendingSentConfirmationRecipient = nil
                        }
                    ]
                )
            } else if let recipient = pendingRejectConfirmationRecipient {
                MessageBox(
                    title: NSLocalizedString("postcard_msg_reject_confirm_title", comment: ""),
                    message: NSLocalizedString("postcard_msg_reject_confirm_message", comment: ""),
                    buttons: [
                        MessageBoxButton(
                            id: "postcard_shipping_reject_confirm_reject",
                            title: NSLocalizedString("postcard_msg_reject_confirm_reject_button", comment: ""),
                            role: .destructive
                        ) {
                            pendingRejectConfirmationRecipient = nil
                            Task { await rejectOrder(recipient) }
                        },
                        MessageBoxButton(
                            id: "postcard_shipping_reject_confirm_cancel",
                            title: NSLocalizedString("common_cancel", comment: ""),
                            role: .cancel
                        ) {
                            pendingRejectConfirmationRecipient = nil
                        }
                    ]
                )
            } else if isShipSuccessAlertPresented {
                MessageBox(
                    title: NSLocalizedString("postcard_msg_shipping_sent_title", comment: ""),
                    message: NSLocalizedString("postcard_msg_shipping_sent_message", comment: ""),
                    buttons: [
                        MessageBoxButton(
                            id: "postcard_shipping_sent_ok",
                            title: NSLocalizedString("common_ok", comment: "")
                        ) {
                            isShipSuccessAlertPresented = false
                        }
                    ]
                )
            }
        }
        .overlay(alignment: .top) {
            if isCopyToastVisible {
                Text(LocalizedStringKey("common_copied"))
                    .font(.footnote)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    /// Renders the friend-request instruction line with inline copy-code action.
    /// - Parameter recipient: Buyer currently awaiting seller shipment.
    /// - Returns: View containing localized instruction text and copy icon.
    @ViewBuilder
    private func friendRequestInstruction(for recipient: PostcardShippingRecipient) -> some View {
        let displayCode = formattedFriendCode(raw: recipient.buyerFriendCode)
        let prefixText = String(
            format: NSLocalizedString("postcard_shipping_friend_request_prefix_format", comment: ""),
            recipient.buyerName
        )
        let codePrefixText = NSLocalizedString("postcard_shipping_friend_request_code_prefix", comment: "")
        let suffixText = NSLocalizedString("postcard_shipping_friend_request_suffix", comment: "")

        Button {
            copyFriendCode(recipient.buyerFriendCode)
        } label: {
            (
                Text(prefixText) +
                Text(codePrefixText) +
                Text(displayCode) +
                Text(" ") +
                Text(Image(systemName: "doc.on.doc")) +
                Text(suffixText)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    /// Formats buyer friend code for seller display.
    /// - Parameter raw: Raw buyer friend code text.
    /// - Returns: Grouped 3-3-3 friend code when valid; otherwise fallback marker.
    private func formattedFriendCode(raw: String) -> String {
        let digits = FriendCode.digitsOnly(raw)
        guard digits.isEmpty == false else {
            return "-"
        }
        return FriendCode.formatted(digits)
    }

    /// Copies buyer friend code digits into clipboard.
    /// - Parameter raw: Raw buyer friend code text.
    private func copyFriendCode(_ raw: String) {
        let digits = FriendCode.digitsOnly(raw)
        guard digits.isEmpty == false else { return }
        UIPasteboard.general.string = digits
        showCopiedToast()
    }

    /// Shows a short-lived copied toast message.
    private func showCopiedToast() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isCopyToastVisible = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isCopyToastVisible = false
                }
            }
        }
    }

    /// Indicates whether any seller order action is currently executing.
    private var isPendingActionLocked: Bool {
        isSendingOrderId != nil || isRejectingOrderId != nil
    }

    /// Loads current shipping recipients for the listing.
    private func loadRecipients() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        if AppTesting.useMockPostcards {
            recipients = AppTesting.fixtureShippingRecipients()
            ratingTasks = []
            return
        }

        do {
            recipients = try await repo.fetchShippingRecipients(postcardId: postcard.id)
            ratingTasks = try await repo.fetchPendingSellerRatingContexts(postcardId: postcard.id)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Marks one recipient order as shipped.
    /// - Parameter recipient: Buyer order recipient to mark as sent.
    private func markSent(_ recipient: PostcardShippingRecipient) async {
        guard !isPendingActionLocked else { return }
        isSendingOrderId = recipient.id
        defer { isSendingOrderId = nil }

        if AppTesting.useMockPostcards {
            recipients.removeAll { $0.id == recipient.id }
            isShipSuccessAlertPresented = true
            return
        }

        do {
            try await repo.markPostcardSent(orderId: recipient.id)
            await dirtyBits.markPostcardDetailDirty(postcardId: postcard.id)
            recipients.removeAll { $0.id == recipient.id }
            isShipSuccessAlertPresented = true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Rejects one pending order and refunds buyer.
    /// - Parameter recipient: Pending order recipient.
    private func rejectOrder(_ recipient: PostcardShippingRecipient) async {
        guard !isPendingActionLocked else { return }
        isRejectingOrderId = recipient.id
        defer { isRejectingOrderId = nil }

        if AppTesting.useMockPostcards {
            recipients.removeAll { $0.id == recipient.id }
            return
        }

        do {
            try await repo.sellerRejectOrder(orderId: recipient.id)
            await dirtyBits.markPostcardBrowseDirty()
            await dirtyBits.markPostcardDetailDirty(postcardId: postcard.id)
            recipients.removeAll { $0.id == recipient.id }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Submits seller-side rating for one completed order row.
    /// - Parameters:
    ///   - task: Pending seller rating task.
    ///   - stars: Number of stars selected by seller.
    private func submitSellerRating(task: PostcardOrderRatingContext, stars: Int) async {
        do {
            try await repo.rateBuyerAfterCompletion(orderId: task.id, stars: stars)
            await dirtyBits.markPostcardDetailDirty(postcardId: postcard.id)
            ratingTasks.removeAll { $0.id == task.id }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Permanently skips seller-side rating for one completed order row.
    /// - Parameter task: Pending seller rating task.
    private func skipSellerRating(task: PostcardOrderRatingContext) async {
        do {
            try await repo.skipBuyerRatingAfterCompletion(orderId: task.id)
            await dirtyBits.markPostcardDetailDirty(postcardId: postcard.id)
            ratingTasks.removeAll { $0.id == task.id }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
