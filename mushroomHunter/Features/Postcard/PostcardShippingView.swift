//
//  PostcardShippingView.swift
//  mushroomHunter
//
//  Purpose:
//  - Renders seller shipping queue and shipment confirmation actions.
//
import SwiftUI

/// Seller shipping queue screen for one postcard listing.
struct PostcardShippingView: View {
    /// Listing whose buyer queue is being managed.
    let postcard: PostcardListing

    /// Dismiss action for this sheet.
    @Environment(\.dismiss) private var dismiss
    /// Buyers currently waiting for seller shipping confirmation.
    @State private var recipients: [PostcardShippingRecipient] = []
    /// Indicates whether recipient list is loading.
    @State private var isLoading: Bool = false
    /// Order id currently being marked as shipped.
    @State private var isSendingOrderId: String? = nil
    /// Inline error message shown in the list.
    @State private var errorMessage: String?
    /// Controls shipment success alert visibility.
    @State private var isShipSuccessAlertPresented: Bool = false
    /// Firebase-backed repository for shipping actions.
    private let repo = FbPostcardRepo()

    /// Main shipping queue UI.
    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            if isLoading && recipients.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if recipients.isEmpty {
                Text(LocalizedStringKey("postcard_shipping_empty"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recipients) { recipient in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(recipient.buyerName)
                            .font(.headline)
                        Text(
                            String(
                                format: NSLocalizedString("postcard_shipping_friend_code_format", comment: ""),
                                recipient.buyerFriendCode.isEmpty ? "-" : recipient.buyerFriendCode
                            )
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                        Button {
                            Task { await markSent(recipient) }
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
                        .disabled(isSendingOrderId != nil)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle(LocalizedStringKey("postcard_shipping_title"))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(LocalizedStringKey("common_close")) {
                    dismiss()
                }
            }
        }
        .task {
            await loadRecipients()
        }
        .refreshable {
            await loadRecipients()
        }
        .alert(LocalizedStringKey("postcard_shipping_sent_title"), isPresented: $isShipSuccessAlertPresented) {
            Button(LocalizedStringKey("common_ok")) {}
        } message: {
            Text(LocalizedStringKey("postcard_shipping_sent_message"))
        }
    }

    /// Loads current shipping recipients for the listing.
    private func loadRecipients() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            recipients = try await repo.fetchShippingRecipients(postcardId: postcard.id)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Marks one recipient order as shipped.
    /// - Parameter recipient: Buyer order recipient to mark as sent.
    private func markSent(_ recipient: PostcardShippingRecipient) async {
        guard isSendingOrderId == nil else { return }
        isSendingOrderId = recipient.id
        defer { isSendingOrderId = nil }

        do {
            try await repo.markPostcardSent(orderId: recipient.id)
            recipients.removeAll { $0.id == recipient.id }
            isShipSuccessAlertPresented = true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
